#!/usr/bin/env bash
# Purpura's own updates, for the updater (Updater.qml) once "Follow Purpura
# versioning" is on in Settings > General > Updater.
#
# A version of purpura is a commit of the checkout it was installed from.
# purpura.sh records which checkout and which commit it installed (in
# ~/.local/state/purpura); a new version is anything newer on that
# checkout's upstream branch. With the configs linked to the checkout
# (./purpura.sh --link), what's installed is simply what it has checked out.
#
# usage: purpura-update.sh check   fetch the upstream and print where things
#                                  stand, as one line of JSON
#        purpura-update.sh apply   pull the checkout and install what that
#                                  brings (purpura.sh --update) - interactive,
#                                  run in the updater's terminal
set -uo pipefail

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/purpura

# The checkout purpura.sh recorded; failing that, the one ~/.config/quickshell
# links into.
find_checkout() {
    local dir=""
    if [[ -r $state_dir/checkout ]]; then
        dir=$(<"$state_dir/checkout")
    fi
    if [[ -z $dir || ! -f $dir/purpura.sh ]]; then
        dir=$(realpath -- "$HOME/.config/quickshell" 2>/dev/null) || dir=""
        dir=${dir%/.config/quickshell}
        [[ -n $dir && -f $dir/purpura.sh ]] || dir=""
    fi
    printf '%s' "$dir"
}

is_linked() {
    [[ -L $HOME/.config/quickshell && $(realpath -- "$HOME/.config/quickshell") == "$1/.config/quickshell" ]]
}

# The installed commit, or nothing when purpura.sh never recorded one (or it's
# gone from the checkout's history).
installed_commit() {
    local dir=$1 recorded
    if is_linked "$dir"; then
        git -C "$dir" rev-parse HEAD
        return
    fi
    [[ -r $state_dir/commit ]] || return 0
    recorded=$(<"$state_dir/commit")
    git -C "$dir" rev-parse --verify --quiet "$recorded^{commit}" || true
}

check() {
    local dir upstream installed known=true fetch_failed=false dirty=false linked=false latest
    dir=$(find_checkout)
    if [[ -z $dir ]]; then
        jq -cn '{state: "no-checkout"}'
        return
    fi
    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        jq -cn --arg dir "$dir" '{state: "not-git", checkout: $dir}'
        return
    fi
    if ! upstream=$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
        jq -cn --arg dir "$dir" '{state: "no-upstream", checkout: $dir}'
        return
    fi

    # In the background, so it must never stop to ask for credentials.
    if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
        timeout 60 git -C "$dir" fetch --quiet &>/dev/null; then
        fetch_failed=true
    fi

    is_linked "$dir" && linked=true
    installed=$(installed_commit "$dir")
    if [[ -z $installed ]]; then
        known=false
        installed=$(git -C "$dir" rev-parse HEAD)
    fi
    latest=$(git -C "$dir" rev-parse '@{u}')
    if [[ -n $(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null) ]]; then
        dirty=true
    fi

    jq -cn \
        --arg dir "$dir" \
        --arg upstream "$upstream" \
        --argjson linked "$linked" \
        --argjson installedKnown "$known" \
        --arg installed "$installed" \
        --arg installedShort "$(git -C "$dir" rev-parse --short "$installed")" \
        --arg installedDate "$(git -C "$dir" log -1 --format=%cs "$installed")" \
        --arg latest "$latest" \
        --arg latestShort "$(git -C "$dir" rev-parse --short "$latest")" \
        --arg latestDate "$(git -C "$dir" log -1 --format=%cs "$latest")" \
        --arg latestSubject "$(git -C "$dir" log -1 --format=%s "$latest")" \
        --argjson behind "$(git -C "$dir" rev-list --count "$installed..$latest")" \
        --argjson localCommits "$(git -C "$dir" rev-list --count '@{u}..HEAD')" \
        --argjson dirty "$dirty" \
        --argjson fetchFailed "$fetch_failed" \
        '{state: "ok", checkout: $dir, upstream: $upstream, linked: $linked,
          installedKnown: $installedKnown, installed: $installed,
          installedShort: $installedShort, installedDate: $installedDate,
          latest: $latest, latestShort: $latestShort, latestDate: $latestDate,
          latestSubject: $latestSubject, behind: $behind,
          localCommits: $localCommits, dirty: $dirty, fetchFailed: $fetchFailed}'
}

say() { printf '\n\e[1m:: %s\e[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '\e[1;33m!!\e[0m %s\n' "$*" >&2; }

# A new version makes the shell reload, and a reload is no time to have the
# lock screen running: should the new version have changed how the lock
# screen is put together, the reload would leave the session locked with
# nothing to unlock it. So if the screen got locked while the packages
# were updating, this waits for it to be unlocked. (Linked configs change
# with the pull itself, so this comes before that.)
wait_until_unlocked() {
    local told=0
    while [[ $(qs ipc call lockscreen isLocked 2>/dev/null) == true ]]; do
        if ((!told)); then
            info "The screen is locked - carrying on once it's unlocked."
            told=1
        fi
        sleep 5
    done
}

# Quickshell reloads the moment one of its files changes, and a reload in the
# middle of many changing, the rest still the old ones, can bring the whole
# shell down. A copied config is purpura.sh's to look after: it stops the
# shell while it replaces the files. A linked one changes with the pull
# itself, so for that the shell's stopped here first - hyprsunset with it,
# which it respawns - and started again once everything's done (on exit),
# through Hyprland, as at login. Only when it can be: in Hyprland.
SHELL_STOPPED=0

shell_pids() {
    pgrep -u "$EUID" -x 'qs|quickshell' || true
}

stop_shell_for_pull() {
    local dir=$1 try pid alive
    local -a pids=()
    mapfile -t pids < <(shell_pids)
    ((${#pids[@]})) || return 0
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null || return 0
    # Only when the pull changes the shell's files.
    git -C "$dir" fetch --quiet 2>/dev/null || return 0
    git -C "$dir" diff --quiet HEAD '@{u}' -- .config/quickshell 2>/dev/null && return 0
    info "Stopping the shell while its files change - it starts again at the end."
    mapfile -t -O "${#pids[@]}" pids < <(pgrep -u "$EUID" -x hyprsunset || true)
    SHELL_STOPPED=1
    trap start_shell EXIT
    kill -TERM -- "${pids[@]}" 2>/dev/null
    for ((try = 0; try < 50; try++)); do
        alive=0
        for pid in "${pids[@]}"; do
            kill -0 -- "$pid" 2>/dev/null && alive=1
        done
        ((alive)) || return 0
        sleep 0.1
    done
    kill -KILL -- "${pids[@]}" 2>/dev/null
}

start_shell() {
    local out try
    ((SHELL_STOPPED)) || return 0
    SHELL_STOPPED=0
    [[ -z $(shell_pids) ]] || return 0
    out=$(hyprctl dispatch 'hl.dsp.exec_cmd("qs")' 2>&1)
    if [[ $out != *ok* ]]; then
        warn "Couldn't start the shell again (${out:-no answer from Hyprland}) - start it with: qs"
        return 0
    fi
    # Up before this exits - so the updater's own check, right after, reaches it.
    for ((try = 0; try < 50; try++)); do
        [[ -n $(qs ipc call lockscreen isLocked 2>/dev/null) ]] && break
        sleep 0.2
    done
    info "The shell's running again."
}

apply() {
    local dir before after installed
    say "Purpura"
    dir=$(find_checkout)
    if [[ -z $dir ]]; then
        warn "Couldn't find the checkout purpura was installed from. Run ./purpura.sh --install from it once, so the updater knows where it is."
        return 1
    fi
    wait_until_unlocked
    info "Updating ${dir/#$HOME/\~}"
    before=$(git -C "$dir" rev-parse HEAD) || return 1
    if is_linked "$dir"; then
        stop_shell_for_pull "$dir"
    fi
    # Fast-forward only: local commits or edits in the way are yours to sort
    # out, not something to merge or throw away from here.
    if ! git -C "$dir" pull --ff-only; then
        warn "Couldn't fast-forward it to its upstream: it has commits or changes of its own in the way. Run git pull there by hand, then ./purpura.sh --update."
        return 1
    fi
    after=$(git -C "$dir" rev-parse HEAD)
    installed=$(installed_commit "$dir")
    if is_linked "$dir"; then
        installed=$before
    fi
    if [[ $installed == "$after" ]]; then
        info "You're on the newest version - nothing to install."
        return 0
    fi
    bash "$dir/purpura.sh" --update
}

case ${1:-} in
    check) check ;;
    apply) apply ;;
    *)
        printf 'usage: %s check|apply\n' "${0##*/}" >&2
        exit 2
        ;;
esac

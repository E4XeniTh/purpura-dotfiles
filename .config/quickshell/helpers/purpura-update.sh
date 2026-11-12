#!/usr/bin/env bash
# Purpura's own updates, for the updater (Updater.qml) once "Follow Purpura
# versioning" is on in Settings > Shell > Updater.
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

apply() {
    local dir before after installed
    say "Purpura"
    dir=$(find_checkout)
    if [[ -z $dir ]]; then
        warn "Couldn't find the checkout purpura was installed from. Run ./purpura.sh --install from it once, so the updater knows where it is."
        return 1
    fi
    info "Updating ${dir/#$HOME/\~}"
    before=$(git -C "$dir" rev-parse HEAD) || return 1
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

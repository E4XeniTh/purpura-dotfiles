#!/usr/bin/env bash
# purpura-dotfiles installer: the packages it needs, the configs
# themselves, and a highlight color applied across them. On its own it only
# shows the help. --install does the work and is safe to re-run - e.g.
# `./purpura.sh --install --no-packages` just to switch to another color.
# `./purpura.sh --link` links the configs to this checkout instead.
set -euo pipefail

# Physical path: it's compared against realpath results below.
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# The color every themed file in the repo is written in; installed copies
# are recolored from it.
BASE_COLOR=9600fa
STATE_FILE=${XDG_STATE_HOME:-$HOME/.local/state}/purpura/highlight
RECOLOR=(python3 -I "$REPO/install/recolor.py")

ASSUME_YES=0
INSTALL=0
INSTALL_PACKAGES=1
CORE_ONLY=0
TOGGLE_LINKS=0
COLOR=""
KB_LAYOUT=""
NOCONFIRM=()
STAGE=""
SEEDED=()
DOTFILES_INSTALLED=0
CONFIGS_CHANGED=0
CLOSE_APPS=0
APPS_RESTARTED=0

LAYOUTS=(
    "us US"
    "hr HR (Croatian)"
)

PRESETS=(
    "purple 9600fa"
    "red ff1f3d"
    "orange ff6a00"
    "yellow ffcc00"
    "green 00d062"
    "cyan 00c8ff"
    "blue 2f5bff"
    "pink ff2fa0"
    "white e6e6e6"
)

CORE_PACKAGES=(
    # compositor + session
    hyprland hyprpaper hyprpolkitagent hyprsunset hyprshutdown
    xdg-desktop-portal xdg-desktop-portal-hyprland
    # the shell
    quickshell qt6-5compat kservice
    # audio, devices, network
    pipewire pipewire-pulse wireplumber libpulse libcava
    networkmanager bluez bluez-utils upower ddcutil playerctl
    # clipboard, screenshots, notifications
    wl-clipboard cliphist grim imagemagick libnotify
    # tools the shell and scripts call
    jq curl python xembedsniproxy
    # terminal + GTK/Qt theming
    kitty qt6ct-kde kvantum breeze-gtk breeze-icons kde-gtk-config
    papirus-icon-theme ttf-hack noto-fonts quintom-cursor-theme-git
    # building the lock screen / visualizer helpers
    base-devel git pam
)

# Packages whose program can also come from a bigger package that doesn't
# declare it - plasma-workspace ships its own xembedsniproxy - so pacman counts
# them as missing, and installing them then clashes over the file.
# package:program - skipped when the program is already there.
SHIPPED_ELSEWHERE=(
    "xembedsniproxy:xembedsniproxy"
)

# default (y/n) | question | packages
OPTIONAL_GROUPS=(
    "y|Apps the keybinds open: rofi, Dolphin|rofi dolphin"
    "y|fish shell + fastfetch (the terminal greeting)|fish fastfetch"
    "n|Solaar (Logitech mice/keyboards: battery list, sensitivity setting)|solaar"
)

# What a color change stops besides windows, which often have none open:
# pgrep -x pattern : the command that brings it back, in autostart order.
# hyprsunset is respawned by qs, and an orphaned one would make that fail.
# Solaar is brought back by apply-peripherals.sh, if it's set to autostart.
SESSION_PROGRAMS=(
    "hyprpolkitagent:/usr/lib/hyprpolkitagent/hyprpolkitagent"
    "hyprpaper:hyprpaper"
    "qs|quickshell:qs"
    "hyprsunset:"
    "solaar:"
    "rofi:"
    "zapzap:"
)

# ---------------- output ----------------
ACCENT="150;0;250"

say() { printf '\n\e[1;38;2;%sm::\e[0m \e[1m%s\e[0m\n' "$ACCENT" "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '\e[1;33m!!\e[0m %s\n' "$*" >&2; }
die() { printf '\e[1;31mxx\e[0m %s\n' "$*" >&2; exit 1; }

# ask QUESTION y|n - succeeds on yes; --yes takes the default.
ask() {
    local reply hint
    hint=$([[ $2 == y ]] && echo Y/n || echo y/N)
    if ((ASSUME_YES)); then
        [[ $2 == y ]]
        return
    fi
    read -r -p "   $1 [$hint] " reply || reply=""
    [[ ${reply:-$2} == [Yy]* ]]
}

usage() {
    cat <<EOF
Usage: ./purpura.sh --install [options]
       ./purpura.sh --update
       ./purpura.sh --link

With neither, it only shows this help.

--install installs purpura-dotfiles: the packages it needs (pacman + AUR),
its configs into ~/.config, and a highlight color applied across them.
Anything it would overwrite is backed up first.

Changing the color inside Hyprland closes everything that's open when it
finishes, so nothing stays in the old color. It warns and asks first.

      --install      install; --color, --yes and --no-packages need it
  -c, --color HEX    highlight color, e.g. 00c8ff (skips the color menu)
  -y, --yes          don't ask anything, take the defaults
      --no-packages  skip installing packages, e.g. to just change color
      --update       what the shell's updater runs after pulling a new
                     version: --install --yes, keeping your color and
                     keyboard layout, and only adding core packages that
                     are missing (never the optional apps)
      --link         link the configs to this checkout instead of installing
                     anything, so editing the repo edits the live config; if
                     anything is linked already, every link is replaced with
                     a real copy instead. fish and the GTK folders are
                     never linked, since they get rewritten as they're
                     used. Takes no other options
  -h, --help         show this help
EOF
}

parse_args() {
    local argc=$#
    while (($#)); do
        case $1 in
            -c | --color)
                (($# > 1)) || die "$1 needs a color"
                COLOR=$2
                shift
                ;;
            --color=*) COLOR=${1#*=} ;;
            --install) INSTALL=1 ;;
            --update)
                INSTALL=1
                ASSUME_YES=1
                CORE_ONLY=1
                ;;
            -y | --yes) ASSUME_YES=1 ;;
            --no-packages) INSTALL_PACKAGES=0 ;;
            --link) TOGGLE_LINKS=1 ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
    if ((TOGGLE_LINKS && argc > 1)); then
        die "--link takes no other options."
    fi
    if ((!INSTALL && !TOGGLE_LINKS)); then
        if ((argc == 0)); then
            usage
            exit 0
        fi
        usage >&2
        die "--color, --yes and --no-packages need --install."
    fi
    if ((ASSUME_YES)); then
        NOCONFIRM=(--noconfirm)
    fi
}

# ---------------- color ----------------
normalize_hex() {
    local hex=${1#\#}
    hex=${hex,,}
    [[ $hex =~ ^[0-9a-f]{6}$ ]] || return 1
    printf '%s' "$hex"
}

rgb_of() { printf '%d;%d;%d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
swatch() { printf '\e[48;2;%sm      \e[0m' "$(rgb_of "$1")"; }

previous_color() {
    local hex=""
    if [[ -r $STATE_FILE ]]; then
        hex=$(normalize_hex "$(<"$STATE_FILE")") || hex=""
    fi
    printf '%s' "${hex:-$BASE_COLOR}"
}

choose_color() {
    local current choice name hex i
    current=$(previous_color)

    if [[ -n $COLOR ]]; then
        COLOR=$(normalize_hex "$COLOR") || die "--color wants a hex color like 00c8ff"
    elif ((ASSUME_YES)); then
        COLOR=$current
    else
        say "Highlight color"
        for i in "${!PRESETS[@]}"; do
            read -r name hex <<<"${PRESETS[i]}"
            printf '   %d) %s %-7s #%s%s\n' $((i + 1)) "$(swatch "$hex")" "$name" "$hex" \
                "$([[ $hex == "$current" ]] && echo "  (current)")"
        done
        info "c) a hex color of your own"
        while :; do
            read -r -p "   Pick one [Enter keeps #$current]: " choice || choice=""
            if [[ -z $choice ]]; then
                COLOR=$current
            elif [[ $choice == [cC] ]]; then
                read -r -p "   Hex color: " choice || choice=""
                COLOR=$(normalize_hex "$choice") || {
                    warn "Not a hex color like 00c8ff."
                    continue
                }
            elif [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#PRESETS[@]})); then
                read -r name COLOR <<<"${PRESETS[choice - 1]}"
            elif ! COLOR=$(normalize_hex "$choice"); then
                warn "Pick a number from the list, c, or type a hex color."
                continue
            fi
            break
        done
    fi

    ACCENT=$(rgb_of "$COLOR")
    local r=$((16#${COLOR:0:2})) g=$((16#${COLOR:2:2})) b=$((16#${COLOR:4:2}))
    if (((2126 * r + 7152 * g + 722 * b) / 10000 < 40)); then
        warn "#$COLOR is very dark - it will be hard to see on the black UI."
    fi
    info "Highlight: $(swatch "$COLOR") #$COLOR"
}

# ---------------- keyboard layout ----------------
# The kb_layout in hyprland.lua's input block.
HYPRLAND_LUA=$HOME/.config/hypr/hyprland.lua
KB_LAYOUT_SED='s/^([[:space:]]*kb_layout[[:space:]]*=[[:space:]]*)"[^"]*"/'

current_kb_layout() {
    local layout=""
    if [[ -r $HYPRLAND_LUA ]]; then
        layout=$(sed -nE 's/^[[:space:]]*kb_layout[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HYPRLAND_LUA" | head -n 1)
    fi
    printf '%s' "${layout:-us}"
}

# Letters, digits, _ and -, comma-separated for several layouts (us,hr).
valid_kb_layout() { [[ $1 =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]]; }

choose_kb_layout() {
    local current choice code name i
    current=$(current_kb_layout)
    if ((ASSUME_YES)); then
        KB_LAYOUT=$current
        return
    fi
    say "Keyboard layout"
    for i in "${!LAYOUTS[@]}"; do
        read -r code name <<<"${LAYOUTS[i]}"
        printf '   %d) %s%s\n' $((i + 1)) "$name" "$([[ $code == "$current" ]] && echo "  (current)")"
    done
    info "Or type a layout code of your own, e.g. de, fr or us,hr."
    while :; do
        read -r -p "   Pick one [Enter keeps $current]: " choice || choice=""
        choice=${choice//[[:space:]]/}
        if [[ -z $choice ]]; then
            KB_LAYOUT=$current
        elif [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#LAYOUTS[@]})); then
            read -r KB_LAYOUT _ <<<"${LAYOUTS[choice - 1]}"
        elif valid_kb_layout "$choice"; then
            KB_LAYOUT=${choice,,}
        else
            warn "Pick a number from the list or type a layout code like de."
            continue
        fi
        break
    done
    info "Keyboard layout: $KB_LAYOUT"
}

# Like the color, the live hyprland.lua is edited rather than replaced, through
# the staged copy (a fresh one is seeded there from the .example). One linked
# into this checkout is the gitignored personal copy, so it's edited in place.
apply_kb_layout() {
    local staged=$STAGE/.config/hypr/hyprland.lua target
    [[ -n $KB_LAYOUT ]] || return 0
    if [[ -e $staged ]]; then
        target=$staged
    elif [[ -f $HYPRLAND_LUA ]]; then
        [[ $(current_kb_layout) == "$KB_LAYOUT" ]] && return 0
        if [[ $(realpath -- "$HYPRLAND_LUA") == "$REPO"/* ]]; then
            target=$(realpath -- "$HYPRLAND_LUA")
        else
            mkdir -p -- "$(dirname -- "$staged")"
            cp -p -- "$HYPRLAND_LUA" "$staged"
            target=$staged
        fi
    else
        return 0
    fi
    if grep -qE '^[[:space:]]*kb_layout[[:space:]]*=[[:space:]]*"' "$target"; then
        sed -i -E "${KB_LAYOUT_SED}\\1\"$KB_LAYOUT\"/" "$target"
    else
        warn "No kb_layout line in ~/.config/hypr/hyprland.lua - add kb_layout = \"$KB_LAYOUT\" to its input block by hand."
    fi
}

# ---------------- packages ----------------
aur_helper() {
    local helper dir
    for helper in yay paru; do
        if command -v "$helper" >/dev/null; then
            printf '%s' "$helper"
            return
        fi
    done
    ask "Some packages are only in the AUR, which needs an AUR helper. Install yay?" y || return 1
    if ! command -v makepkg >/dev/null || ! command -v git >/dev/null; then
        warn "Installing yay needs base-devel and git."
        return 1
    fi
    # Called as `helper=$(aur_helper)` inside an if, where set -e is off:
    # every step is checked by hand.
    dir=$(mktemp -d) || return 1
    if ! git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$dir/yay-bin" >&2 ||
        ! (cd "$dir/yay-bin" && makepkg -si --noconfirm) >&2; then
        rm -rf "$dir"
        warn "Installing yay failed."
        return 1
    fi
    rm -rf "$dir"
    printf yay
}

install_packages() {
    command -v pacman >/dev/null || die "This installer is for Arch Linux and Arch-based distros (no pacman found). Use --no-packages to only install the configs."
    say "Packages"

    local -a wanted=("${CORE_PACKAGES[@]}") extra=() missing=() repo=() aur=() found=() unknown=()
    local group default question pkgs p helper
    if [[ -n $(ls -A /sys/class/backlight 2>/dev/null) ]]; then
        wanted+=(brightnessctl) # a built-in panel ddcutil can't reach
    fi
    # --update can't know which optional groups were turned down before, so
    # it leaves them all alone rather than install one by its default.
    if ((!CORE_ONLY)); then
        for group in "${OPTIONAL_GROUPS[@]}"; do
            IFS='|' read -r default question pkgs <<<"$group"
            if ask "$question?" "$default"; then
                read -ra extra <<<"$pkgs"
                wanted+=("${extra[@]}")
            fi
        done
    fi

    local entry pkg prog
    for entry in "${SHIPPED_ELSEWHERE[@]}"; do
        pkg=${entry%%:*} prog=${entry#*:}
        if ! pacman -Qq -- "$pkg" &>/dev/null && command -v -- "$prog" >/dev/null; then
            info "$prog is already installed (by $(pacman -Qqo -- "$(command -v -- "$prog")" 2>/dev/null || echo "something else")), so the $pkg package is skipped."
            for p in "${!wanted[@]}"; do
                [[ ${wanted[p]} == "$pkg" ]] && unset 'wanted[p]'
            done
        fi
    done

    # Anything already satisfied - even by another package that provides
    # it, like quickshell-git - is left alone instead of swapped out.
    mapfile -t missing < <(pacman -T "${wanted[@]}" || true)
    for p in "${missing[@]}"; do
        if pacman -Si -- "$p" &>/dev/null; then
            repo+=("$p")
        else
            aur+=("$p")
        fi
    done

    if ((${#repo[@]})); then
        info "From the Arch repos: ${repo[*]}"
        # -Syu together with the install: syncing without upgrading is
        # the partial upgrade Arch doesn't support.
        sudo pacman -Syu --needed "${NOCONFIRM[@]}" -- "${repo[@]}"
    fi

    if ((${#aur[@]})); then
        if helper=$(aur_helper); then
            # Checked one by one: a single unknown name would otherwise
            # abort the whole AUR install.
            for p in "${aur[@]}"; do
                if "$helper" -Si "$p" &>/dev/null; then
                    found+=("$p")
                else
                    unknown+=("$p")
                fi
            done
            if ((${#found[@]})); then
                info "From the AUR: ${found[*]}"
                "$helper" -S --needed "${NOCONFIRM[@]}" "${found[@]}"
            fi
        else
            warn "Skipped the AUR packages: ${aur[*]}"
        fi
    fi
    if ((${#unknown[@]})); then
        warn "Couldn't find these in the repos or the AUR, skipped: ${unknown[*]}"
    fi
    if ((${#missing[@]} == 0)); then
        info "Everything's already installed."
    fi
}

# ---------------- dotfiles ----------------
# Everything is assembled in a staging copy first (examples seeded, paths
# fixed, colors applied), then synced into $HOME file by file - so only
# files that actually differ get touched, each backed up first.
stage_dotfiles() {
    local -a files=()
    local f target home_esc
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT

    # Tracked files only: a checkout can also hold the gitignored personal
    # files (hyprland.lua, monitors.json, built helpers...), and those must
    # never overwrite the live ones.
    if git -C "$REPO" rev-parse --is-inside-work-tree &>/dev/null; then
        mapfile -d '' -t files < <(git -C "$REPO" ls-files -z -- .config .local)
    else
        mapfile -d '' -t files < <(cd "$REPO" && find .config .local -type f -print0)
    fi

    for f in "${files[@]}"; do
        [[ -f $REPO/$f ]] || continue
        if [[ $f == *.example ]]; then
            # Personal files: seeded from their .example once, then never
            # overwritten.
            target=${f%.example}
            [[ -e $HOME/$target ]] && continue
            SEEDED+=("$target")
        else
            target=$f
        fi
        mkdir -p -- "$STAGE/$(dirname -- "$target")"
        cp -p -- "$REPO/$f" "$STAGE/$target"
    done

    # Configs that name their author's home directory.
    home_esc=$(printf '%s' "$HOME" | sed 's/[&#\\]/\\&/g')
    for f in .config/kitty/kitty.conf .config/qt6ct/qt6ct.conf .config/ZapZap/ZapZap.conf; do
        if [[ -f $STAGE/$f ]]; then
            sed -i -E "s#/home/[^/]+/#${home_esc}/#g" "$STAGE/$f"
        fi
    done
}

recolor_stage() {
    local -a staged=()
    local summary args img
    [[ $COLOR == "$BASE_COLOR" ]] && return
    mapfile -d '' -t staged < <(find "$STAGE" -type f -print0)
    summary=$("${RECOLOR[@]}" --from "$BASE_COLOR" --to "$COLOR" "${staged[@]}")
    info "Recolored $summary"

    if ! command -v magick >/dev/null; then
        warn "ImageMagick isn't installed, so the wallpaper and fastfetch logo stay purple."
        return
    fi
    args=$("${RECOLOR[@]}" --from "$BASE_COLOR" --to "$COLOR" --modulate)
    for img in "$STAGE"/.config/hypr/wallpapers/*.png "$STAGE"/.config/fastfetch/*.gif; do
        if [[ -f $img ]]; then
            magick "$img" -modulate "$args" "$img"
        fi
    done
}

# hyprland.lua is personal, so its live copy is recolored from whatever
# color it has instead of being replaced. Read from the file itself: the
# state file also moves on when this one was left alone or edited by hand.
recolor_live_hyprland() {
    local live=$HOME/.config/hypr/hyprland.lua staged=$STAGE/.config/hypr/hyprland.lua previous
    [[ -f $live && ! -e $staged ]] || return 0
    previous=$(sed -nE 's/^[[:space:]]*active_border[^(]*\(([0-9a-fA-F]{6}).*/\1/p' "$live" | head -n 1)
    previous=$(normalize_hex "$previous") || previous=$(previous_color)
    [[ $previous == "$COLOR" ]] && return 0
    mkdir -p -- "$(dirname -- "$staged")"
    cp -p -- "$live" "$staged"
    if ! "${RECOLOR[@]}" --from "$previous" --to "$COLOR" "$staged" >/dev/null; then
        rm -f -- "$staged"
        warn "Couldn't recolor ~/.config/hypr/hyprland.lua from #$previous - change its border colors by hand."
    fi
}

in_a_checkout() {
    local dir=$1
    while [[ $dir == /?* ]]; do
        [[ -f $dir/install/recolor.py ]] && return 0
        dir=${dir%/*}
    done
    return 1
}

# A directory like ~/.config/hypr symlinked into some other checkout of
# these dotfiles: writing through it would recolor that checkout. Swap the
# link for a real copy (personal gitignored files included) to install into.
detach_other_checkouts() {
    local rel=$1 path=$HOME part target tmp
    local -a parts=()
    IFS=/ read -ra parts <<<"${rel%/*}"
    for part in "${parts[@]}"; do
        path+=/$part
        [[ -L $path && -d $path ]] || continue
        target=$(realpath -- "$path")
        [[ $target != "$REPO" && $target != "$REPO"/* ]] && in_a_checkout "$target" || continue
        tmp=$path.purpura-new
        rm -rf -- "$tmp"
        cp -a -- "$target" "$tmp"
        rm -f -- "$path"
        mv -- "$tmp" "$path"
        info "${path/#$HOME/\~} linked to $target - it's a real copy now, that checkout is left as it was."
    done
}

sync_stage() {
    local backup rel src dst added=0 updated=0 same=0 linked=0
    backup=$HOME/.config/purpura-backups/$(date +%Y%m%d-%H%M%S)
    while IFS= read -r -d '' rel; do
        src=$STAGE/$rel
        dst=$HOME/$rel
        detach_other_checkouts "$rel"
        # e.g. ~/.config/quickshell symlinked to this checkout: writing
        # there would edit the repo itself.
        if [[ $(realpath -m -- "$dst") == "$REPO"/* ]]; then
            linked=$((linked + 1))
            continue
        fi
        if [[ -e $dst || -L $dst ]]; then
            if cmp -s -- "$src" "$dst"; then
                same=$((same + 1))
                continue
            fi
            mkdir -p -- "$backup/$(dirname -- "$rel")"
            cp -pP -- "$dst" "$backup/$rel"
            # Replace a symlink rather than write through it.
            rm -f -- "$dst"
            updated=$((updated + 1))
        else
            added=$((added + 1))
        fi
        mkdir -p -- "$(dirname -- "$dst")"
        cp -p -- "$src" "$dst"
    done < <(cd "$STAGE" && find . -type f -printf '%P\0' | sort -z)

    # The shell's own code is all the repo's, so anything in it the repo no
    # longer has - moved elsewhere or deleted - goes too (into the backup):
    # left behind, a moved file would clash with the one in its new place.
    local shell_code=$HOME/.config/quickshell/components removed=0
    if [[ -d $shell_code && $(realpath -m -- "$shell_code") != "$REPO"/* ]]; then
        while IFS= read -r -d '' rel; do
            [[ -e $STAGE/.config/quickshell/components/$rel ]] && continue
            mkdir -p -- "$backup/.config/quickshell/components/$(dirname -- "$rel")"
            mv -- "$shell_code/$rel" "$backup/.config/quickshell/components/$rel"
            removed=$((removed + 1))
        done < <(cd "$shell_code" && find . \( -type f -o -type l \) -printf '%P\0')
        find "$shell_code" -mindepth 1 -type d -empty -delete
    fi

    info "$added added, $updated updated, $removed removed, $same already up to date."
    if ((added + updated + removed)); then
        CONFIGS_CHANGED=1
    fi
    if ((${#SEEDED[@]})); then
        info "Created from their .example (yours to edit, never overwritten): ${SEEDED[*]}"
    fi
    if ((updated + removed)); then
        info "Previous versions of the updated and removed files: ${backup/#$HOME/\~}"
    fi
    if ((linked)); then
        warn "$linked files link into this checkout, so they keep their current colors - recoloring them would edit the repo itself. To recolor them, run ./purpura.sh --link first: it replaces those links with real copies."
    fi
}

install_dotfiles() {
    say "Dotfiles"
    command -v python3 >/dev/null || die "Applying the color needs python3 (it's in the package list - run without --no-packages, or install python)."
    if ! ask "Install the configs into ~/.config? Files that change are backed up first." y; then
        info "Skipped."
        return
    fi
    stage_dotfiles
    recolor_stage
    recolor_live_hyprland
    apply_kb_layout
    sync_stage
    mkdir -p -- "$(dirname -- "$STATE_FILE")"
    printf '#%s\n' "$COLOR" >"$STATE_FILE"
    record_install
    DOTFILES_INSTALLED=1
}

# Which checkout the configs came from, and at which commit - what the
# shell's updater compares against that checkout's upstream once "Follow
# Purpura versioning" is on (helpers/purpura-update.sh).
record_install() {
    local dir=${STATE_FILE%/*} commit
    mkdir -p -- "$dir"
    printf '%s\n' "$REPO" >"$dir/checkout"
    if commit=$(git -C "$REPO" rev-parse HEAD 2>/dev/null); then
        printf '%s\n' "$commit" >"$dir/commit"
    else
        rm -f -- "$dir/commit"
    fi
}

# ---------------- linking ----------------
# Gitignored files only exist on this machine: a fresh clone doesn't have them,
# and the repo's copy goes stale while the configs are real copies. So the live
# one moves into the repo, and whatever it replaces goes to the backup.
adopt_personal_files() {
    local item=$1 backup=$2 f
    while IFS= read -r -d '' f; do
        cmp -s -- "$HOME/$f" "$REPO/$f" && continue
        if [[ -e $REPO/$f ]]; then
            mkdir -p -- "$(dirname -- "$backup/repo/$f")"
            mv -- "$REPO/$f" "$backup/repo/$f"
        fi
        mkdir -p -- "$(dirname -- "$REPO/$f")"
        cp -p -- "$HOME/$f" "$REPO/$f"
    done < <(cd "$HOME" && find "$item" -type f -print0 | git -C "$REPO" check-ignore -z --stdin)
}

# Nothing live to adopt, e.g. a fresh clone: the same seeding as installing.
seed_personal_files() {
    local -a examples=()
    local f target
    mapfile -d '' -t examples < <(git -C "$REPO" ls-files -z -- '*.example')
    for f in "${examples[@]}"; do
        target=$REPO/${f%.example}
        if [[ ! -e $target ]]; then
            cp -p -- "$REPO/$f" "$target"
            info "Created ${f%.example} from its .example."
        fi
    done
}

warn_about_linked_configs() {
    local f color
    # stage_dotfiles rewrites these per machine, which a link can't do.
    for f in .config/kitty/kitty.conf .config/qt6ct/qt6ct.conf .config/ZapZap/ZapZap.conf; do
        if grep -E '/home/[^/]+/' "$REPO/$f" 2>/dev/null | grep -qv -- "$HOME/"; then
            warn "$f names another home directory - fix its paths by hand."
        fi
    done
    if [[ ! -x $REPO/.config/quickshell/helpers/auth ]]; then
        warn "The lock screen's helper isn't built, so it can't check your password: make -C ~/.config/quickshell/helpers"
    fi
    color=$(previous_color)
    if [[ $color != "$BASE_COLOR" ]]; then
        warn "Linked configs are the repo's own purple (#$BASE_COLOR), not your #$color. Restart your apps to see it."
    fi
}

link_configs() {
    local backup item dst
    local -a moved=()
    backup=$HOME/.config/purpura-backups/$(date +%Y%m%d-%H%M%S)
    say "Linking the configs to $REPO"
    for item in "$@"; do
        if [[ -e $HOME/$item ]]; then
            adopt_personal_files "$item" "$backup"
        fi
    done
    seed_personal_files
    for item in "$@"; do
        dst=$HOME/$item
        if [[ -e $dst ]]; then
            if diff -rq -- "$dst" "$REPO/$item" &>/dev/null; then
                rm -rf -- "$dst"
            else
                mkdir -p -- "$(dirname -- "$backup/$item")"
                mv -- "$dst" "$backup/$item"
                moved+=("$item")
            fi
        fi
        mkdir -p -- "$(dirname -- "$dst")"
        ln -s -- "$REPO/$item" "$dst"
    done
    info "$# configs linked."
    if ((${#moved[@]})); then
        info "Differed from the repo, so the live versions are in ${backup/#$HOME/\~}: ${moved[*]}"
    fi
    warn_about_linked_configs
}

unlink_configs() {
    local item dst target tmp count=0
    say "Unlinking the configs"
    for item in "$@"; do
        dst=$HOME/$item
        [[ -L $dst ]] || continue
        # A dangling link has nothing to copy, so it gets the repo's version.
        if [[ -e $dst ]]; then
            target=$(realpath -- "$dst")
        else
            target=$REPO/$item
        fi
        # All of it, not just what's tracked: personal files come along.
        tmp=$dst.purpura-new
        rm -rf -- "$tmp"
        cp -a -- "$target" "$tmp"
        rm -f -- "$dst"
        mv -- "$tmp" "$dst"
        count=$((count + 1))
    done
    info "$count links replaced with real copies."
}

# Configs other programs rewrite as they run, which through a link would keep
# changing the repo: fish its fish_variables, and KDE's GTK settings sync the
# GTK folders (cursor theme, window button assets). So they're never linked:
# a link from before this rule becomes a real copy, and a missing one gets one.
NEVER_LINKED=(.config/fish .config/gtk-3.0 .config/gtk-4.0)

ensure_real_copies() {
    local item dst
    local -a linked=()
    for item in "${NEVER_LINKED[@]}"; do
        dst=$HOME/$item
        if [[ -L $dst && $(realpath -m -- "$dst") == "$REPO/$item" ]]; then
            linked+=("$item")
        elif [[ ! -e $dst && ! -L $dst && -e $REPO/$item ]]; then
            mkdir -p -- "$(dirname -- "$dst")"
            cp -a -- "$REPO/$item" "$dst"
            info "Copied $item to ~/$item."
        fi
    done
    if ((${#linked[@]})); then
        unlink_configs "${linked[@]}"
    fi
}

# Whole directories under .config, but .local file by file: the directories
# there also hold things that aren't ours, like other color schemes.
toggle_links() {
    local item
    local -a items=() excludes=()
    ensure_real_copies
    for item in "${NEVER_LINKED[@]}"; do
        excludes+=(":(exclude)$item")
    done
    mapfile -d '' -t items < <(
        git -C "$REPO" ls-files -z -- .config "${excludes[@]}" | cut -z -d/ -f1,2 | sort -zu
        git -C "$REPO" ls-files -z -- .local
    )
    ((${#items[@]})) || die "No tracked configs found in $REPO - --link needs a git checkout."
    for item in "${items[@]}"; do
        if [[ -L $HOME/$item ]]; then
            unlink_configs "${items[@]}"
            record_install
            return
        fi
    done
    link_configs "${items[@]}"
    record_install
}

# ---------------- helpers ----------------
build_helpers() {
    local dir=$HOME/.config/quickshell/helpers pam=$HOME/.config/quickshell/pam.d/quickshell-auth
    say "Lock screen, visualizer and idle helpers"
    # Built one at a time so a missing libcava only costs the visualizer.
    if make -C "$dir" auth >/dev/null; then
        info "Built helpers/auth (the lock screen's password check)."
    else
        warn "Building helpers/auth failed - without it the lock screen can't check your password. Fix the error above, then run: make -C ${dir/#$HOME/\~}"
    fi
    if make -C "$dir" cava_bridge >/dev/null; then
        info "Built helpers/cava_bridge (the dashboard's visualizer)."
    else
        warn "Building helpers/cava_bridge failed (needs libcava from the AUR) - the dashboard's visualizer stays empty until it builds: make -C ${dir/#$HOME/\~}"
    fi
    if make -C "$dir" idle_inhibit >/dev/null; then
        info "Built helpers/idle_inhibit (keeps auto-lock and auto-sleep off while a video plays)."
    else
        warn "Building helpers/idle_inhibit failed - apps that ask over D-Bus not to go idle (browsers playing a video) won't stop auto-lock or auto-sleep until it builds: make -C ${dir/#$HOME/\~}"
    fi
    if ! cmp -s -- "$pam" /etc/pam.d/quickshell-auth; then
        info "Installing the lock screen's PAM config (needs sudo)."
        sudo install -Dm644 -- "$pam" /etc/pam.d/quickshell-auth
    fi
}

# ---------------- open apps ----------------
# Apps read their theme when they start, so a new color only takes over
# completely once everything open has been restarted. The warning comes
# before any of the work, leaving time to save; the closing comes last.
warn_about_closing_apps() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && $COLOR != "$(previous_color)" ]] || return 0
    command -v hyprctl >/dev/null || return 0
    say "Open apps"
    warn "Changing the color closes EVERYTHING that's open when the install finishes: every window on every workspace, browsers and games included. Anything unsaved is lost, so save your work now."
    info "This terminal stays open. The shell (qs), hyprpaper, the polkit agent and Solaar restart by themselves; everything else you reopen yourself."
    if ask "Close everything when the install finishes?" y; then
        CLOSE_APPS=1
    else
        info "Leaving them open - they keep the old color until restarted."
    fi
}

# Every open window's PID, except this terminal and Hyprland itself.
window_pids() {
    local pid=$$
    local -a spared=()
    while ((pid > 1)); do
        spared+=("$pid")
        pid=$(ps -o ppid= -p "$pid") || break
        pid=${pid//[^0-9]/}
    done
    mapfile -t -O "${#spared[@]}" spared < <(pgrep -u "$EUID" -x Hyprland)
    # X11 windows can report 0 or -1, which `kill` takes to mean every
    # process in the session.
    hyprctl -j clients | jq -r '.[].pid | select(. > 1)' | sort -un | while read -r pid; do
        [[ " ${spared[*]} " == *" $pid "* ]] || printf '%s\n' "$pid"
    done
}

# SIGTERM to let them exit cleanly, SIGKILL whatever's still up after 5s.
stop_pids() {
    local pid try
    local -a alive=("$@")
    ((${#alive[@]})) || return 0
    kill -TERM -- "${alive[@]}" 2>/dev/null || true
    for ((try = 0; try < 50; try++)); do
        set -- "${alive[@]}"
        alive=()
        for pid in "$@"; do
            if kill -0 -- "$pid" 2>/dev/null; then
                alive+=("$pid")
            fi
        done
        ((${#alive[@]})) || return 0
        sleep 0.1
    done
    kill -KILL -- "${alive[@]}" 2>/dev/null || true
}

restart_apps() {
    local entry pattern cmd out
    local -a pids=() found=()
    # The reload below reverts what these two replay: the monitor layout and
    # the mouse sensitivity.
    local -a commands=("$HOME/.config/hypr/scripts/apply-monitors.sh" "$HOME/.config/hypr/scripts/apply-peripherals.sh")
    say "Closing everything open"
    if command -v jq >/dev/null; then
        mapfile -t pids < <(window_pids)
    else
        warn "jq isn't installed, so windows can't be listed - they stay open in the old color."
    fi
    for entry in "${SESSION_PROGRAMS[@]}"; do
        pattern=${entry%%:*}
        cmd=${entry#*:}
        mapfile -t found < <(pgrep -u "$EUID" -x "$pattern")
        ((${#found[@]})) || continue
        pids+=("${found[@]}")
        if [[ -n $cmd ]]; then
            commands+=("$cmd")
        fi
    done
    stop_pids "${pids[@]}"

    say "Restarting the session"
    hyprctl reload >/dev/null || warn "hyprctl reload failed - run it by hand for the new border color."
    # Through Hyprland, so they don't depend on this terminal staying open.
    for cmd in "${commands[@]}"; do
        out=$(hyprctl dispatch "hl.dsp.exec_cmd(\"$cmd\")" 2>&1) || true
        if [[ $out == *ok* ]]; then
            info "Started ${cmd/#$HOME/\~}"
        else
            warn "Couldn't start ${cmd/#$HOME/\~}: $out - run it by hand."
        fi
    done
    # kitty rereads its config on this, for the terminal that stayed open.
    pkill -USR1 -u "$EUID" -x kitty || true
    APPS_RESTARTED=1
}

final_notes() {
    local svc
    say "Done"
    for svc in NetworkManager bluetooth; do
        if systemctl cat "$svc.service" &>/dev/null && ! systemctl is-active --quiet "$svc.service"; then
            info "$svc isn't running; the Connections tab needs it: sudo systemctl enable --now $svc"
        fi
    done
    if ((APPS_RESTARTED)); then
        info "Everything's now running in #$COLOR - reopen your apps whenever you're ready."
    else
        info "Log into Hyprland, or if you're already in it run: hyprctl reload"
        info "Apps that were open keep their old colors until restarted."
    fi
}

main() {
    parse_args "$@"
    ((EUID != 0)) || die "Run this as your normal user, not root - it asks for sudo when it needs it."
    if ((TOGGLE_LINKS)); then
        toggle_links
        return
    fi
    choose_color
    choose_kb_layout
    warn_about_closing_apps
    if ((INSTALL_PACKAGES)); then
        install_packages
    fi
    # Not `if install_dotfiles`: bash turns set -e off inside anything
    # run as an if condition.
    install_dotfiles
    if ((DOTFILES_INSTALLED)); then
        build_helpers
    fi
    if ((CLOSE_APPS && CONFIGS_CHANGED)); then
        restart_apps
    fi
    final_notes
}

main "$@"

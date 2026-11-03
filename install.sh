#!/usr/bin/env bash
# purpura-dotfiles installer: the packages it needs, the configs
# themselves, and a highlight color applied across them. Safe to re-run -
# e.g. `./install.sh --no-packages` just to switch to another color.
set -euo pipefail

# Physical path: it's compared against realpath results below.
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# The color every themed file in the repo is written in; installed copies
# are recolored from it.
BASE_COLOR=9600fa
STATE_FILE=${XDG_STATE_HOME:-$HOME/.local/state}/purpura/highlight
RECOLOR=(python3 -I "$REPO/install/recolor.py")

ASSUME_YES=0
INSTALL_PACKAGES=1
COLOR=""
NOCONFIRM=()
STAGE=""
SEEDED=()
DOTFILES_INSTALLED=0

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
    hyprland hyprpaper hypridle hyprpolkitagent hyprsunset hyprshutdown
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

# default (y/n) | question | packages | flatpaks
OPTIONAL_GROUPS=(
    "y|Apps the keybinds open: rofi, Dolphin, Waterfox (Flatpak)|rofi dolphin xdotool flatpak|net.waterfox.waterfox"
    "y|fish shell + fastfetch (the terminal greeting)|fish fastfetch|"
    "n|Solaar (Logitech mice/keyboards: battery list, sensitivity setting)|solaar|"
    "n|ZapZap (WhatsApp)|zapzap|"
    "n|ZeroTier|zerotier-one|"
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
Usage: ./install.sh [options]

Installs purpura-dotfiles: the packages it needs (pacman + AUR), its
configs into ~/.config, and a highlight color applied across them.
Anything it would overwrite is backed up first.

  -c, --color HEX    highlight color, e.g. 00c8ff (skips the color menu)
  -y, --yes          don't ask anything, take the defaults
      --no-packages  skip installing packages, e.g. to just change color
  -h, --help         show this help
EOF
}

parse_args() {
    while (($#)); do
        case $1 in
            -c | --color)
                (($# > 1)) || die "$1 needs a color"
                COLOR=$2
                shift
                ;;
            --color=*) COLOR=${1#*=} ;;
            -y | --yes) ASSUME_YES=1 ;;
            --no-packages) INSTALL_PACKAGES=0 ;;
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

    local -a wanted=("${CORE_PACKAGES[@]}") flatpaks=() extra=() missing=() repo=() aur=() found=() unknown=()
    local group default question pkgs fps p helper
    if [[ -n $(ls -A /sys/class/backlight 2>/dev/null) ]]; then
        wanted+=(brightnessctl) # a built-in panel ddcutil can't reach
    fi
    for group in "${OPTIONAL_GROUPS[@]}"; do
        IFS='|' read -r default question pkgs fps <<<"$group"
        if ask "$question?" "$default"; then
            read -ra extra <<<"$pkgs"
            wanted+=("${extra[@]}")
            read -ra extra <<<"$fps"
            flatpaks+=("${extra[@]}")
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

    if ((${#flatpaks[@]})) && ! command -v flatpak >/dev/null; then
        warn "flatpak isn't installed, skipped: ${flatpaks[*]}"
    elif ((${#flatpaks[@]})); then
        info "From Flathub: ${flatpaks[*]}"
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        if ((ASSUME_YES)); then
            flatpak install --user -y flathub "${flatpaks[@]}"
        else
            flatpak install --user flathub "${flatpaks[@]}"
        fi
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
        [[ -f $dir/install.sh && -f $dir/install/recolor.py ]] && return 0
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

    info "$added added, $updated updated, $same already up to date."
    if ((${#SEEDED[@]})); then
        info "Created from their .example (yours to edit, never overwritten): ${SEEDED[*]}"
    fi
    if ((updated)); then
        info "Previous versions of the updated files: ${backup/#$HOME/\~}"
    fi
    if ((linked)); then
        warn "$linked files link into this checkout, so they keep their current colors - recoloring them would edit the repo itself. To recolor them, run the installer from a separate clone: it replaces those links with real copies."
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
    sync_stage
    mkdir -p -- "$(dirname -- "$STATE_FILE")"
    printf '#%s\n' "$COLOR" >"$STATE_FILE"
    DOTFILES_INSTALLED=1
}

# ---------------- helpers ----------------
build_helpers() {
    local dir=$HOME/.config/quickshell/helpers pam=$HOME/.config/quickshell/pam.d/quickshell-auth
    say "Lock screen + visualizer helpers"
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
    if ! cmp -s -- "$pam" /etc/pam.d/quickshell-auth; then
        info "Installing the lock screen's PAM config (needs sudo)."
        sudo install -Dm644 -- "$pam" /etc/pam.d/quickshell-auth
    fi
}

final_notes() {
    local svc
    say "Done"
    for svc in NetworkManager bluetooth; do
        if systemctl cat "$svc.service" &>/dev/null && ! systemctl is-active --quiet "$svc.service"; then
            info "$svc isn't running; the Connections tab needs it: sudo systemctl enable --now $svc"
        fi
    done
    info "Log into Hyprland, or if you're already in it run: hyprctl reload"
    info "Apps that were open keep their old colors until restarted."
}

main() {
    parse_args "$@"
    ((EUID != 0)) || die "Run this as your normal user, not root - it asks for sudo when it needs it."
    choose_color
    if ((INSTALL_PACKAGES)); then
        install_packages
    fi
    # Not `if install_dotfiles`: bash turns set -e off inside anything
    # run as an if condition.
    install_dotfiles
    if ((DOTFILES_INSTALLED)); then
        build_helpers
    fi
    final_notes
}

main "$@"

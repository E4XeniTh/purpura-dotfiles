# purpura-dotfiles

My personal, minimal Hyprland setup. The core of it is a Quickshell
desktop shell built from scratch — bar, dashboard, notification center,
lock screen, power menu — styled sharp-cornered, black, and purple, with
colors and shell-wide settings kept in one file (`Config.js`). Alongside
that is the Hyprland config itself and a handful of matching app configs
(terminal, shell, launcher, etc). Everything lives under `.config/`, laid
out to be copied straight into place.

## What's in here

| Component | What it does |
|---|---|
| **Bar** | Top bar: tray, clock (opens the dashboard), volume/brightness/battery widgets, notification icon (opens the notification center) |
| **Dashboard** | Clock, weather, calendar, now-playing + media controls, quick settings (audio/network/bluetooth/screen/battery), power/lock |
| **Notification center** | Toast popups, plus a persistent (capped, newest-first) history panel |
| **Clipboard history** | cliphist-backed text/image history panel (META + V), with a full-content preview pane, click-to-copy, and right-click delete |
| **Screenshot picker** | Custom region/window/monitor/all-monitors picker (META + X) - freezes the screen, dims it, and captures straight to the clipboard via grim |
| **Lock screen** | A real session lock - no keybind gets through but volume, brightness and media keys - over the blurred desktop, with the time above the password box and the dashboard's now-playing card beside it while something plays. Authenticates via PAM |
| **Auto-lock, dim and suspend** | Settings > General > Power: locks after a set time without input, then optionally dims the monitors (all together, or each after its own inactivity, naming the ones still active if you like) and suspends, counting down on the main monitor first. The dim covers everything, the settings screen and the lock screen included |
| **Manual dim** | META + BackSpace dims every monitor but the one the mouse is on, each time it's pressed. A dimmed one wakes when the mouse moves onto it. An existing `hyprland.lua` needs the bind from the `.example` added by hand, or bind it in Settings > Shortcuts |
| **Mouse & input languages** | Settings > General > Input: mouse sensitivity and acceleration, and the keyboard languages you type in. With more than one, META + - switches to the next and shows which is on. Kept after Hyprland config reloads. An existing `hyprland.lua` needs the bind from the `.example` added by hand, or bind it in Settings > Shortcuts |
| **Shortcuts** | Settings tab with a clickable keyboard: bound keys are lit, and clicking a key adds or removes its binds. Saved to `hypr/shortcuts.lua`, which `hyprland.lua` loads (an existing `hyprland.lua` needs the `pcall(require, "shortcuts")` line from the `.example` added by hand) |
| **Power menu** | Shutdown / reboot / suspend / logout |
| **Tray** | System tray with a themed right-click menu per item |

Also included: the Hyprland config (`hypr/`), and configs for kitty,
fish, rofi, fastfetch, GTK, and ZapZap.

The shell (`.config/quickshell/`) is `shell.qml`, which puts it all
together, `Config.js` (colors, font, sizes), `helpers/` (the C helpers and
scripts) and `components/`, by area:

| Folder | What's in it |
|---|---|
| `bar/` | The bar and its widgets (tray, workspaces, volume/brightness/battery) |
| `dashboard/` | The dashboard and its cards (calendar, weather, now playing, visualizer, system monitor) |
| `settings/` | The settings screen and its tabs; `cards/` and `controls/` hold the pieces the tabs are built from |
| `panels/` | Notifications, clipboard, screenshot picker, updater, dropdown console |
| `osd/` | Volume, brightness, workspace and fullscreen-hint popups |
| `lock/` | The lock screen |
| `power/` | Power menu, auto-lock, auto-dim and auto-suspend |
| `system/` | Shell-wide state with no UI of its own: UI scale, edge gaps, night light, input settings |
| `common/` | Pieces several areas share |

`./purpura.sh --install`/`--update` keeps `components/` exactly as the
repo has it: a file the repo no longer has (moved or deleted) is moved
into the backup folder, so don't keep files of your own in there.

No component has a `...State.qml` singleton - each keeps its own
open/closed state locally and exposes it through an `IpcHandler`, which
is also how cross-file control (a keybind, or one component nudging
another) works:

```bash
qs ipc call notificationpanel toggle   # show / hide also work
qs ipc call dashboard toggle           # opens on the primary screen
qs ipc call powermenu toggle
qs ipc call lockscreen lock            # lock only - no IPC unlock, see LockScreen.qml
qs ipc call trayMenu hide              # no toggle/show - see Tray.qml
qs ipc call clipboard toggle           # show / hide also work
qs ipc call screenshot show            # toggle / hide also work, see Screenshot.qml
qs ipc call updater check              # recheck now; toggle / show / hide work the dropdown
```

## Install

On Arch Linux or an Arch-based distro:

```bash
git clone https://github.com/E4XeniTh/purpura-dotfiles
cd purpura-dotfiles
./purpura.sh --install
```

The installer:

- asks for a **highlight color** (purple by default; pick a preset or any
  hex) and applies it across the configs: the shell, Hyprland's borders,
  GTK, Qt/Kvantum, KDE apps, kitty, rofi, ZapZap, and the wallpaper and
  fastfetch logo. The repo itself stays purple - only the installed copies
  are recolored (`install/recolor.py`)
- installs the packages listed below from the Arch repos and the AUR
  (offering to set up `yay` if you have no AUR helper), asking about the
  optional app groups first
- copies the configs into `~/.config`, backing up every file it changes
  to `~/.config/purpura-backups/<date>/` first
- creates `hyprland.lua`, `hyprpaper.conf` and `ZapZap.conf` from their
  `.example` once and never overwrites them after that (picking a new
  color only updates `hyprland.lua`'s border colors)
- builds the helper binaries and installs the lock screen's PAM file
- if you changed the color from inside Hyprland, **closes everything that's
  open** when it finishes, so nothing stays in the old color. It warns and
  asks first, because anything unsaved is lost (`--yes` takes that as a yes).
  The terminal you ran it from stays open, and `qs`, `hyprpaper`, the polkit
  agent and Solaar restart by themselves; other apps you reopen yourself

Re-run it whenever you like - e.g. `./purpura.sh --install --no-packages` to
switch to another color. `./purpura.sh` on its own installs nothing and only
shows the help, which lists the options (`--color HEX`, `--yes`,
`--no-packages`, `--update`, `--link`).

### Staying up to date

Turn on **Follow Purpura versioning** in Settings > General > Updater, and the
updater keeps purpura itself current alongside your packages. A version is a
commit of the checkout you installed from: the installer records which
checkout and commit it installed (in `~/.local/state/purpura/`), and anything
newer on that checkout's upstream branch is an update.

- It's checked on the updater's own schedule (`git fetch`, never asking for
  credentials), and you get a notification once per new version - clicking it
  opens the updater.
- The updater's dropdown shows purpura's state under the package list:
  installed vs. newest version, and anything that would get in the way
  (local commits or changes in the checkout, no network).
- Right-clicking the updater button runs purpura's update just before the
  firmware updates: a fast-forward `git pull` of the checkout, then
  `./purpura.sh --update`, which installs the new configs and helpers, keeps
  your color and keyboard layout, and only adds core packages that are
  missing (never the optional apps).
- The dropdown's **Update:** buttons run one step on its own - packages,
  flatpak, firmware or purpura - or **everything**, the same as
  right-clicking the updater button.

An install from before this needs one `./purpura.sh --install` (or `--link`)
so the checkout gets recorded; linked configs are found without it.

### Linked to the repo

To work on the configs, link them instead of copying them:

```bash
./purpura.sh --link
```

Everything the repo tracks except fish and the GTK folders gets linked into `~/.config` (and the
color scheme into `~/.local/share/color-schemes`), so editing the repo edits
the live config. Run it again to undo: if anything is linked, every link is replaced
with a real copy instead.

- Your gitignored personal files (`hyprland.lua`, `monitors.json`...) move
  into the checkout, so don't delete it while linked.
- Other live files that differ from the repo are moved to
  `~/.config/purpura-backups/<date>/` first.
- Linked configs stay in the repo's purple: `purpura.sh` can't recolor them
  without editing the repo.
- fish and `gtk-3.0`/`gtk-4.0` stay real copies, because they get rewritten
  as they're used: fish rewrites its own `fish_variables`, and KDE's GTK
  settings sync rewrites the GTK folders. Edits to the repo's copies need
  copying over by hand.
- Other apps that rewrite their own config now show up as changes in
  `git status`.

### By hand

```bash
cp -r .config/hypr .config/quickshell ~/.config/
```

Copy the rest (`fish`, `kitty`, `rofi`, `fastfetch`, `gtk-3.0`,
`gtk-4.0`, `Kvantum`, `qt6ct`, `kdeglobals`, `ZapZap`, and
`.local/share/color-schemes` into `~/.local/share/`) too if you want those
as well. A few of them name the author's home directory (`kitty.conf`,
`qt6ct.conf`, `ZapZap.conf`) - point those at yours.

`hyprland.lua`, `hypr/hyprpaper.conf`, and `ZapZap/ZapZap.conf` are
gitignored - personal/machine-specific enough (keyboard layout, output
names, wallpaper paths, an account-tied WhatsApp session) that editing
them shouldn't turn into a pending diff, and pulling repo updates
shouldn't ever clobber them back to some default. Each has a tracked
`.example` twin instead - seed your real config from it once, on first
install only (`cp -n` no-ops if the real file already exists, so this
is safe to re-run):

```bash
cp -n .config/hypr/hyprland.lua.example ~/.config/hypr/hyprland.lua
cp -n .config/hypr/hyprpaper.conf.example ~/.config/hypr/hyprpaper.conf
cp -n .config/ZapZap/ZapZap.conf.example ~/.config/ZapZap/ZapZap.conf
```

## Build the helper binaries

Three small C helpers need compiling locally - they're gitignored since
they're machine-specific. `purpura.sh` does this for you; by hand:

- **`auth`**: the lock screen checks your real login password through
  it, over PAM, so the shell process itself never touches `/etc/shadow`.
- **`cava_bridge`**: feeds the default sink's audio into `libcava` for
  the dashboard's visualizer - not something a prebuilt binary can cover
  since it's linked against a specific fork of `libcava`.
- **`idle_inhibit`**: answers apps that ask over D-Bus not to go idle
  (`org.freedesktop.ScreenSaver.Inhibit` - browsers playing a video, among
  others) and watches systemd idle inhibitor locks, so those hold off
  auto-lock, auto-dim and auto-suspend too. Hyprland only sees Wayland inhibitors by
  itself. The shell starts it and it keeps running across shell reloads.

```bash
cd ~/.config/quickshell/helpers
make
sudo cp ../pam.d/quickshell-auth /etc/pam.d/quickshell-auth
```

Re-run `make` after pulling changes to any of the helpers' `.c` files.

## Dependencies and affected apps

Beyond a base Arch install (`purpura.sh` installs all of these - its
package lists are the exact set):

- `kitty`
- `hyprland`
- `quickshell` — built with Pipewire + SystemTray support
- `qt6-5compat`
- `qt6ct-kde` (AUR)
- `kvantum`
- `base-devel` (`gcc`, `make`)
- `ttf-hack` — `Config.js`'s `fontfamily`
- `libcava` (AUR)
- `libpulse`
- `hyprpaper`
- `hyprshutdown`
- `hyprpolkitagent` (or another polkit authentication agent)
- `xdg-desktop-portal`
- `xdg-desktop-portal-hyprland`
- `pipewire`
- `pipewire-pulse` - the visualizer's `cava_bridge` reads audio through the PulseAudio API
- `wireplumber`
- `bluez` + `bluez-utils` - the Connections tab's Bluetooth category
- `ddcutil` - Screen Settings' brightness sliders and Bar.qml's brightness widget use this for external DDC/CI monitors
- `brightnessctl` (optional) - used instead of `ddcutil` for a laptop's own built-in panel (`eDP-*`), which ddcutil can't reach at all; only needed if you actually have one
- `playerctl`
- `jq`
- `curl`
- `pam`
- `xembedsniproxy` (AUR) - (useful if you emulate windows applications through Wayland)
- `kservice` - `kbuildsycoca6`, run at login so KDE apps like Dolphin see installed apps
- `networkmanager` - provides `nmcli`, which the Connections tab's Wired category also uses to detect a ZeroTier interface (`Quickshell.Networking` never sees it directly)
- `zerotier-one` (AUR, optional, not installed by `purpura.sh`) - only if you actually use ZeroTier; its `zt*` interface shows up via `nmcli` on its own, nothing here calls `zerotier-cli` (it needs root and isn't used)
- `upower` - Battery Settings' system-battery row and Bar.qml's battery widget both read through `Quickshell.Services.UPower`, which needs the `upower` daemon running
- `cliphist` (AUR) + `wl-clipboard` - back the clipboard history panel (`components/panels/Clipboard.qml`, META + V); `wl-paste --watch cliphist store` (both `--type text` and `--type image`, see `hyprland.lua`'s autostart block) is what actually feeds cliphist's history, the panel itself only ever calls `cliphist list` / `decode` / `delete` / `wipe`
- `grim` - the custom screenshot picker (`components/panels/Screenshot.qml`, META + X) freezes every screen with it before the picker appears; every capture is then taken from those frozen frames, never the live screen, so the picker's own dim/selection border can't end up in the image. `wl-clipboard` above also covers the `wl-copy` the result goes into
- `imagemagick` - crops those frozen frames for region and window captures (`helpers/screenshot-crop.sh`); monitor and all-monitor captures copy a frozen frame as-is and don't need it
- `hyprsunset` - night light (Settings > General > Night Light); the shell starts and drives it itself, so don't autostart it separately
- `libnotify` - provides `notify-send`, which the screenshot picker calls after every successful capture ("Screenshot copied to clipboard"); routes through this shell's own `NotificationServer` (`components/panels/Notification.qml`) like any other app notification, no separate daemon needed
- `solaar` (optional) - Battery Settings' Logitech-peripheral list parses `solaar show`'s default text output (no stable JSON output as of writing); skipped entirely if it's not installed
- An MPRIS-compatible media player (mpv with the mpris plugin, Spotify, etc.)
- `breeze-gtk`, `breeze-icons`, `kde-gtk-config`, `noto-fonts`, `quintom-cursor-theme-git` (AUR) - the GTK theme, icons, font, cursor and GTK modules `gtk-3.0/settings.ini` names
- `python` - `purpura.sh` uses it to apply the highlight color
- A symbolic icon theme covering `weather-*`, `media-*`, `system-*`, `audio-volume-*`, `battery-000` through `battery-100` (in 10% increments, each with a `-charging` variant) (e.g. Papirus)

**Keybind-launched apps** (swap freely — their `hl.bind` lines in `hyprland.lua`):

- `dolphin`
- `rofi`
- `solaar` — only if you have Logitech Unifying peripherals

**Bundled personal configs** (only matter if you use them):
- `fish`
- `fastfetch`
- ZapZap (not installed by `purpura.sh`)

## Notes

- Colors, font family, and notification timeout live in `Config.js` (base
  of the quickshell config, imported as `Config` from any component). The
  font is the qt6ct preset's general font (Hack, 10pt), set for every bit of
  text, so the shell looks the same with or without qt6ct - change both
  together. Edit
  it and restart `qs` to re-theme the shell alone - or re-run
  `./purpura.sh --install --no-packages` to change the highlight everywhere
  at once (it remembers the current one in
  `~/.local/state/purpura/highlight`).
- The whole shell scales with each screen's resolution: every size is
  written for 1920x1080 and grows or shrinks with the screen, so it
  takes up the same share of a 1440p or 4K screen (ultrawides scale by
  their height). This goes by the size after Hyprland's own monitor
  scale, so a 4K screen at scale 2 isn't scaled twice. To make the shell
  bigger or smaller on top of that, use the **UI Scale** slider at the
  bottom of Settings > General (50-150%, applied when you let go; saved to
  `~/.config/quickshell/uiscalesettings.json`).
- `Config.solaarEnabled` (default `true`) turns Solaar integration off
  entirely - `solaar show` is never invoked at all while it's `false`,
  not just run and ignored. Set it to `false` if solaar isn't installed
  or you just don't want it polled.
- `Config.hiddenTrayApps` (default `[]`) hides matching tray icons, e.g.
  `["solaar", "firefox"]` - matched case-insensitively as a substring
  against each item's own id/title, since apps aren't consistent about
  which of the two they actually set.
- Weather refreshes every 15 minutes via `wttr.in` — no API key needed.
- Monitor layout (resolution, position, scale, on/off) is set from the
  dashboard's Screen settings panel, not hardcoded in `hyprland.lua` -
  that file only defines the primary display. Changes are saved to
  `~/.config/quickshell/monitors.json` (gitignored - machine-specific)
  and replayed by `scripts/apply-monitors.sh` on every login.
- The lock screen is a real session lock, so if the shell ever dies while
  it's up - or it won't take your password - the session stays locked.
  To get back in, switch to another TTY (Ctrl+Alt+F3), log in, and run
  `pkill -x 'qs|quickshell'; hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'`,
  then switch back and start the shell again (`qs` in a terminal).

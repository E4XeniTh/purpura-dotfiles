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
| **Lock screen** | Full-screen lock, authenticates via PAM |
| **Power menu** | Shutdown / reboot / suspend / logout |
| **Tray** | System tray with a themed right-click menu per item |

Also included: the Hyprland config (`hypr/`), and configs for kitty,
fish, rofi, fastfetch, GTK, and ZapZap.

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
```

## Install

```bash
cp -r .config/hypr .config/quickshell ~/.config/
```

Copy the rest (`fish`, `kitty`, `rofi`, `fastfetch`, `gtk-3.0`,
`gtk-4.0`, `ZapZap`) too if you want those as well.

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

Two small C helpers need compiling locally - they're gitignored since
they're machine-specific.

- **`auth`**: the lock screen checks your real login password through
  it, over PAM, so the shell process itself never touches `/etc/shadow`.
- **`cava_bridge`**: feeds the default sink's audio into `libcava` for
  the dashboard's visualizer - not something a prebuilt binary can cover
  since it's linked against a specific fork of `libcava`.

```bash
cd ~/.config/quickshell/helpers
make
sudo cp ../pam.d/quickshell-auth /etc/pam.d/quickshell-auth
```

Re-run `make` after pulling changes to `helpers/auth.c` or
`helpers/cava_bridge.c`.

## Dependencies and affected apps

Beyond a base Arch install:

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
- `wireplumber`
- `ddcutil` - Screen Settings' brightness sliders and Bar.qml's brightness widget use this for external DDC/CI monitors
- `brightnessctl` (optional) - used instead of `ddcutil` for a laptop's own built-in panel (`eDP-*`), which ddcutil can't reach at all; only needed if you actually have one
- `playerctl`
- `jq`
- `curl`
- `pam`
- `xembedsniproxy` - (useful if you emulate windows applications through Wayland)
- `networkmanager` - provides `nmcli`, which Network Settings' Connections tab also uses to detect a ZeroTier interface (`Quickshell.Networking` never sees it directly)
- `zerotier-one` (AUR, optional) - only if you actually use ZeroTier; its `zt*` interface shows up via `nmcli` on its own, nothing here calls `zerotier-cli` (it needs root and isn't used)
- `upower` - Battery Settings' system-battery row and Bar.qml's battery widget both read through `Quickshell.Services.UPower`, which needs the `upower` daemon running
- `solaar` (optional) - Battery Settings' Logitech-peripheral list parses `solaar show`'s default text output (no stable JSON output as of writing); skipped entirely if it's not installed
- An MPRIS-compatible media player (mpv with the mpris plugin, Spotify, etc.)
- A symbolic icon theme covering `weather-*`, `media-*`, `system-*`, `audio-volume-*`, `battery-000` through `battery-100` (in 10% increments, each with a `-charging` variant) (e.g. Papirus)

**Keybind-launched apps** (swap freely — `local` vars at the top of `hyprland.lua`):

- `dolphin`
- `rofi`
- Waterfox (Flatpak)
- Obsidian
- `solaar` — only if you have Logitech Unifying peripherals

**Bundled personal configs** (only matter if you use them):
- `fish`
- `fastfetch`
- ZapZap

## Notes

- Colors, font family, and notification timeout live in `Config.js` (base
  of the quickshell config, imported as `Config` from any component). Edit
  it and restart `qs` to re-theme.
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
  and replayed by `scripts/apply-monitors.sh` on every login. Screen
  Settings' "Remember on boot" checkbox (on by default) controls
  whether that replay happens at all - turn it off to have
  `hyprland.lua`'s own static monitor line win every boot instead,
  without touching `monitors.json` itself.

# purpura-dotfiles

Hyprland + Quickshell desktop shell. Sharp corners, translucent black panels,
purple accents — colors and other shell-wide settings live in `Config.js`
at the base of the quickshell config.

## What's in here

| Component | What it does |
|---|---|
| **Bar** | Top bar: tray, clock (opens the dashboard), notification icon (opens the notification center) |
| **Dashboard** | Dropdown from the bar: clock, weather, calendar, now-playing + media controls, quick toggles, power/lock |
| **Notification center** | Toast popups for new notifications, plus a persistent (capped, newest-first) history panel with clear-all/dismiss |
| **Lock screen** | Full-screen lock, authenticates via PAM |
| **Power menu** | Shutdown / reboot / suspend / logout |
| **Tray** | System tray with a themed right-click menu per item |

Dashboard is the only multi-file component (`components/dashboard/`: the
main file plus Calendar/Weather/NowPlaying). No component has a
`...State.qml` singleton anymore - each keeps its own open/closed state
locally and exposes it through an `IpcHandler`, which is also how
cross-file control (a keybind, or one component nudging another) works
now:

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

### Lock screen password check

The lock screen authenticates against your real Linux account via a small
PAM helper binary, so the shell process itself never touches `/etc/shadow`.

```bash
cd ~/.config/quickshell/helpers
make
sudo cp ../pam.d/quickshell-auth /etc/pam.d/quickshell-auth
```

No setuid bit needed on the helper: `pam_unix` already delegates the shadow
read to the setuid-root `unix_chkpwd`, same as `su`/i3lock/swaylock.

Re-run `make` after pulling changes to `helpers/auth.c` — the compiled
binary is gitignored since it's machine-specific.

> **Why not `Quickshell.Services.Pam`?** Tried it first — it's the more
> "native" approach and needs no separate helper binary. But its internal
> subprocess consistently failed with `PAM_PERM_DENIED` even with a
> healthy system PAM stack (`su` worked fine, `unix_chkpwd` correctly
> setuid, no sandboxing involved), pointing at a bug or limitation in
> Quickshell's own implementation rather than anything in this repo. Worth
> retrying against a future Quickshell release.

### Cava visualizer

`make` (same directory/command as above) also builds `cava_bridge`, a
small helper linked against `libcava` and `libpulse-simple`, feeding the
default sink's monitor audio through it. `dashboard/Cava.qml` runs the
compiled binary directly.

> Went this route after the `cava` CLI's own raw/ascii output mode kept
> producing frozen bars in this exact setup. `libcava` here is
> [LukashonakV/cava](https://github.com/LukashonakV/cava), a fork of
> karlstav/cava built as a shared library (`meson setup build && meson
> compile -C build && meson install -C build` per its README) - the
> plain Arch `cava` package is just the CLI and doesn't include this.

## Dependencies

**Core**
- [Hyprland](https://hyprland.org)
- [Quickshell](https://quickshell.org) — needs to be built with Pipewire
  and SystemTray service support (the default for the AUR
  `quickshell`/`quickshell-git` packages)
- `qt6-5compat` — `Qt5Compat.GraphicalEffects`, used to recolor symbolic
  icons (weather icon, shuffle/repeat) to the theme color
- `gcc`/`make` (`base-devel`) — to build the lock screen's PAM helper
  and the cava bridge helper
- [`libcava`](https://github.com/LukashonakV/cava) (built/installed via
  its own `meson` setup - provides `cava/cavacore.h` + the `libcava`
  pkg-config module) and `libpulse` — needed to build
  `helpers/cava_bridge.c`; `pactl` (part of `libpulse`/
  `pulseaudio-utils`) is also used at runtime to find the default sink

**CLI tools** (invoked directly, not linked against)
- `curl` — weather (`dashboard/Weather.qml`)
- `hostname` — dashboard greeting text
- `systemctl`, `hyprctl` — power menu actions and screen settings
  (`dashboard/settings/ScreenSettings.qml` reads/writes monitor config
  through `hyprctl`) - systemd and Hyprland are already required, not
  extra installs

**Services**
- `pipewire` (+ a session manager, e.g. `wireplumber`) — volume OSD
- An MPRIS-compatible media player (mpv with the mpris plugin, Spotify,
  etc.) — now-playing widget shows nothing without one running
- PAM (`pam` package) — already a base Arch dependency; the installed
  service does `auth include system-auth`, so whatever your system's real
  auth stack does (faillock, etc.) still applies

**Icon theme**
- A theme with `weather-*-symbolic`, `media-*-symbolic`,
  `system-*-symbolic`, and `audio-volume-*-symbolic` icons. Coverage
  varies by theme — [Papirus](https://archlinux.org/packages/extra/any/papirus-icon-theme/)
  has good `weather-*` coverage; `breeze-icons` (KDE) works too but with
  gaps.

## Notes

- Colors, font family, and notification timeout live in `Config.js` (base
  of the quickshell config, imported as `Config` from any component). Edit
  it and restart `qs` to re-theme. Will also hold options-menu settings
  once that exists.
- Weather refreshes every 15 minutes via `wttr.in` — no API key needed.
- Monitor layout (resolution, position, scale, on/off) is set from the
  dashboard's Screen settings panel, not hardcoded in `hyprland.lua` -
  that file only defines the primary display. Changes are saved to
  `~/.config/hypr/monitors.conf` and replayed via `hyprctl keyword
  monitor` by `scripts/apply-monitors.sh` on every login (see
  `hyprland.lua`'s autostart block) so they survive a restart.

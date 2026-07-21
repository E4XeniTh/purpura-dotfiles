# purpura-dotfiles

Hyprland + Quickshell desktop shell. Sharp corners, translucent black panels,
purple accents — the accent color auto-follows Hyprland's `col.active_border`,
so re-theming is just a `hyprland.conf` edit away.

## What's in here

| Component | What it does |
|---|---|
| **Bar** | Top bar: tray, clock (opens the dashboard), notification icon (placeholder) |
| **Dashboard** | Dropdown from the bar: clock, weather, calendar, now-playing + media controls, quick toggles, power/lock |
| **Lock screen** | Full-screen lock, authenticates via PAM |
| **Power menu** | Shutdown / reboot / suspend / logout |
| **Tray** | System tray with a themed right-click menu per item |

## Install

```bash
cp -r .config/hypr .config/quickshell ~/.config/
```

That's it — the lock screen's PAM config ships inside `quickshell/pam/`, so
there's no separate build or system install step.

## Dependencies

**Core**
- [Hyprland](https://hyprland.org)
- [Quickshell](https://quickshell.org) — needs to be built with PAM,
  Pipewire, and SystemTray service support (the default for the AUR
  `quickshell`/`quickshell-git` packages)
- `qt6-5compat` — `Qt5Compat.GraphicalEffects`, used to recolor symbolic
  icons (weather icon, shuffle/repeat) to the theme color

**CLI tools** (invoked directly, not linked against)
- `curl` — weather (`dashboard/Weather.qml`)
- `hostname` — dashboard greeting text
- `grep` — reading the accent color out of `hyprland.conf`
  (`ThemeLoader.qml`)
- `systemctl`, `hyprctl` — power menu actions (systemd and Hyprland are
  already required, not extra installs)

**Services**
- `pipewire` (+ a session manager, e.g. `wireplumber`) — volume OSD
- An MPRIS-compatible media player (mpv with the mpris plugin, Spotify,
  etc.) — now-playing widget shows nothing without one running
- PAM (`pam` package) — already a base Arch dependency; the bundled config
  does `auth include system-auth`, so whatever your system's real auth
  stack does (faillock, etc.) still applies

**Icon theme**
- A theme with `weather-*-symbolic`, `media-*-symbolic`,
  `system-*-symbolic`, and `audio-volume-*-symbolic` icons. Coverage
  varies by theme — [Papirus](https://archlinux.org/packages/extra/any/papirus-icon-theme/)
  has good `weather-*` coverage; `breeze-icons` (KDE) works too but with
  gaps.

## Notes

- The accent color reads from `hyprland.conf` once at Quickshell startup
  (`ThemeLoader.qml`). Change `col.active_border` and restart `qs` to
  re-theme.
- Weather refreshes every 15 minutes via `wttr.in` — no API key needed.

# purpura-dotfiles

Hyprland + Quickshell desktop shell. Sharp corners, translucent black panels,
purple accents — colors and other shell-wide settings live in `Config.js`
at the base of the quickshell config.

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

## Dependencies

**Core**
- [Hyprland](https://hyprland.org)
- [Quickshell](https://quickshell.org) — needs to be built with Pipewire
  and SystemTray service support (the default for the AUR
  `quickshell`/`quickshell-git` packages)
- `qt6-5compat` — `Qt5Compat.GraphicalEffects`, used to recolor symbolic
  icons (weather icon, shuffle/repeat) to the theme color
- `gcc`/`make` (`base-devel`) — to build the lock screen's PAM helper

**CLI tools** (invoked directly, not linked against)
- `curl` — weather (`dashboard/Weather.qml`)
- `hostname` — dashboard greeting text
- `systemctl`, `hyprctl` — power menu actions (systemd and Hyprland are
  already required, not extra installs)

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

- Colors and other shell-wide settings live in `Config.js` (base of the
  quickshell config, imported as `Config` from any component). Edit it and
  restart `qs` to re-theme. Will also hold notification/options-menu
  settings once those exist.
- Weather refreshes every 15 minutes via `wttr.in` — no API key needed.

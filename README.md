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
| **Bar** | Top bar: tray, clock (opens the dashboard), volume/brightness/battery widgets, notification icon (opens the notification center). Right-clicking the volume widget picks the playback device; right-clicking the brightness widget lists every monitor but the primary with a checkbox - click one to switch it on or off at once and close the menu (the same as switching it in Settings > Display and pressing Apply) - and opens the Display or Night Light settings |
| **Drag to a workspace** | Drag a window with META + left click (or wherever Drag window is bound in Settings > Shortcuts - all of this follows it) and let go on a workspace in the bar's workspace widget to send it there - while the cursor's on a workspace, that workspace lights up and the window turns invisible so the bar stays in view (it stays invisible on the separator between two monitors' workspaces too, with nothing lit), with its app's icon (the one the widget draws it with) right under the cursor instead and its miniature gone from its box (both come back when the cursor moves off), a floating window lands where it was on its own monitor before the drag, and letting go anywhere else is an ordinary drag. On monitors without the bar, the same workspace widget floats at the top of the screen while a drag is on and the cursor's on that monitor (reserving no room), to drop onto there too - and while META (Drag window's modifier) is held there, drag or not, so a window can be grabbed from it too. The windows drawn in the widget can be grabbed the same way, with META + left click: the window comes off whichever workspace it's on the moment the button goes down, onto the workspace shown there, and is dragged like any other from then on - onto another workspace to send it there, or out of the bar to put it down there (one that was tiled goes back into the tiling, and one that was fullscreen is fullscreen again when it's sent to a workspace; let go without moving, it goes back where it was). A META + left click on the widget that misses every window drawn there - an empty workspace, the gap between two, the widget's edge - drags nothing, rather than the window under the widget. A plain click still switches workspace. Comes with `hypr/purpura.lua` (see below) |
| **Workspaces** | One book of every workspace, kept by `hypr/purpura.lua` over Hyprland's own: each Hyprland workspace gets purpura's number - 1-5 for the ones Settings > Display pins to the monitors (META + 1-5 go to them), and from 6 up for every other, kept as long as it's there - and a type: pinned, spare (what a monitor none of 1-5 is on gets), reserved, fullscreen, new or other. The bar's workspace widget orders the workspaces by it, numbering the pinned ones only, and the workspace OSD, Settings > Display, Next workspace and the workspaces of their own all go by it. Pins are Hyprland's own persistent workspaces on their monitors, each monitor's lowest its default, so Hyprland keeps them, makes one that's missing and brings them home when their monitor's back - and they survive `hyprctl reload`, as the book's remembered for the session (in `$XDG_RUNTIME_DIR`). Your own `hyprland.lua` rules for workspaces 1-5 (gaps, a layout) stay, as rules for one workspace merge |
| **Workspaces of their own** | META + CTRL + W (Reserve workspace) gives the focused window an empty unmanaged workspace - one past 5, as Settings > Display only pins 1-5 to a monitor: the one its monitor's showing, when that's one of those and holds nothing else, or else a new one, numbered from 6. The window goes there, the monitor switches to it, and the workspace stays bound to that monitor. With Create Workspace For Fullscreen Apps (Settings > General > Shell > Main Bar; off unless turned on), a fullscreen app opening - fullscreen as it opens, or within its first five seconds, as games do; maximized doesn't count - is given one the same way, on its own monitor, and the workspace OSD shows it there, dashed in the fullscreen color, even with Show Workspace OSD on switch (Settings > General > Shell > Workspace OSD) turned off; with it off, the app stays where it opened. META + Tab switches the monitor under the cursor to its next workspace by number, as the widget has them left to right - empty pins included, as Hyprland keeps those (round to the first after the last), and META + CTRL + Tab makes an empty one on the monitor under the cursor, bound to it, and switches that monitor to it - on a monitor other than the focused one, without moving the cursor or taking the focus. As a monitor with more than one workspace switches, the workspace OSD shows every one of them - unmanaged ones too, with no number - one with a window in real fullscreen dashed in the fullscreen color, one with a window maximized solid in it, and the border round the one it's on alike (dashed on a fullscreen one, in the fullscreen color on either); a monitor with just the one shows none. In the bar's workspace widget, a workspace with a window in real fullscreen - the whole monitor, not maximized - has a dashed border, and a monitor's unmanaged workspaces show (with no number) whenever it has pinned ones of its own - on one with none pinned, with Show Single Workspace Monitors (Settings > General > Shell > Main Bar) off, only once it has two or more of them. An existing `hyprland.lua` gets the three binds from `hypr/purpura.lua` unless it or Settings > Shortcuts already has those keys bound (or unbound) |
| **How apps open** | Settings > General > Windows: pick an app - one that's open, or any other by its window class - and set how its windows look as they open: as it likes, tiled, floating (at a size, centered or not), maximized or fullscreen, how see-through, and the animation they come up with. kitty's floating window comes pre-included, at the size `hyprland.lua`'s `kittyrule` gives it. Each change applies at once, to windows opening from then on (opacity and animation to the ones open now too), and is kept in `~/.config/quickshell/windowrules.json` and `hypr/windowrules.lua`, which `hypr/purpura.lua` reads each time Hyprland loads its config. Once something's been changed there, the list takes over from `hyprland.lua`'s own `kittyrule` |
| **Dashboard** | Clock, weather, calendar, now-playing + media controls, quick settings (audio/network/bluetooth/screen/battery), power/lock. While a power action is set to run later (see Power menu), a small window under the dashboard shows which and the time left, with an X that cancels it |
| **Notification center** | Toast popups, plus a persistent (capped, newest-first) history panel |
| **Clipboard history** | cliphist-backed text/image history panel (META + V), with a full-content preview pane, click-to-copy, and right-click delete. Opens with the newest entry selected, so it works without the mouse: Up/Down (Page Up/Down, Home/End) choose, Enter copies, Delete removes, Esc closes |
| **Screenshot picker** | Custom region/window/monitor/all-monitors picker (META + X) - freezes the screen, dims it, and captures straight to the clipboard via grim |
| **Lock screen** | A real session lock - no keybind gets through but volume, brightness and media keys - over the blurred desktop, with the time above the password box and the dashboard's now-playing card beside it while something plays. Authenticates via PAM |
| **Auto-lock, dim and suspend** | Settings > General > Power: locks after a set time without input, then optionally dims the monitors (all together, or each after its own inactivity, naming the ones still active if you like) and suspends, counting down on the main monitor first. The dim covers everything, the settings screen and the lock screen included |
| **Manual dim** | META + BackSpace dims every monitor but the one the mouse is on, each time it's pressed. A dimmed one wakes when the mouse moves onto it. An existing `hyprland.lua` needs the bind from the `.example` added by hand, or bind it in Settings > Shortcuts |
| **Mouse & input languages** | Settings > General > Input: mouse sensitivity and acceleration, and the keyboard languages you type in. With more than one, META + - switches to the next and shows which is on. Kept after Hyprland config reloads. An existing `hyprland.lua` needs the bind from the `.example` added by hand, or bind it in Settings > Shortcuts |
| **Shortcuts** | Settings tab with a clickable keyboard and mouse: bound keys and buttons are lit, and clicking one adds or removes its binds. The mouse has left, right and middle click, the wheel's up and down, and Forward and Back on its side; the + below the wheel opens the rest (a tilting wheel, extra buttons 6 - 16 and the F13 - F24 keys many-button mice send), where pressing a button finds it too. Mouse buttons can also drag or resize windows; left click needs a modifier. Saved to `hypr/shortcuts.lua`, which `hyprland.lua` loads with `dofile`. An existing `hyprland.lua` needs the `pcall(dofile, ...)` line from the `.example` added by hand, in place of an older `pcall(require, "shortcuts")`: Hyprland reloads its whole config whenever a file it `require`d changes, resetting the monitor layout on every save |
| **Display** | Settings tab with every monitor, laid out where it sits: resolution, refresh rate, scale, rotation, position and workspaces for the one picked, right click to switch one on or off, double click to make it primary. Middle click renames a display for the shell only - the bar's brightness menu, Identify and the dim screen's active monitors use the name too, and Hyprland still goes by the port |
| **Sound** | Settings tab with the playback and recording devices - right click makes one the default, scrolling changes its volume, middle click renames it for the shell only (the bar's volume menu uses the name too) - and a volume mixer for the apps playing |
| **Connections** | Settings tab with everything this computer connects through as a directory tree, an icon on every row: user@host branches into its devices (Solaar, Wi-Fi, Bluetooth, ZeroTier, Ethernet), each into what's connected through it (Logitech peripherals, remembered and connected Wi-Fi networks, paired Bluetooth devices, ZeroTier networks, the wired connection). Borders show the state - lit for connected, brighter for connected and remembered, dark for remembered, red for disabled - and anything with a battery (a laptop, a mouse, a controller) gets a segmented bar beside its row showing its charge, red when low. Left click shows its details on the right (addresses, signal, live traffic, a Wi-Fi network search to join, nearby Bluetooth devices to pair...), middle click renames it for the shell only, right click disables/disconnects it - or forgets one that's only remembered. Solaar is asked often while the tab is open, and otherwise once as the shell starts and every 5 minutes while neither the dashboard nor Settings is open, so its devices are there the first time the tab opens |
| **Power menu** | Shutdown / reboot / suspend / logout / lock. Right-click one to run it later (a hint in the screen's bottom right corner says so; not while one's already waiting): type a number, pick Hours or Minutes, Enter (Escape or a click outside backs out). While it waits, the menu shows the time left above the buttons, with an X to cancel, and its button in red |
| **Tray** | System tray with a themed right-click menu per item |

Also included: the Hyprland config (`hypr/`), and configs for kitty,
fish, rofi, fastfetch, GTK, ZapZap, and mpv (with the uosc, thumbfast,
chapters and slicing scripts).

The shell (`.config/quickshell/`) is `shell.qml`, which puts it all
together, `Config.js` (colors, font, sizes), `helpers/` (the C helpers and
scripts) and `components/`, by area:

| Folder | What's in it |
|---|---|
| `bar/` | The bar and its widgets (tray, workspaces, volume/brightness/battery) |
| `dashboard/` | The dashboard and its cards (calendar, weather, now playing, visualizer, system monitor) |
| `settings/` | The settings screen and its tabs; `cards/` and `controls/` hold the pieces the tabs are built from |
| `panels/` | Notifications, clipboard, screenshot picker, updater, dropdown console |
| `osd/` | Volume, brightness and input language popups (placed, sized and stacked by `OsdHost.qml` - Settings > General > Shell > OSD), plus the workspace and fullscreen-hint ones |
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
  (offering to set up `yay` if you have no AUR helper): rofi, Dolphin, fish
  and fastfetch come along, and only Solaar is asked about first
- copies the configs into `~/.config`, backing up every file it changes
  to `~/.config/purpura-backups/<date>/` first - mpv's included, though
  mpv itself isn't installed
- creates `hyprland.lua`, `hyprpaper.conf` and `ZapZap.conf` from their
  `.example` once and never overwrites them after that (picking a new
  color only updates `hyprland.lua`'s border colors)
- copies `hyprland.lua`'s fullscreen border color (the `border_color` of
  its `fullscreenrule`) into the shell's `Config.js` as `fgcolorfullscreen`,
  which the bar's workspace widget draws a workspace holding a fullscreen
  window in - so after changing that color by hand, run
  `./purpura.sh --install --no-packages` again to match
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
- The updater's dropdown shows purpura's state under the package list: how
  many new changes and the newest one's description, the installed and
  newest versions, and anything that would get in the way (local commits or
  changes in the checkout, no network).
- Right-clicking the updater button runs purpura's update just before the
  firmware updates: a fast-forward `git pull` of the checkout, then
  `./purpura.sh --update`, which installs the new configs and helpers, keeps
  your color, and only adds core packages that are
  missing (never the optional apps).

The dropdown itself says what's waiting in plain words: how many updates are
available (or that everything's up to date), when it last checked, with a
**Check now** button;
then a section each for system packages (Arch repositories and AUR), Flatpak
apps, purpura and firmware, each with its own **Update** button. System
packages and Flatpak apps start collapsed, showing just how many updates
they have - click one to slide it open onto its updates (name, where it's
from, old → new version); the dropdown grows with it, and a long list
scrolls, with a scroll bar you can drag. A check that couldn't run
says so in its section - pacman-contrib or yay not installed, no network -
rather than passing for "up to date". **Update all** at the bottom runs every
kind in turn, the same as right-clicking the updater button; it all happens
in a terminal window, where you confirm and type your password.

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
`gtk-4.0`, `Kvantum`, `qt6ct`, `kdeglobals`, `ZapZap`, `mpv`, and
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
- `bluez` + `bluez-utils` - the Connections tab's Bluetooth adapters and devices
- `ddcutil` - Screen Settings' brightness sliders and Bar.qml's brightness widget use this for external DDC/CI monitors
- `brightnessctl` (optional) - used instead of `ddcutil` for a laptop's own built-in panel (`eDP-*`), which ddcutil can't reach at all; only needed if you actually have one
- `playerctl`
- `jq`
- `curl`
- `pam`
- `xembedsniproxy` (AUR) - (useful if you emulate windows applications through Wayland)
- `kservice` - `kbuildsycoca6`, run at login so KDE apps like Dolphin see installed apps
- `networkmanager` - provides `nmcli`, which the Connections tab also uses for addresses, DNS and the Wi-Fi access point's details, and to detect a ZeroTier interface (`Quickshell.Networking` never sees it directly); `iproute2`'s `ip` gives the addresses and routes
- `zerotier-one` (AUR, optional, not installed by `purpura.sh`) - only if you actually use ZeroTier; its `zt*` interface shows up via `nmcli` on its own, nothing here calls `zerotier-cli` (it needs root and isn't used). The Connections tab starts and stops `zerotier-one.service` through systemctl, which asks for your password
- `upower` - Battery Settings' system-battery row and Bar.qml's battery widget both read through `Quickshell.Services.UPower`, which needs the `upower` daemon running
- `cliphist` (AUR) + `wl-clipboard` - back the clipboard history panel (`components/panels/Clipboard.qml`, META + V); `wl-paste --watch cliphist store` (both `--type text` and `--type image`, see `hyprland.lua`'s autostart block) is what actually feeds cliphist's history, the panel itself only ever calls `cliphist list` / `decode` / `delete` / `wipe`
- `grim` - the custom screenshot picker (`components/panels/Screenshot.qml`, META + X) freezes every screen with it before the picker appears; every capture is then taken from those frozen frames, never the live screen, so the picker's own dim/selection border can't end up in the image. `wl-clipboard` above also covers the `wl-copy` the result goes into
- `imagemagick` - crops those frozen frames for region and window captures (`helpers/screenshot-crop.sh`); monitor and all-monitor captures copy a frozen frame as-is and don't need it
- `hyprsunset` - night light (Settings > General > Night Light); the shell starts and drives it itself, so don't autostart it separately
- `libnotify` - provides `notify-send`, which the screenshot picker calls after every successful capture ("Screenshot copied to clipboard"); routes through this shell's own `NotificationServer` (`components/panels/Notification.qml`) like any other app notification, no separate daemon needed
- `solaar` (optional) - the Connections tab's Logitech peripherals (battery, kind, receiver, firmware...) come from `solaar show`'s default text output (no stable JSON output as of writing, see `dashboard/SolaarParse.js`); skipped entirely if it's not installed
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
- mpv - uosc, thumbfast, chapters and slicing scripts (not installed by `purpura.sh`)

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
- The shell's own side of Hyprland lives in `hypr/purpura.lua`, not in
  your `hyprland.lua`: Close Window closing what's under the mouse (the
  dropdown console included), dropping a dragged window on a workspace in
  the bar and grabbing one from it (on whichever combo "Drag window" is bound to),
  the book of workspaces (Settings > Display's pins included), the Reserve
  workspace, Next workspace and New workspace actions and a fullscreen app's
  workspace of its own (with Create Workspace For Fullscreen Apps on), the
  rules Settings > General > Windows makes, and the
  layer rules for the shell's panels. It's installed and
  updated with everything else, and `hyprland.lua` runs it with one line at
  the start of its binds:
  `pcall(loadfile(os.getenv("HOME") .. "/.config/hypr/purpura.lua") or function() end, mainMod)`.
  An existing `hyprland.lua` needs that line added by hand, in place of the
  Close Window block (`pair`, `contains`, `windowUnderCursor` and the
  `hl.dsp.window.close` wrapper), the three drop binds on `mouse:272` and
  the `powermenu`, `settingsscreen` and `dropdownconsole` layer rules, if
  it has them. If one of its parts ever fails to load, a notification says
  which, and the rest still loads.
- Monitor layout (resolution, position, scale, on/off, pinned
  workspaces) is set in Settings > Display, not hardcoded in
  `hyprland.lua` - that file only defines the primary display. Set
  Default saves it to `~/.config/quickshell/monitors.json` (gitignored -
  machine-specific), and `scripts/apply-monitors.sh` replays it on every
  login: the monitors first, then, once they've settled, the pins handed to
  `hypr/purpura.lua`'s book of workspaces, which has Hyprland keep each on
  its monitor and switches every monitor to its lowest pin, ending on the
  primary. Apply hands the book the pins the same way; it switches a monitor
  that isn't showing one of its own to its lowest (but not one showing an
  app's own workspace) and brings the windows along off a workspace no
  monitor has any more.
- The lock screen is a real session lock, so if the shell ever dies while
  it's up - or it won't take your password - the session stays locked.
  To get back in, switch to another TTY (Ctrl+Alt+F3), log in, and run
  `pkill -x 'qs|quickshell'; hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'`,
  then switch back and start the shell again (`qs` in a terminal).

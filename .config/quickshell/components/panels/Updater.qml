import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "../../Config.js" as Config
import "../settings/controls"

// Update checker + dropdown, modeled on apdatifier (github.com/exequtic/
// apdatifier): periodically checks pacman/AUR and flatpak for pending
// updates, surfaces a highlighted bar button (Bar.qml) when any are
// found, and a dropdown saying what's waiting, in plain words:
//
//   - at the top, how many updates are ready (or that everything's up to
//     date), when it last looked, and a button to look again now
//   - a section for each kind - system packages (the Arch repositories and
//     the AUR, which yay updates together) and Flatpak apps - with what it
//     is, how many are waiting, each package's name, where it comes from
//     and old -> new version, and its own Update button; a checker that
//     isn't installed or couldn't reach its server says so there instead
//     of passing for "up to date"
//   - purpura itself: with "Follow Purpura versioning" on, whether there's
//     a new version, how many changes and the newest one's description,
//     the installed and newest dates; with it off, where to turn it on.
//     Its Update button is there either way
//   - firmware, which isn't checked here, with a button that checks and
//     installs it (left out where fwupd isn't installed)
//   - one big button installing everything (as right-clicking the bar
//     button does), and a line saying that it all happens in a terminal
//     window, asking for confirmation and the password
//
// The list scrolls once it's long, with a thin bar showing where; purpura,
// firmware and the big button stay in view under it.
//
// Mutually exclusive with Notification.qml's own history panel (each holds
// a reference to the other and closes it when it itself opens, same
// convention Dashboard.qml/SettingsScreen.qml already use for each other),
// and auto-closes the same way (5s after the mouse last left it).
// Structurally mirrors Notification.qml's own history panel throughout -
// same box-grow-open animation, same fullscreen-aware margin/exclusiveZone
// handling - since that's the closest existing analog to "a small
// bar-button dropdown that behaves like the notification one."
Scope {
    id: root

    // Settings > General's global UI Scale (UiScale.qml), from shell.qml -
    // multiplied into every window's Config.uiScale below.
    property real shellScale: 1.0

    // EdgeGaps.qml: lines this up with the bar's right end.
    property var edgeGaps: null

    // Cross-wired from shell.qml, same as Dashboard.qml/SettingsScreen.qml's
    // own mutual-exclusivity wiring.
    property var notification: null

    property bool dropdownOpen: false

    onDropdownOpenChanged: {
        if (root.dropdownOpen) {
            autoCloseTimer.restart()
            if (root.notification) root.notification.centerOpen = false
        } else {
            autoCloseTimer.stop()
        }
    }

    // Same 5s "no hover" auto-close as Notification.qml's own history
    // panel - HoverHandler on mainRect below restarts/stops this exactly
    // the same way.
    Timer {
        id: autoCloseTimer
        interval: 5000
        repeat: false
        onTriggered: root.dropdownOpen = false
    }

    // ---------------- settings (own file, watched directly - same
    // decoupled-from-ShellSettings.qml pattern Bar.qml/WorkspaceRow.qml
    // already use for barsettings.json) ----------------
    FileView {
        id: updaterSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/updatersettings.json"
        watchChanges: true
        onFileChanged: reload()
    }

    readonly property var updaterSettingsStore: {
        try {
            return JSON.parse(updaterSettingsFile.text())
        } catch (e) {
            return {}
        }
    }

    readonly property bool highlightOnUpdates: root.updaterSettingsStore.highlightOnUpdates !== false
    readonly property int checkIntervalMinutes: {
        const raw = root.updaterSettingsStore.checkIntervalMinutes
        const n = Number(raw)
        return (raw !== undefined && !isNaN(n) && n > 0) ? n : 30
    }
    // "Follow Purpura versioning" - off unless turned on.
    readonly property bool followPurpura: root.updaterSettingsStore.followPurpura === true

    // ---------------- update data ----------------
    property var repoUpdates: []
    property var aurUpdates: []
    property var flatpakUpdates: []

    readonly property var allUpdates: root.repoUpdates.concat(root.aurUpdates).concat(root.flatpakUpdates)
    readonly property int updateCount: root.allUpdates.length
    // The packages plus purpura itself - what the bar button lights up for.
    readonly property int totalUpdates: root.updateCount + (root.purpuraUpdateAvailable ? 1 : 0)

    // How each checker got on last time: "ok", "missing" (not installed) or
    // "failed" (it ran but couldn't check - offline, say). Each check runs
    // through bash, which exits 127 for a command that isn't there.
    property string repoCheck: "ok"
    property string aurCheck: "ok"
    property string flatpakCheck: "ok"
    readonly property bool hasYay: root.aurCheck !== "missing"
    readonly property bool hasFlatpak: root.flatpakCheck !== "missing"
    // fwupd, for the firmware: not always installed either.
    property bool hasFwupd: true

    // Whether something couldn't be looked at, so "nothing found" isn't
    // the same as "up to date".
    readonly property bool checkedEverything: root.repoCheck === "ok" && root.flatpakCheck !== "failed"
        && !(root.followPurpura && !!root.purpura && (root.purpura.state !== "ok" || root.purpura.fetchFailed))

    // Any check still running, and when the last round finished.
    readonly property bool checking: repoCheckProcess.running || aurCheckProcess.running
        || flatpakUpdatesProcess.running || root.purpuraChecking
    property var lastChecked: null
    onCheckingChanged: {
        if (!root.checking) root.lastChecked = new Date()
    }

    function checkAll() {
        repoCheckProcess.running = false
        repoCheckProcess.running = true
        repoNameProcess.running = false
        repoNameProcess.running = true
        aurCheckProcess.running = false
        aurCheckProcess.running = true
        flatpakUpdatesProcess.running = false
        flatpakUpdatesProcess.running = true
        flatpakInstalledProcess.running = false
        flatpakInstalledProcess.running = true
        fwupdCheckProcess.running = true
        if (root.followPurpura) root.checkPurpura()
    }

    Process {
        id: fwupdCheckProcess
        command: ["bash", "-c", "command -v fwupdmgr >/dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.hasFwupd = exitCode === 0
        }
    }

    Component.onCompleted: root.checkAll()

    // `qs ipc call updater check` is how the update terminal asks for a
    // recheck once it's done (see runUpdate()); toggle/show/hide work the
    // dropdown, same as the notification panel's.
    IpcHandler {
        target: "updater"
        function check(): void { root.checkAll() }
        function toggle(): void { root.dropdownOpen = !root.dropdownOpen }
        function show(): void { root.dropdownOpen = true }
        function hide(): void { root.dropdownOpen = false }
    }

    // ---------------- purpura itself ----------------
    // A version of purpura is a commit of the checkout it was installed
    // from; helpers/purpura-update.sh fetches that checkout's upstream and
    // reports where things stand, as JSON (see it for the fields). The
    // settings file loads after startup, so turning on also covers the
    // first check.
    property var purpura: null
    property bool purpuraChecking: false

    readonly property bool purpuraUpdateAvailable: root.followPurpura && !!root.purpura
        && root.purpura.state === "ok" && root.purpura.behind > 0

    onFollowPurpuraChanged: {
        if (root.followPurpura) root.checkPurpura()
        else root.purpura = null
    }

    function checkPurpura() {
        root.purpuraChecking = true
        purpuraCheckProcess.running = false
        purpuraCheckProcess.running = true
    }

    Process {
        id: purpuraCheckProcess
        command: ["bash", Quickshell.shellDir + "/helpers/purpura-update.sh", "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                let report = null
                try {
                    report = JSON.parse(text)
                } catch (e) {
                    report = { state: "error" }
                }
                root.purpuraChecking = false
                if (!root.followPurpura) return
                root.purpura = report
                root.notifyAboutPurpura()
            }
        }
    }

    // Once per new version: the newest commit already notified about is
    // remembered across restarts, so only a commit newer than that notifies.
    FileView {
        id: purpuraNotifiedFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/purpura/notified"
        blockLoading: true
        printErrors: false
    }

    property string purpuraNotified: purpuraNotifiedFile.text().trim()

    // The hint is what makes clicking it open this dropdown (see
    // Notification.qml).
    function notifyAboutPurpura() {
        const p = root.purpura
        if (!root.purpuraUpdateAvailable || !p.latest || p.latest === root.purpuraNotified) return
        root.purpuraNotified = p.latest
        purpuraNotifiedFile.setText(p.latest + "\n")
        Quickshell.execDetached([
            "notify-send", "-a", "Purpura", "-i", "system-software-update-symbolic",
            "-h", "boolean:x-purpura-updater:true",
            "Purpura update available",
            p.behind + " new commit" + (p.behind === 1 ? "" : "s") + ", newest: " + p.latestSubject
        ])
    }

    function homePath(path) {
        const home = Quickshell.env("HOME")
        return (home && path && path.startsWith(home)) ? "~" + path.slice(home.length) : (path || "")
    }

    // ---------------- what the dropdown says ----------------
    function plural(n, one, many) {
        return n + " " + (n === 1 ? one : many)
    }

    // "2026-11-12" -> "12 Nov 2026"
    function shortDate(iso) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "")
        if (!m) return iso || ""
        return Qt.formatDate(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])), "d MMM yyyy")
    }

    readonly property string intervalText: {
        const m = root.checkIntervalMinutes
        if (m % 60 === 0) return m === 60 ? "hour" : (m / 60) + " hours"
        return m === 1 ? "minute" : m + " minutes"
    }

    readonly property string headline: {
        if (root.totalUpdates > 0)
            return root.plural(root.totalUpdates, "update", "updates") + " ready to install"
        if (root.checking && !root.lastChecked) return "Looking for updates..."
        return root.checkedEverything ? "Everything is up to date" : "No updates found"
    }

    readonly property string checkedLine: {
        const every = "checks every " + root.intervalText
        if (root.checking) return "Checking now · " + every
        if (!root.lastChecked) return "Not checked yet · " + every
        return "Last checked at " + Qt.formatTime(root.lastChecked, "hh:mm") + " · " + every
    }

    // Nothing's known yet: the very first check is still going.
    readonly property bool firstCheck: root.checking && !root.lastChecked

    // The sections of the list: one per command that updates them.
    readonly property var sections: {
        const out = []
        const packages = root.repoUpdates.concat(root.aurUpdates)
        const waiting = root.firstCheck
        const notes = []
        if (root.repoCheck === "missing")
            notes.push("Updates from the Arch repositories can't be seen: install pacman-contrib, which provides checkupdates.")
        else if (root.repoCheck === "failed")
            notes.push("Couldn't reach the Arch repositories just now - maybe you're offline.")
        if (root.aurCheck === "missing")
            notes.push("yay isn't installed, so AUR packages aren't checked.")
        const packagesKnown = root.repoCheck === "ok"
        out.push({
            title: "System packages",
            about: root.hasYay ? "From the Arch repositories and the AUR, updated together with yay."
                               : "From the Arch repositories, updated with pacman.",
            rows: packages,
            status: packages.length > 0 ? root.plural(packages.length, "update", "updates")
                  : waiting ? "Checking..." : packagesKnown ? "Up to date" : "Couldn't check",
            note: waiting ? "" : notes.join(" "),
            step: "packages",
            canRun: packages.length > 0 || (!waiting && !packagesKnown)
        })
        if (root.hasFlatpak) {
            const flatpakKnown = root.flatpakCheck === "ok"
            out.push({
                title: "Flatpak apps",
                about: "Apps installed with Flatpak.",
                rows: root.flatpakUpdates,
                status: root.flatpakUpdates.length > 0 ? root.plural(root.flatpakUpdates.length, "update", "updates")
                      : waiting ? "Checking..." : flatpakKnown ? "Up to date" : "Couldn't check",
                note: (waiting || flatpakKnown) ? "" : "Couldn't check Flatpak just now - maybe you're offline.",
                step: "flatpak",
                canRun: root.flatpakUpdates.length > 0 || (!waiting && !flatpakKnown)
            })
        }
        return out
    }

    // What the dropdown's purpura section says.
    readonly property string purpuraStatus: {
        const p = root.purpura
        if (!root.followPurpura) return "Not checked"
        if (!p) return root.purpuraChecking ? "Checking..." : ""
        if (p.state !== "ok") return "Can't check"
        return p.behind > 0 ? "Update available" : "Up to date"
    }

    // The newest change, when there's one to install.
    readonly property string purpuraChanges: {
        const p = root.purpura
        if (!root.purpuraUpdateAvailable) return ""
        const what = root.plural(p.behind, "new change", "new changes")
        return p.latestSubject ? what + ", the newest: “" + p.latestSubject + "”" : what
    }

    readonly property string purpuraVersions: {
        const p = root.purpura
        if (!p || p.state !== "ok") return ""
        // Without a record of what's installed, it's the checkout's own.
        const installed = (p.installedKnown ? "Installed: " : "Your checkout: ")
            + root.shortDate(p.installedDate) + " (" + p.installedShort + ")"
        if (p.behind > 0) return installed + "\nNewest: " + root.shortDate(p.latestDate) + " (" + p.latestShort + ")"
        return installed
    }

    readonly property string purpuraNote: {
        const p = root.purpura
        if (!p) return ""
        switch (p.state) {
        case "ok":
            break
        case "no-checkout":
            return "Run ./purpura.sh --install from your checkout once, so the updater knows where purpura came from."
        case "not-git":
            return root.homePath(p.checkout) + " isn't a git checkout, so there's nothing to update it from."
        case "no-upstream":
            return root.homePath(p.checkout) + " isn't tracking a remote branch to update from."
        default:
            return "The check itself failed."
        }
        const notes = []
        if (p.fetchFailed) notes.push("Couldn't reach " + p.upstream + ", so this is as of the last time it could.")
        if (!p.installedKnown) notes.push("Which version is installed isn't recorded yet - updating once records it.")
        if (p.localCommits > 0) {
            notes.push("Your checkout has " + p.localCommits + " commit" + (p.localCommits === 1 ? "" : "s")
                + " of its own, so updating it takes a git pull by hand.")
        } else if (p.dirty) {
            notes.push("Your checkout has uncommitted changes, which can get in the way of updating it.")
        }
        return notes.join(" ")
    }

    // interval recomputes live off checkIntervalMinutes (a plain
    // property read inside the binding), so editing the Updater settings
    // category's own input box reschedules this immediately rather than
    // waiting for quickshell to restart.
    Timer {
        id: checkTimer
        interval: root.checkIntervalMinutes * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.checkAll()
    }

    // "pkgname oldver -> newver" line format, shared by checkupdates
    // (official repos) and `yay -Qua` (AUR) below.
    function parseVersionLines(text) {
        const out = []
        const lines = text.split("\n")
        for (const line of lines) {
            const m = line.trim().match(/^(\S+)\s+(\S+)\s*->\s*(\S+)/)
            if (m) out.push({ name: m[1], oldVersion: m[2], newVersion: m[3] })
        }
        return out
    }

    // A check run through bash, which exits 127 when `tool` isn't installed.
    function checkCommand(tool, command) {
        return ["bash", "-c", "command -v " + tool + " >/dev/null 2>&1 || exit 127; " + command]
    }

    // checkupdates (pacman-contrib), not `pacman -Qu`/`yay -Qu` - syncs a
    // throwaway, user-writable copy of the package database instead of
    // the real one, so this can run unattended on a timer with no root/
    // sudo prompt at all. Exits 0 with updates, 2 with none, 1 when it
    // couldn't check. Only gives name/oldver/newver - repoNameProcess below
    // supplies the actual repo (core/extra/multilib/...) each package
    // belongs to, matched by name in rebuildRepoUpdates().
    property var _repoPending: []
    property var _repoNameByPackage: ({})

    function rebuildRepoUpdates() {
        const out = []
        for (const p of root._repoPending) {
            out.push({
                category: root._repoNameByPackage[p.name] || "repo",
                name: p.name,
                oldVersion: p.oldVersion,
                newVersion: p.newVersion
            })
        }
        root.repoUpdates = out
    }

    Process {
        id: repoCheckProcess
        command: root.checkCommand("checkupdates", "checkupdates")
        stdout: StdioCollector {
            onStreamFinished: {
                root._repoPending = root.parseVersionLines(text)
                root.rebuildRepoUpdates()
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.repoCheck = exitCode === 127 ? "missing" : exitCode === 1 ? "failed" : "ok"
        }
    }

    // `pacman -Sl` - lists every package in every configured repo as
    // "repo name version [installed]", one line each. Local-only (no
    // network), cheap enough to re-run every check cycle alongside
    // checkupdates. Builds the name -> repo map rebuildRepoUpdates()
    // above reads; a package with no entry here (shouldn't normally
    // happen for anything checkupdates itself reported) just falls back
    // to the plain "repo" label instead of guessing wrong.
    Process {
        id: repoNameProcess
        command: ["pacman", "-Sl"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                for (const rawLine of text.split("\n")) {
                    const line = rawLine.trim()
                    if (line.length === 0) continue
                    const parts = line.split(/\s+/)
                    if (parts.length < 2) continue
                    map[parts[1]] = parts[0]
                }
                root._repoNameByPackage = map
                root.rebuildRepoUpdates()
            }
        }
    }

    // yay -Qua: AUR-only (the trailing "a"), never touches/needs a
    // synced pacman db the way the repo half does - it queries AUR's own
    // RPC API live per package, so no root/sudo and no separate sync
    // step either. AUR packages were never in any configured repo at
    // all, so these are tagged "aur" directly rather than going through
    // repoNameProcess's own map. It exits 1 with nothing to list, which
    // isn't a failure.
    Process {
        id: aurCheckProcess
        command: root.checkCommand("yay", "yay -Qua")
        stdout: StdioCollector {
            onStreamFinished: {
                root.aurUpdates = root.parseVersionLines(text).map(u => Object.assign({ category: "aur" }, u))
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.aurCheck = exitCode === 127 ? "missing" : "ok"
        }
    }

    // flatpak remote-ls --updates - a genuine LISTING subcommand (unlike
    // `flatpak update`, which actually applies updates and isn't safe to
    // shell out to unattended on a timer even with --assumeno, since
    // non-interactive confirmation behavior isn't something to gamble on
    // in the background). --columns requests tab-separated, script-
    // friendly fields - untested live (no flatpak install to check the
    // exact column names against), so if this comes back empty despite
    // real pending updates, the column list here is the first thing to
    // check. Only gives the pending/new version - flatpakInstalledProcess
    // below supplies the currently-installed one, matched by
    // application ID in rebuildFlatpakUpdates().
    property var _flatpakPending: []
    property var _flatpakInstalled: ({})

    function rebuildFlatpakUpdates() {
        const out = []
        for (const p of root._flatpakPending) {
            out.push({
                category: "flatpak",
                name: p.name,
                oldVersion: root._flatpakInstalled[p.appId] || "",
                newVersion: p.newVersion
            })
        }
        root.flatpakUpdates = out
    }

    Process {
        id: flatpakUpdatesProcess
        command: root.checkCommand("flatpak", "flatpak remote-ls --updates --columns=application,version,name")
        stdout: StdioCollector {
            onStreamFinished: {
                const pending = []
                for (const rawLine of text.split("\n")) {
                    const line = rawLine.trim()
                    if (line.length === 0) continue
                    const fields = line.split("\t")
                    if (fields.length < 3) continue
                    pending.push({ appId: fields[0], newVersion: fields[1], name: fields[2] || fields[0] })
                }
                root._flatpakPending = pending
                root.rebuildFlatpakUpdates()
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.flatpakCheck = exitCode === 127 ? "missing" : exitCode !== 0 ? "failed" : "ok"
        }
    }

    Process {
        id: flatpakInstalledProcess
        command: root.checkCommand("flatpak", "flatpak list --columns=application,version")
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                for (const rawLine of text.split("\n")) {
                    const line = rawLine.trim()
                    if (line.length === 0) continue
                    const fields = line.split("\t")
                    if (fields.length < 2) continue
                    map[fields[0]] = fields[1]
                }
                root._flatpakInstalled = map
                root.rebuildFlatpakUpdates()
            }
        }
    }

    // ---------------- right-click: run the actual upgrade in a terminal ----------------
    // Interactive, not headless - yay/flatpak/fwupdmgr all need to
    // prompt for confirmation (and yay/fwupdmgr for sudo), so this opens
    // a real kitty window. With "Follow Purpura versioning" on, purpura
    // updates itself just before the firmware (purpura-update.sh apply);
    // its failing never holds the firmware update back. Flatpak and fwupd
    // are left out where they aren't installed, so the rest still runs.
    //
    // Started detached rather than as a Process: updating purpura rewrites
    // this shell's own config, and Quickshell kills whatever a Process is
    // still running when the reload that sets off destroys it - which
    // would take the terminal down mid-update. So instead of this waiting
    // for the window to close, the window asks for a recheck itself once
    // the updates are done (`qs ipc call updater check`, see the
    // IpcHandler above), before its "press any key" prompt.
    function runUpdate() {
        const steps = [root.updateSteps.packages]
        if (root.hasFlatpak) steps.push(root.updateSteps.flatpak)
        if (root.followPurpura) steps.push("{ " + root.updateSteps.purpura + " || true; }")
        if (root.hasFwupd) steps.push(root.updateSteps.firmware)
        root.runInTerminal(steps)
    }

    // Each step on its own - the dropdown's buttons. Purpura's runs
    // whether "Follow Purpura versioning" is on or not: it's asked for.
    // Without yay, the system packages are updated with pacman.
    readonly property var updateSteps: ({
        packages: root.hasYay ? "yay" : "sudo pacman -Syu",
        flatpak: "flatpak update",
        firmware: "fwupdmgr update",
        purpura: 'bash "$1/helpers/purpura-update.sh" apply'
    })

    function runStep(name) {
        if (root.updateSteps[name]) root.runInTerminal([root.updateSteps[name]])
    }

    // `steps` one after the other, stopping at the first that fails, in a
    // kitty window that asks for a recheck once they're done. The dropdown
    // closes, out of the terminal's way.
    function runInTerminal(steps) {
        root.dropdownOpen = false
        const script = steps.join(" && ")
            + "; echo; qs ipc call updater check >/dev/null 2>&1"
            + "; echo 'Press any key to close this window'; read -n 1 -s"
        Quickshell.execDetached(["kitty", "bash", "-c", script, "purpura-updater", Quickshell.shellDir])
    }

    // Whether the currently-focused window is genuinely fullscreen - see
    // Notification.qml's own identical block for the full reasoning
    // (same detection). A genuinely separate copy, not a shared
    // property, for the same reason Notification.qml's own copy is
    // separate from Dashboard.qml/Bar.qml's - each top-level dropdown
    // needs this independently of the others.
    property bool activeIsFullscreen: false
    property string fullscreenMonitorName: ""
    // Neither PanelWindow below is given an explicit `screen:` (unlike
    // Dashboard/Bar/etc.'s per-monitor Variants), so - same as
    // Notification.qml's own fallback - this only ever compares against
    // Quickshell.screens[0], which is where an unscreened PanelWindow
    // ends up here too.
    readonly property bool ignoresBarPadding: root.activeIsFullscreen && Quickshell.screens.length > 0 && root.fullscreenMonitorName === Quickshell.screens[0].name

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Not purpura.lua's drag events (see Bar.qml's).
            if (event.name === "custom") return
            fullscreenCheckProcess.running = true
        }
    }

    Process {
        id: fullscreenCheckProcess
        command: ["hyprctl", "activewindow", "-j"]

        stdout: StdioCollector {
            id: fullscreenCheckCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(fullscreenCheckCollector.text)
                } catch (e) {
                    parsed = null
                }
                const mon = Hyprland.activeToplevel && Hyprland.activeToplevel.monitor
                root.activeIsFullscreen = !!(parsed && parsed.fullscreenClient === 2 && mon)
                root.fullscreenMonitorName = (root.activeIsFullscreen && mon) ? mon.name : ""
            }
        }
    }

    PanelWindow {
        id: dropdownWindow

        // The shell-wide per-screen scale (see Config.uiScale) of
        // whichever screen the compositor put this window on.
        readonly property real uiScale: Config.uiScale(dropdownWindow.screen, root.shellScale)
        readonly property real panelWidth: Config.scaled(440, dropdownWindow.uiScale)
        readonly property real pad: Config.scaled(14, dropdownWindow.uiScale)

        margins { top: Config.scaled(root.ignoresBarPadding ? 10 : 4, dropdownWindow.uiScale); right: root.edgeGaps ? root.edgeGaps.right : 10 }
        anchors { top: true; right: true }
        exclusiveZone: root.ignoresBarPadding ? -1 : 0
        visible: root.dropdownOpen

        // Content-derived, NOT bound to panelBox's currently-animating
        // height - see Notification.qml's own identical fix/comment:
        // binding the window itself to the live animation resizes the
        // actual Wayland surface every frame (a real compositor
        // round-trip), which is what made this feel sluggish and gave it
        // a wrong height mid-spread.
        implicitWidth: dropdownWindow.panelWidth
        implicitHeight: Math.max(centerCol.implicitHeight + 2 * dropdownWindow.pad, 1)

        color: "transparent"

        Rectangle {
            id: panelBox
            visible: root.dropdownOpen
            color: "transparent"
            width: centerCol.width
            // The column's own padding above (its anchors.margins) and the
            // same again below it.
            height: centerCol.implicitHeight + 2 * dropdownWindow.pad

            // Grows from the right edge, same as Notification.qml's own
            // panelBox/Tray.qml's menu.
            anchors.right: parent.right

            Rectangle {
                id: mainRect
                anchors.fill: parent
                color: Config.fillcolor
                border.width: Config.scaled(2, dropdownWindow.uiScale)
                border.color: Config.fgcolor
                clip: true

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            autoCloseTimer.stop()
                        } else {
                            autoCloseTimer.restart()
                        }
                    }
                }

                ColumnLayout {
                    id: centerCol

                    width: dropdownWindow.panelWidth - 2 * dropdownWindow.pad

                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: dropdownWindow.pad
                    }
                    spacing: Config.scaled(12, dropdownWindow.uiScale)

                    // ---------------- at a glance ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(10, dropdownWindow.uiScale)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(3, dropdownWindow.uiScale)

                            Text {
                                Layout.fillWidth: true
                                text: root.headline
                                color: root.totalUpdates > 0 ? Config.fgcolorlight : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(16, dropdownWindow.uiScale)
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.checkedLine
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                elide: Text.ElideRight
                            }
                        }

                        ActionButton {
                            Layout.alignment: Qt.AlignTop
                            // Wide enough for either label, so it doesn't jump.
                            Layout.preferredWidth: Math.max(implicitWidth, Config.scaled(112, dropdownWindow.uiScale))
                            uiScale: dropdownWindow.uiScale
                            text: root.checking ? "Checking..." : "Check now"
                            enabled: !root.checking
                            onClicked: root.checkAll()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.scaled(1, dropdownWindow.uiScale)
                        color: Config.fgcolordark
                    }

                    // ---------------- the packages, by kind ----------------
                    // Scrolls once it's long; everything below stays in view.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(sectionsColumn.implicitHeight, Config.scaled(320, dropdownWindow.uiScale))

                        Flickable {
                            id: sectionsView
                            anchors.fill: parent
                            contentHeight: sectionsColumn.implicitHeight
                            contentWidth: width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            ColumnLayout {
                                id: sectionsColumn
                                // Room for the scroll bar while there is one.
                                width: sectionsView.width - (sectionsView.interactive ? Config.scaled(12, dropdownWindow.uiScale) : 0)
                                spacing: Config.scaled(16, dropdownWindow.uiScale)

                                Repeater {
                                    model: root.sections

                                    ColumnLayout {
                                        id: section

                                        required property var modelData

                                        Layout.fillWidth: true
                                        spacing: Config.scaled(4, dropdownWindow.uiScale)

                                        // Its name, how it stands, and its own Update button.
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Config.scaled(10, dropdownWindow.uiScale)

                                            Text {
                                                text: section.modelData.title
                                                color: Config.fgcolor
                                                font.family: Config.fontfamily
                                                font.pixelSize: Config.scaled(14, dropdownWindow.uiScale)
                                                font.bold: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: section.modelData.status
                                                color: section.modelData.rows.length > 0 ? Config.fgcolorlight : Config.fgcolorhint
                                                font.family: Config.fontfamily
                                                font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                                                font.bold: section.modelData.rows.length > 0
                                                elide: Text.ElideRight
                                            }

                                            ActionButton {
                                                visible: section.modelData.canRun
                                                uiScale: dropdownWindow.uiScale
                                                implicitHeight: Config.scaled(28, dropdownWindow.uiScale)
                                                text: "Update"
                                                onClicked: root.runStep(section.modelData.step)
                                            }
                                        }

                                        // What it is, in a few words.
                                        Text {
                                            Layout.fillWidth: true
                                            text: section.modelData.about
                                            color: Config.fgcolorhint
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                            wrapMode: Text.WordWrap
                                        }

                                        // Why it might not be showing everything.
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                            text: section.modelData.note
                                            color: Config.fgcolorred
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                            wrapMode: Text.WordWrap
                                        }

                                        // The updates: name, where it's from, old -> new.
                                        Repeater {
                                            model: section.modelData.rows

                                            RowLayout {
                                                id: updateRow

                                                required property var modelData

                                                Layout.fillWidth: true
                                                Layout.topMargin: Config.scaled(2, dropdownWindow.uiScale)
                                                spacing: Config.scaled(8, dropdownWindow.uiScale)

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: updateRow.modelData.name
                                                    color: Config.fgcolor
                                                    font.family: Config.fontfamily
                                                    font.pixelSize: Config.scaled(13, dropdownWindow.uiScale)
                                                    elide: Text.ElideRight
                                                }

                                                // The repository it's from (core, extra, AUR...),
                                                // where that's worth saying.
                                                Text {
                                                    visible: updateRow.modelData.category !== "flatpak"
                                                    text: updateRow.modelData.category === "aur" ? "AUR" : updateRow.modelData.category
                                                    color: Config.fgcolorhint
                                                    font.family: Config.fontfamily
                                                    font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                                }

                                                Text {
                                                    Layout.maximumWidth: sectionsView.width * 0.5
                                                    text: (updateRow.modelData.oldVersion ? updateRow.modelData.oldVersion + "  →  " : "→  ")
                                                        + updateRow.modelData.newVersion
                                                    color: Config.fgcolorlight
                                                    font.family: Config.fontfamily
                                                    font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                                                    horizontalAlignment: Text.AlignRight
                                                    elide: Text.ElideLeft
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // How far down the list is, while it's longer than the
                        // room it has.
                        Rectangle {
                            anchors.right: parent.right
                            y: sectionsView.visibleArea.yPosition * sectionsView.height
                            width: Config.scaled(4, dropdownWindow.uiScale)
                            height: sectionsView.visibleArea.heightRatio * sectionsView.height
                            visible: sectionsView.interactive
                            color: Config.fgcolor
                        }
                    }

                    // ---------------- purpura ----------------
                    // Below the list rather than in it, so it stays in view
                    // however far the list scrolls.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.scaled(1, dropdownWindow.uiScale)
                        color: Config.fgcolordark
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(4, dropdownWindow.uiScale)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(10, dropdownWindow.uiScale)

                            Text {
                                text: "Purpura"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(14, dropdownWindow.uiScale)
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.purpuraStatus
                                color: root.purpuraUpdateAvailable ? Config.fgcolorlight : Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                                font.bold: root.purpuraUpdateAvailable
                                elide: Text.ElideRight
                            }

                            // Unfollowed, it's not known whether there's
                            // anything new - updating finds out.
                            ActionButton {
                                visible: root.purpuraUpdateAvailable || !root.followPurpura
                                uiScale: dropdownWindow.uiScale
                                implicitHeight: Config.scaled(28, dropdownWindow.uiScale)
                                text: "Update"
                                onClicked: root.runStep("purpura")
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.followPurpura
                                ? "These dotfiles: the shell, its themes and its settings."
                                : "These dotfiles. To be told about new versions, turn on “Follow Purpura versioning” in Settings > General > Updater."
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.purpuraChanges
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.purpuraVersions
                            color: Config.fgcolorlight
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.purpuraNote
                            wrapMode: Text.WordWrap
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                        }
                    }

                    // ---------------- firmware ----------------
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.scaled(1, dropdownWindow.uiScale)
                        visible: root.hasFwupd
                        color: Config.fgcolordark
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.hasFwupd
                        spacing: Config.scaled(10, dropdownWindow.uiScale)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(2, dropdownWindow.uiScale)

                            Text {
                                text: "Firmware"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(14, dropdownWindow.uiScale)
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Your devices' own software, through fwupd. Not checked automatically."
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                wrapMode: Text.WordWrap
                            }
                        }

                        ActionButton {
                            Layout.alignment: Qt.AlignTop
                            uiScale: dropdownWindow.uiScale
                            implicitHeight: Config.scaled(28, dropdownWindow.uiScale)
                            text: "Check & update"
                            onClicked: root.runStep("firmware")
                        }
                    }

                    // ---------------- everything at once ----------------
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.scaled(1, dropdownWindow.uiScale)
                        color: Config.fgcolordark
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        uiScale: dropdownWindow.uiScale
                        implicitHeight: Config.scaled(36, dropdownWindow.uiScale)
                        lit: root.totalUpdates > 0
                        text: root.totalUpdates === 1 ? "Install 1 update"
                            : root.totalUpdates > 1 ? "Install all " + root.totalUpdates + " updates"
                            : "Run a full update anyway"
                        onClicked: root.runUpdate()
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Updates open in a terminal window, where you confirm them and enter your password. "
                            + "“Install all” goes through every kind above in turn - so does right-clicking the update button in the bar."
                        color: Config.fgcolorhint
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                        wrapMode: Text.WordWrap
                    }
                }
            }

            states: [

                State {
                    name: "spread"

                    PropertyChanges {
                        target: panelBox

                        width: dropdownWindow.panelWidth
                        height: Config.scaled(2, dropdownWindow.uiScale)
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: panelBox

                        width: dropdownWindow.panelWidth
                        height: centerCol.implicitHeight + 2 * dropdownWindow.pad
                    }
                }

            ]

            transitions: [

                Transition {

                    NumberAnimation {

                        properties: "width,height"

                        duration: 300

                        easing.type: Easing.OutCubic

                    }

                }

            ]

            onVisibleChanged: {
                if (visible) {
                    panelBox.width = 0
                    panelBox.height = Config.scaled(4, dropdownWindow.uiScale)

                    panelBox.state = "spread"
                    dropdownOpenTimer.start()
                }
            }

            Timer {
                id: dropdownOpenTimer

                // Must match the transition's duration above, so phase 1
                // (width) fully finishes before phase 2 (height) starts.
                interval: 300
                repeat: false

                onTriggered: {
                    panelBox.state = "open"
                }
            }
        }
    }
}

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "../../Config.js" as Config

// Update checker + dropdown, modeled on apdatifier (github.com/exequtic/
// apdatifier): periodically checks pacman/AUR and flatpak for pending
// updates, surfaces a highlighted bar button (Bar.qml) when any are
// found, and a scrollable dropdown listing them - name, source (the
// actual repo - core/extra/multilib/... - for an official package, "aur"
// for an AUR one, "flatpak" for a flatpak), old -> new version. With
// "Follow Purpura versioning" on, purpura itself is checked too: a
// notification once per new version, its state in a fixed section under
// the list, and its update run just before the firmware. Mutually
// exclusive with Notification.qml's own history panel (each holds a
// reference to the other and closes it
// when it itself opens, same convention Dashboard.qml/SettingsScreen.qml
// already use for each other), and auto-closes the same way (5s after
// the mouse last left it). Structurally mirrors Notification.qml's own
// history panel throughout - same box-grow-open animation, same
// fullscreen-aware margin/exclusiveZone handling - since that's the
// closest existing analog to "a small bar-button dropdown that behaves
// like the notification one."
Scope {
    id: root

    // Settings > Shell's global UI Scale (UiScale.qml), from shell.qml -
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
        if (root.followPurpura) root.checkPurpura()
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

    // What the dropdown's purpura section says.
    readonly property string purpuraStatus: {
        const p = root.purpura
        if (!p) return root.purpuraChecking ? "checking..." : ""
        if (p.state !== "ok") return "can't check"
        return p.behind > 0 ? "update available" : "up to date"
    }

    readonly property string purpuraVersions: {
        const p = root.purpura
        if (!p || p.state !== "ok") return ""
        if (p.behind > 0) {
            return p.installedShort + " -> " + p.latestShort + "  ·  " + p.behind + " new commit" + (p.behind === 1 ? "" : "s")
        }
        return p.installedShort + "  ·  " + p.installedDate
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

    // checkupdates (pacman-contrib), not `pacman -Qu`/`yay -Qu` - syncs a
    // throwaway, user-writable copy of the package database instead of
    // the real one, so this can run unattended on a timer with no root/
    // sudo prompt at all. Missing entirely (pacman-contrib not
    // installed) just yields empty output below, same "hide rather than
    // guess wrong" convention as solaar/ddcutil/sensors elsewhere in
    // this shell. Only gives name/oldver/newver - repoNameProcess below
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
        command: ["checkupdates"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._repoPending = root.parseVersionLines(text)
                root.rebuildRepoUpdates()
            }
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
    // repoNameProcess's own map.
    Process {
        id: aurCheckProcess
        command: ["yay", "-Qua"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.aurUpdates = root.parseVersionLines(text).map(u => Object.assign({ category: "aur" }, u))
            }
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
        command: ["flatpak", "remote-ls", "--updates", "--columns=application,version,name"]
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
    }

    Process {
        id: flatpakInstalledProcess
        command: ["flatpak", "list", "--columns=application,version"]
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
    // its failing never holds the firmware update back.
    //
    // Started detached rather than as a Process: updating purpura rewrites
    // this shell's own config, and Quickshell kills whatever a Process is
    // still running when the reload that sets off destroys it - which
    // would take the terminal down mid-update. So instead of this waiting
    // for the window to close, the window asks for a recheck itself once
    // the updates are done (`qs ipc call updater check`, see the
    // IpcHandler above), before its "press any key" prompt.
    function runUpdate() {
        const steps = ["yay", "flatpak update"]
        if (root.followPurpura) steps.push('{ bash "$1/helpers/purpura-update.sh" apply || true; }')
        steps.push("fwupdmgr update")
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
        implicitWidth: Config.scaled(400, dropdownWindow.uiScale)
        implicitHeight: Math.max(centerCol.implicitHeight + Config.scaled(20, dropdownWindow.uiScale), 1)

        color: "transparent"

        Rectangle {
            id: panelBox
            visible: root.dropdownOpen
            color: "transparent"
            width: centerCol.width
            // +20 = the 10px top margin centerCol's own anchors.margins
            // already gives it (an offset on its position, not something
            // that eats into this box's own height budget) PLUS a
            // matching 10px gap below it - the exact same "+20 = 10 top +
            // 10 bottom" Clipboard.qml's own panelBox comment explains
            // for its box. A bare +10 here left nothing left over for the
            // bottom gap at all (10 entirely consumed accounting for the
            // top offset), clipping the empty-state label flush against
            // the border.
            height: centerCol.implicitHeight + Config.scaled(20, dropdownWindow.uiScale)

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

                    width: Config.scaled(400, dropdownWindow.uiScale) - 2 * Config.scaled(10, dropdownWindow.uiScale)

                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: Config.scaled(10, dropdownWindow.uiScale)
                    }
                    spacing: Config.scaled(10, dropdownWindow.uiScale)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Updates"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, dropdownWindow.uiScale)
                            font.bold: true
                        }

                        Text {
                            text: root.totalUpdates + " available"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                        }
                    }

                    // With purpura's own section below, this one only speaks
                    // for the packages.
                    Text {
                        Layout.fillWidth: true
                        visible: root.updateCount === 0
                        text: root.followPurpura ? "Packages are up to date" : "Everything is up to date"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        id: updatesList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, Config.scaled(420, dropdownWindow.uiScale))
                        visible: root.updateCount > 0
                        clip: true
                        spacing: Config.scaled(8, dropdownWindow.uiScale)
                        model: root.allUpdates
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: updatesList.width
                            height: Config.scaled(50, dropdownWindow.uiScale)
                            color: Config.fillcolor
                            border.width: Config.scaled(2, dropdownWindow.uiScale)
                            border.color: Config.fgcolor

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Config.scaled(8, dropdownWindow.uiScale)
                                spacing: Config.scaled(8, dropdownWindow.uiScale)

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Config.scaled(2, dropdownWindow.uiScale)

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, dropdownWindow.uiScale)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Config.scaled(6, dropdownWindow.uiScale)

                                        Text {
                                            text: modelData.category
                                            color: Config.fgcolor
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData.oldVersion.length > 0 ? modelData.oldVersion + " -> " : "-> ") + modelData.newVersion
                                            color: Config.fgcolorlight
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------------- purpura ----------------
                    // Below the list rather than in it, so it stays in view
                    // however far the list scrolls.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.followPurpura
                        spacing: Config.scaled(4, dropdownWindow.uiScale)

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Config.scaled(2, dropdownWindow.uiScale)
                            Layout.bottomMargin: Config.scaled(4, dropdownWindow.uiScale)
                            color: Config.fgcolor
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: "Purpura"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, dropdownWindow.uiScale)
                                font.bold: true
                            }

                            Text {
                                text: root.purpuraStatus
                                color: root.purpuraUpdateAvailable ? Config.fgcolorlight : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(12, dropdownWindow.uiScale)
                                font.bold: root.purpuraUpdateAvailable
                            }
                        }

                        // installed -> newest, or just what's installed
                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.purpuraVersions
                            color: Config.fgcolorlight
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                            elide: Text.ElideRight
                        }

                        // The newest commit's own description.
                        Text {
                            Layout.fillWidth: true
                            visible: root.purpuraUpdateAvailable
                            text: root.purpura ? (root.purpura.latestSubject || "") : ""
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.purpuraNote
                            wrapMode: Text.WordWrap
                            color: Config.fgcolordark
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, dropdownWindow.uiScale)
                        }
                    }

                    Item { height: Config.scaled(2, dropdownWindow.uiScale) }
                }
            }

            states: [

                State {
                    name: "spread"

                    PropertyChanges {
                        target: panelBox

                        width: Config.scaled(400, dropdownWindow.uiScale)
                        height: Config.scaled(2, dropdownWindow.uiScale)
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: panelBox

                        width: Config.scaled(400, dropdownWindow.uiScale)
                        height: centerCol.implicitHeight + Config.scaled(20, dropdownWindow.uiScale)
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

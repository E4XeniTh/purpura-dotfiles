import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "../Config.js" as Config

// Update checker + dropdown, modeled on apdatifier (github.com/exequtic/
// apdatifier): periodically checks pacman/AUR and flatpak for pending
// updates, surfaces a highlighted bar button (Bar.qml) when any are
// found, and a scrollable dropdown listing them - name, source (the
// actual repo - core/extra/multilib/... - for an official package, "aur"
// for an AUR one, "flatpak" for a flatpak), old -> new version. Mutually
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

    // ---------------- update data ----------------
    property var repoUpdates: []
    property var aurUpdates: []
    property var flatpakUpdates: []

    readonly property var allUpdates: root.repoUpdates.concat(root.aurUpdates).concat(root.flatpakUpdates)
    readonly property int updateCount: root.allUpdates.length

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
    }

    Component.onCompleted: root.checkAll()

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
    // a real kitty window rather than running detached the way the
    // read-only check Processes above do. The trailing `; echo; echo
    // ...; read` always runs regardless of whether the `&&` chain ahead
    // of it succeeded or stopped partway through (a `;`, not another
    // `&&`) - leaves the window open with its output still on screen
    // instead of it vanishing the instant the commands finish, and gives
    // onExited below something to actually wait on.
    Process {
        id: runUpdateProcess
        command: ["kitty", "sh", "-c", "yay && flatpak update && fwupdmgr update; echo; echo 'Press any key to close this window'; read -n 1 -s"]

        // Rechecks the moment the kitty window actually closes, not just
        // when the update commands themselves finish - the "press any
        // key" prompt above deliberately keeps the window (and this
        // Process) alive past that point so the user can review the
        // output first - so the dropdown/button highlight reflect
        // reality again right away instead of waiting for the next
        // scheduled checkTimer tick.
        onExited: (exitCode, exitStatus) => root.checkAll()
    }

    function runUpdate() {
        runUpdateProcess.running = false
        runUpdateProcess.running = true
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
        margins { top: root.ignoresBarPadding ? 10 : 4; right: 10 }
        anchors { top: true; right: true }
        exclusiveZone: root.ignoresBarPadding ? -1 : 0
        visible: root.dropdownOpen

        // Content-derived, NOT bound to panelBox's currently-animating
        // height - see Notification.qml's own identical fix/comment:
        // binding the window itself to the live animation resizes the
        // actual Wayland surface every frame (a real compositor
        // round-trip), which is what made this feel sluggish and gave it
        // a wrong height mid-spread.
        implicitWidth: 400
        implicitHeight: Math.max(centerCol.implicitHeight + 10, 1)

        color: "transparent"

        Rectangle {
            id: panelBox
            visible: root.dropdownOpen
            color: "transparent"
            width: centerCol.width
            // +10 bottom padding - matches centerCol's own top margin
            // (anchors.margins below) and its 10px inter-child spacing,
            // the same uniform 10/10/10 Clipboard.qml's own panelBox
            // already uses throughout (top margin, internal spacing,
            // bottom margin all equal) - that plain consistency, not any
            // extra breathing room, is what made its label read as
            // well-placed.
            height: centerCol.implicitHeight + 10

            // Grows from the right edge, same as Notification.qml's own
            // panelBox/Tray.qml's menu.
            anchors.right: parent.right

            Rectangle {
                id: mainRect
                anchors.fill: parent
                color: Config.fillcolor
                border.width: 2
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

                    width: 380

                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: 10
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Updates"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Text {
                            text: root.updateCount + " available"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: 12
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.updateCount === 0
                        text: "Everything is up to date"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        id: updatesList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 420)
                        visible: root.updateCount > 0
                        clip: true
                        spacing: 8
                        model: root.allUpdates
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: updatesList.width
                            height: 50
                            color: Config.fillcolor
                            border.width: 2
                            border.color: Config.fgcolor

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: modelData.category
                                            color: Config.fgcolor
                                            font.family: Config.fontfamily
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData.oldVersion.length > 0 ? modelData.oldVersion + " -> " : "-> ") + modelData.newVersion
                                            color: Config.fgcolorlight
                                            font.family: Config.fontfamily
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            states: [

                State {
                    name: "spread"

                    PropertyChanges {
                        target: panelBox

                        width: 400
                        height: 2
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: panelBox

                        width: 400
                        height: centerCol.implicitHeight + 10
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
                    panelBox.height = 4

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

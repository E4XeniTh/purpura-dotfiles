import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import "../Config.js" as Config

// One rectangle per current Hyprland workspace, sorted by owning
// monitor position first and workspace number second - meant to sit
// directly to the left of Bar.qml's clock (the dashboard-open button),
// which sets this Row's own height from the outside. Each box is
// width-only aspect-ratio scaled to its own monitor
// (HyprlandMonitor.width/height) and draws a live miniature grid of
// that workspace's actual windows underneath a faint workspace-number
// label.
Row {
    id: root

    spacing: 6

    // Every connected screen, left-to-right by x - ties (side-by-side
    // monitors stacked vertically instead) broken by whichever is
    // closest to y = 0, so a monitor placed above the reference point
    // sorts before one placed further below it. Only used below to
    // rank which monitor each workspace belongs to.
    readonly property var sortedMonitors: Quickshell.screens.slice().sort((a, b) => {
        if (a.x !== b.x) return a.x - b.x
        return Math.abs(a.y) - Math.abs(b.y)
    })

    readonly property var sortedWorkspaces: {
        const monitorRank = {}
        root.sortedMonitors.forEach((s, i) => { monitorRank[s.name] = i })
        return Hyprland.workspaces.values.slice().sort((a, b) => {
            const rankA = (a.monitor && monitorRank[a.monitor.name] !== undefined) ? monitorRank[a.monitor.name] : 999
            const rankB = (b.monitor && monitorRank[b.monitor.name] !== undefined) ? monitorRank[b.monitor.name] : 999
            if (rankA !== rankB) return rankA - rankB
            return a.id - b.id
        })
    }

    // sortedWorkspaces with a "separator" marker spliced in wherever the
    // owning monitor changes between one entry and the next, so the Row
    // below can draw a small divider between each monitor's group of
    // workspace boxes instead of one continuous, ungrouped run of them.
    readonly property var rowEntries: {
        const list = []
        let lastMonitorName = null
        for (const ws of root.sortedWorkspaces) {
            const monName = ws.monitor ? ws.monitor.name : ""
            if (lastMonitorName !== null && monName !== lastMonitorName) {
                list.push({ kind: "separator" })
            }
            list.push({ kind: "workspace", ws: ws })
            lastMonitorName = monName
        }
        return list
    }

    // A toplevel's lastIpcObject (the only place its at/size/class live
    // - see WindowBox below) is only ever as fresh as the last
    // refreshToplevels() call, unlike title/activated/workspace which
    // update live - re-requested on every Hyprland event so the little
    // per-window rectangles track real opens/closes/moves/resizes
    // instead of a one-off snapshot from whenever quickshell started.
    Connections {
        target: Hyprland
        function onRawEvent(event) { Hyprland.refreshToplevels() }
    }
    Component.onCompleted: {
        Hyprland.refreshToplevels()
        root.loadScreensStore()
    }

    // Which workspace numbers (1-5) are actually pinned to each
    // monitor via Screen Settings - read straight from the same
    // monitors.json ScreenSettings.qml writes, rather than depending on
    // that panel being open/instantiated, so the number label below can
    // tell "a real pin" apart from whatever spare workspace number
    // Hyprland happened to assign a monitor with nothing pinned to it.
    property var screensStore: ({})

    function loadScreensStore() {
        screensStoreProcess.running = false
        screensStoreProcess.running = true
    }

    function isPinned(workspace) {
        if (!workspace.monitor) return false
        const stored = root.screensStore[workspace.monitor.name]
        return !!(stored && stored.workspaces && stored.workspaces.includes(workspace.id))
    }

    Process {
        id: screensStoreProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/monitors.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.screensStore = JSON.parse(text)
                } catch (e) {
                    root.screensStore = {}
                }
            }
        }
    }

    // Nothing pushes a change notification when monitors.json is
    // rewritten (only ScreenSettings.qml's own Apply button touches
    // it), so this just polls - same interval Network Settings uses
    // for its own ZeroTier/nmcli refresh.
    Timer {
        interval: 4000
        repeat: true
        running: true
        onTriggered: root.loadScreensStore()
    }

    Repeater {
        model: root.rowEntries

        Loader {
            id: entryLoader
            required property var modelData

            // Loader auto-sizes to whatever it loads by default - the
            // separator's own Rectangle is deliberately shorter than
            // the row (60%), so leaving the Loader at that same
            // shrunk height made "center within my own parent" a
            // no-op, and the whole thing just sat at Row's default
            // top-aligned position instead of actually centering in
            // the bar. Forcing every Loader (workspace or separator)
            // to the row's full height first is what makes that
            // centering below mean something.
            height: root.height

            sourceComponent: entryLoader.modelData.kind === "separator" ? separatorComponent : workspaceComponent
        }
    }

    Component {
        id: separatorComponent

        Rectangle {
            width: 2
            height: root.height * 0.6
            anchors.verticalCenter: parent.verticalCenter
            color: Config.fgcolordark
        }
    }

    Component {
        id: workspaceComponent

        Rectangle {
            id: wsBox

            // parent is entryLoader (Loader reparents its loaded item
            // directly) - .ws rather than .modelData itself since the
            // Repeater's own model entries are now { kind, ws } wrappers,
            // not bare workspace objects, to make room for the
            // separator markers spliced into rowEntries above.
            readonly property var modelData: wsBox.parent.modelData.ws

            readonly property var mon: wsBox.modelData.monitor

            // HyprlandMonitor.width/height are the raw/physical output
            // resolution (straight from hyprctl's own JSON), but a
            // window's at/size (and monitor.x/y) are in logical,
            // already-scale-divided coordinates - dividing a logical
            // window size by the unscaled monitor width/height made
            // every window rectangle too small by exactly a factor of
            // scale (e.g. half size at 200%/2x). These are the
            // logical/effective dimensions to actually match against.
            readonly property real monWidth: (wsBox.mon && wsBox.mon.scale > 0) ? wsBox.mon.width / wsBox.mon.scale : 0
            readonly property real monHeight: (wsBox.mon && wsBox.mon.scale > 0) ? wsBox.mon.height / wsBox.mon.scale : 0

            readonly property real aspect: (wsBox.mon && wsBox.mon.height > 0)
                ? (wsBox.mon.width / wsBox.mon.height)
                : (16 / 9)

            height: root.height
            width: wsBox.height * wsBox.aspect
            color: Config.fillcolor
            border.width: 2
            border.color: wsBox.modelData.active ? Config.fgcolor : Config.fgcolordark
            radius: 0
            // A window that's fullscreened, off-monitor mid-drag, or
            // just rounds slightly past its workspace's edge would
            // otherwise draw outside this box's own border - clipped
            // to keep every window rectangle strictly inside it.
            clip: true

            // One rectangle per window actually open on this
            // workspace, positioned/sized as a fraction of the owning
            // monitor's geometry (at/size are absolute layout
            // coordinates, same space as monitor.x/y/width/height) so
            // it lands in the same relative spot inside this miniature
            // box.
            Repeater {
                model: wsBox.modelData.toplevels.values

                Rectangle {
                    id: winBox
                    required property var modelData

                    readonly property var ipcData: winBox.modelData.lastIpcObject
                    readonly property var atArr: winBox.ipcData.at ?? [0, 0]
                    readonly property var sizeArr: winBox.ipcData.size ?? [0, 0]
                    readonly property string winClass: winBox.ipcData.class ?? ""

                    // Real per-app icon, the same way Tray.qml gets one
                    // - its Image binds straight to SystemTray's own
                    // already-resolved .icon rather than guessing an
                    // icon-theme name. There's no such direct icon on a
                    // Hyprland toplevel, but DesktopEntries.
                    // heuristicLookup() matches this window's WM class
                    // to its installed .desktop file and returns that
                    // entry's real icon name, which resolves correctly
                    // far more often than assuming the icon theme has
                    // an entry literally named after the raw class
                    // string (the fallback below, for whatever
                    // heuristicLookup can't match).
                    readonly property var desktopEntry: winBox.winClass.length > 0
                        ? DesktopEntries.heuristicLookup(winBox.winClass)
                        : null
                    readonly property string iconName: (winBox.desktopEntry && winBox.desktopEntry.icon.length > 0)
                        ? winBox.desktopEntry.icon
                        : winBox.winClass

                    x: wsBox.mon ? (winBox.atArr[0] - wsBox.mon.x) / wsBox.monWidth * wsBox.width : 0
                    y: wsBox.mon ? (winBox.atArr[1] - wsBox.mon.y) / wsBox.monHeight * wsBox.height : 0
                    width: (wsBox.mon && wsBox.monWidth > 0)
                        ? Math.max(1, winBox.sizeArr[0] / wsBox.monWidth * wsBox.width)
                        : 1
                    height: (wsBox.mon && wsBox.monHeight > 0)
                        ? Math.max(1, winBox.sizeArr[1] / wsBox.monHeight * wsBox.height)
                        : 1

                    color: "transparent"
                    border.width: 1
                    // Only lit up fgcolor when BOTH this window is the
                    // focused one ("activated") AND its workspace is the
                    // currently active one on its monitor - a focused
                    // window sitting on a workspace you've since
                    // switched away from should still read as dimmed,
                    // not call attention to itself.
                    border.color: (wsBox.modelData.active && winBox.modelData.activated)
                        ? Config.fgcolor
                        : Config.fgcolordark

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.max(4, Math.min(winBox.width, winBox.height) * 0.6)
                        // The plain single-arg iconPath() renders "a
                        // missing texture" image when the name doesn't
                        // resolve in the current icon theme (documented
                        // behavior, not a bug) rather than failing
                        // quietly - the two-arg fallback form loads a
                        // generic icon instead whenever the specific
                        // app/class name isn't a real theme icon, same
                        // fallback pattern BluetoothDeviceCard.qml uses.
                        source: winBox.iconName.length > 0
                            ? Quickshell.iconPath(winBox.iconName, "application-x-executable")
                            : Quickshell.iconPath("application-x-executable")
                    }
                }
            }

            // Faint workspace number, drawn above the window grid (z
            // higher than the Repeater's default stacking) so it stays
            // legible regardless of how many window/icon rectangles are
            // packed underneath it. Hidden entirely - not just dimmed -
            // for a workspace number past 5 or one that was never
            // actually pinned to this monitor through Screen Settings
            // (see isPinned()/screensStore above), e.g. the spare
            // number 6+ Hyprland assigns a monitor with nothing pinned
            // to it once 1-5 are already claimed elsewhere - the box
            // and its window grid still show either way, just without
            // a number that would otherwise look like a deliberate pin.
            Text {
                anchors.centerIn: parent
                z: 10
                visible: wsBox.modelData.id <= 5 && root.isPinned(wsBox.modelData)
                text: String(wsBox.modelData.id)
                color: Config.fgcolor
                opacity: 0.4
                // Outline so the number stays legible over whatever's
                // underneath it (light window rectangles/icons, not
                // just the box's own dark fill).
                style: Text.Outline
                styleColor: "black"
                font.family: Config.fontfamily
                font.bold: true
                font.pixelSize: Math.max(8, Math.min(wsBox.width, wsBox.height) * 0.55)
            }

            // Switches to this workspace - Hyprland's own activate(),
            // equivalent to HyprlandIpc.dispatch("workspace <name>").
            // Covers the whole box (window-grid rectangles/icons and
            // the number label underneath have no MouseAreas of their
            // own to compete with).
            MouseArea {
                anchors.fill: parent
                onClicked: wsBox.modelData.activate()
            }
        }
    }
}

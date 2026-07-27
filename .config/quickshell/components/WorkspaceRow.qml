import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
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
    Component.onCompleted: Hyprland.refreshToplevels()

    Repeater {
        model: root.sortedWorkspaces

        Rectangle {
            id: wsBox
            required property var modelData

            readonly property var mon: wsBox.modelData.monitor
            readonly property real aspect: (wsBox.mon && wsBox.mon.height > 0)
                ? (wsBox.mon.width / wsBox.mon.height)
                : (16 / 9)

            height: root.height
            width: wsBox.height * wsBox.aspect
            color: Config.fillcolor
            border.width: 2
            border.color: wsBox.modelData.active ? Config.fgcolor : Config.fgcolordark
            radius: 0

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

                    x: wsBox.mon ? (winBox.atArr[0] - wsBox.mon.x) / wsBox.mon.width * wsBox.width : 0
                    y: wsBox.mon ? (winBox.atArr[1] - wsBox.mon.y) / wsBox.mon.height * wsBox.height : 0
                    width: (wsBox.mon && wsBox.mon.width > 0)
                        ? Math.max(1, winBox.sizeArr[0] / wsBox.mon.width * wsBox.width)
                        : 1
                    height: (wsBox.mon && wsBox.mon.height > 0)
                        ? Math.max(1, winBox.sizeArr[1] / wsBox.mon.height * wsBox.height)
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
            // packed underneath it.
            Text {
                anchors.centerIn: parent
                z: 10
                text: String(wsBox.modelData.id)
                color: Config.fgcolorlight
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
        }
    }
}

import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

Scope {
    id: root

    // PowerMenu/LockScreen are separate files with their own IpcHandler-
    // driven state now (no more shared *State.qml singleton to read), so
    // shell.qml passes these down from the actual PowerMenu/LockScreen
    // instances it creates.
    property bool locked: false
    property bool powerMenuOpen: false

    // Dashboard/Notification instances, also passed down from shell.qml -
    // clicking their buttons below calls straight into these rather than
    // spawning a `qs ipc call` subprocess to talk to another component in
    // this very same process.
    property var dashboard: null
    property var notification: null

    // dashboard.primaryMonitor defaults to a hardcoded output name
    // ("DP-1") and isn't persisted to disk, so it can point at a screen
    // that doesn't exist at all on this machine/session (e.g. the same
    // config used on a laptop with only eDP-1) - without this, the bar
    // would then be invisible on every single screen. Falls back to
    // whatever screen shows up first instead of disappearing entirely.
    //
    // Compared by name, not object identity. A previous version of this
    // fallback compared modelData against Quickshell.screens[0] by
    // reference, and the bar started disappearing on every monitor
    // change instead of just when the real primary was missing - most
    // likely Quickshell.screens handing out fresh QtObjects whenever the
    // monitor set changes, making any previously-captured reference go
    // stale. `.name` is the only thing that's safe to compare here.
    readonly property bool primaryMonitorConnected: root.dashboard
        ? Quickshell.screens.some(s => s.name === root.dashboard.primaryMonitor)
        : true

    readonly property string effectivePrimaryName: root.primaryMonitorConnected
        ? (root.dashboard ? root.dashboard.primaryMonitor : "")
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")

    // Every connected screen, left-to-right by x - ties (side-by-side
    // monitors stacked vertically instead) broken by whichever is
    // closest to y = 0, so a monitor placed above the reference point
    // sorts before one placed further below it. Used below to rank
    // which monitor each workspace belongs to (see sortedWorkspaces).
    readonly property var sortedMonitors: Quickshell.screens.slice().sort((a, b) => {
        if (a.x !== b.x) return a.x - b.x
        return Math.abs(a.y) - Math.abs(b.y)
    })

    // Every current Hyprland workspace, sorted by its owning monitor's
    // position in sortedMonitors first and by workspace number second -
    // feeds the little per-workspace rectangle row to the left of the
    // clock (the dashboard-open button).
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

    // A toplevel's lastIpcObject (the only place its at/size/class live -
    // see WindowBox below) is only ever as fresh as the last
    // refreshToplevels() call, unlike title/activated/workspace which
    // update live - re-requested on every Hyprland event so the little
    // per-window rectangles track real opens/closes/moves/resizes
    // instead of a one-off snapshot from whenever quickshell started.
    Connections {
        target: Hyprland
        function onRawEvent(event) { Hyprland.refreshToplevels() }
    }
    Component.onCompleted: Hyprland.refreshToplevels()

    // Falls back to a sane default until hyprctl responds
    Variants {
        model: Quickshell.screens
        PanelWindow {
            // Double-click a display in Screen settings to mark it
            // primary - the whole bar (tray, clock, notification button)
            // only shows there, not just the tray. root.dashboard is the
            // actual Dashboard.qml instance (passed down from
            // shell.qml), whose primaryMonitor is itself shared across
            // every screen's dashWindow - see that file for why it has
            // to be.
            visible: !root.locked && !root.powerMenuOpen && (root.dashboard ? modelData.name === root.effectivePrimaryName : true)
            id: bar
            property var modelData
            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: 10
                left: 10
                right: 10
            }
            implicitHeight: 48
            // Transparent window; the visible bar is the Rectangle below.
            // This lets us draw a border without fighting the window's
            // own background compositing.
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                color: Config.fillcolor
                radius: 0
                border.width: 2
                border.color: Config.fgcolor
                Tray {
                    id: trayItem
                    border.width: 2
                    border.color: Config.fgcolor
                    width: trayWidth < 16 ? 0 : trayWidth + 16
                    implicitHeight: 26+8
                    anchors.margins: 10
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    screen: modelData
                }

                // One rectangle per current Hyprland workspace, sitting
                // directly to the left of the clock (the dashboard-open
                // button) - width-only aspect-ratio scaled to that
                // workspace's own monitor (HyprlandMonitor.width/height,
                // not the QuickshellScreenInfo one - see
                // root.sortedWorkspaces), height matched to the clock
                // card's own height rather than the bar's full content
                // height. Each box also draws a tiny live grid of that
                // workspace's actual windows - see the nested Repeater
                // below - positioned/sized from the same at/size/monitor
                // geometry `hyprctl -j clients` reports (surfaced here
                // via each toplevel's lastIpcObject), normalized into
                // this box's own pixel space.
                Row {
                    id: workspaceRow
                    height: clockCard.height
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: clockCard.left
                    anchors.rightMargin: 10
                    spacing: 6

                    Repeater {
                        model: root.sortedWorkspaces

                        Rectangle {
                            id: wsBox
                            required property var modelData

                            readonly property var mon: wsBox.modelData.monitor
                            readonly property real aspect: (wsBox.mon && wsBox.mon.height > 0)
                                ? (wsBox.mon.width / wsBox.mon.height)
                                : (16 / 9)

                            height: workspaceRow.height
                            width: wsBox.height * wsBox.aspect
                            color: Config.fillcolor
                            border.width: 2
                            border.color: wsBox.modelData.active ? Config.fgcolorlight : Config.fgcolor
                            radius: 0

                            // One rectangle per window actually open on
                            // this workspace, positioned/sized as a
                            // fraction of the owning monitor's geometry
                            // (at/size are absolute layout coordinates,
                            // same space as monitor.x/y/width/height) so
                            // it lands in the same relative spot inside
                            // this miniature box.
                            Repeater {
                                model: wsBox.modelData.toplevels.values

                                Rectangle {
                                    id: winBox
                                    required property var modelData

                                    readonly property var ipcData: winBox.modelData.lastIpcObject
                                    readonly property var atArr: winBox.ipcData.at ?? [0, 0]
                                    readonly property var sizeArr: winBox.ipcData.size ?? [0, 0]

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
                                    border.color: Config.fgcolor

                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: Math.max(4, Math.min(winBox.width, winBox.height) * 0.6)
                                        source: winBox.ipcData.class ? Quickshell.iconPath(winBox.ipcData.class) : ""
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: clockCard
                    anchors.centerIn: parent
                    width: clock.implicitWidth + 16
                    height: clock.implicitHeight + 4
                    border.width: 2
                    border.color: Config.fgcolor
                    color: clockmouseArea.containsMouse ? Config.fgcolorhover : "transparent"
                    Clock {
                        id: clock
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: clockmouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: {
                            if (root.dashboard) {
                                root.dashboard.toggle(modelData)
                            }
                        }
                    }
                }

                Rectangle {
                    id: notificationButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 10
                    }

                    border.width: 2
                    border.color: Config.fgcolor
                    width: 34
                    height: 34
                    color: notifmouseArea.containsMouse ? Config.fgcolorhover : "transparent"

                    MouseArea {
                        id: notifmouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: {
                            if (root.notification) {
                                root.notification.centerOpen = !root.notification.centerOpen
                            }
                        }
                    }

                    IconImage {
                        id: notifIcon

                        implicitSize: 32
                        source: Quickshell.iconPath("notifications-symbolic")
                    }

                    ColorOverlay {
                        anchors.fill: notifIcon
                        source: notifIcon
                        color: Config.fgcolor
                    }
                }
            }
        }
    }
}

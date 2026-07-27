import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
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
    // sorts before one placed further below it. Feeds the little
    // per-monitor rectangle row between the tray and the clock.
    readonly property var sortedMonitors: Quickshell.screens.slice().sort((a, b) => {
        if (a.x !== b.x) return a.x - b.x
        return Math.abs(a.y) - Math.abs(b.y)
    })

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

                // One rectangle per connected monitor, sitting centered
                // in the gap between the tray and the clock (the
                // dashboard-open button) - width-only aspect-ratio
                // scaled to each screen's own width/height ratio like
                // WorkspaceOsd's boxes, height pinned to the bar's own
                // content height so every box lines up with the rest of
                // the bar regardless of how wide a given monitor is.
                Item {
                    id: monitorRowArea
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    anchors.left: trayItem.right
                    anchors.right: clockCard.left

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Repeater {
                            model: root.sortedMonitors

                            Rectangle {
                                required property var modelData

                                height: monitorRowArea.height
                                width: monitorRowArea.height * (modelData.width / modelData.height)
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor
                                radius: 0
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

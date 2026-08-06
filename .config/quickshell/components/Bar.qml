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

            // Same reference-resolution scaling formula as Dashboard.qml/
            // WorkspaceOsd.qml, so every element below tracks this
            // screen's own resolution instead of assuming a fixed one.
            readonly property real uiScale: Math.max(0.6, Math.min(1.8, modelData.width * 0.42 / 800))

            // Explicit (every other panel in this shell sets one too) so
            // Screenshot.qml can find this exact surface via `hyprctl
            // layers -j` and make it right-click-selectable like a
            // window - it never shows up in `hyprctl clients -j` at all,
            // being a layer-shell surface rather than a toplevel window.
            WlrLayershell.namespace: "bar"

            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: Config.scaled(10, bar.uiScale)
                left: Config.scaled(10, bar.uiScale)
                right: Config.scaled(10, bar.uiScale)
            }
            implicitHeight: Config.scaled(Config.barheight, bar.uiScale)
            // Transparent window; the visible bar is the Rectangle below.
            // This lets us draw a border without fighting the window's
            // own background compositing.
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                color: Config.fillcolor
                radius: 0
                border.width: Config.scaled(2, bar.uiScale)
                border.color: Config.fgcolor
                Tray {
                    id: trayItem
                    border.width: Config.scaled(2, bar.uiScale)
                    border.color: Config.fgcolor
                    width: trayWidth < 16 ? 0 : trayWidth + Config.scaled(16, bar.uiScale)
                    implicitHeight: Config.scaled(26 + 8, bar.uiScale)
                    anchors.margins: Config.scaled(10, bar.uiScale)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    screen: modelData
                    isPrimary: root.dashboard ? modelData.name === root.effectivePrimaryName : true
                }

                // See WorkspaceRow.qml - sits to the left of the clock
                // (the dashboard-open button), which sets its height
                // here since layer-shell/anchors info all lives in this
                // file. rightMargin is the usual 10px inset plus 32px of
                // deliberate extra breathing room before the dashboard
                // button specifically.
                WorkspaceRow {
                    id: workspaceRow
                    height: clockCard.height
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: clockCard.left
                    anchors.rightMargin: Config.scaled(10 + 32, bar.uiScale)
                }

                // Sits centered in the 42px gap above (10 base inset +
                // 32 deliberate breathing room) between workspaceRow and
                // the dashboard-open button - full bar height rather
                // than the shorter 60%-height ones WorkspaceRow.qml
                // draws between its own monitor groups, so this one
                // reads as a stronger divider between the two.
                Rectangle {
                    id: workspaceDashboardSeparator
                    width: Config.scaled(12, bar.uiScale)
                    height: Config.scaled(2, bar.uiScale)
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: clockCard.left
                    anchors.rightMargin: Config.scaled(15, bar.uiScale)
                    color: Config.fgcolor
                }

                Rectangle {
                    id: clockCard
                    anchors.centerIn: parent
                    width: clock.implicitWidth + Config.scaled(16, bar.uiScale)
                    height: clock.implicitHeight + Config.scaled(4, bar.uiScale)
                    border.width: Config.scaled(2, bar.uiScale)
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

                    Rectangle {
                        id: workspaceDashboardSeparatorR
                        width: Config.scaled(12, bar.uiScale)
                        height: Config.scaled(2, bar.uiScale)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: clockCard.right
                        anchors.leftMargin: Config.scaled(16, bar.uiScale)
                        color: Config.fgcolor
                    }
                }

                VolumeControl {
                    id: volumeControl
                    uiScale: bar.uiScale
                    dashboard: root.dashboard
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: clockCard.right
                    anchors.leftMargin: Config.scaled(10 + 32, bar.uiScale)
                }

                // Hides itself entirely (BrightnessControl.qml's own
                // visible/width/height) when the currently-targeted
                // monitor has no brightness control at all - nothing
                // here needs to react to that, the gap after
                // volumeControl just doesn't open up.
                BrightnessControl {
                    id: brightnessControl
                    uiScale: bar.uiScale
                    dashboard: root.dashboard
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: volumeControl.right
                    anchors.leftMargin: Config.scaled(10, bar.uiScale)
                }

                // Hides itself entirely (BatteryControl.qml's own
                // visible/width/height) on a desktop with no real
                // system battery - nothing here needs to react to that,
                // the gap after brightnessControl just doesn't open up.
                BatteryControl {
                    id: batteryControl
                    uiScale: bar.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: brightnessControl.right
                    anchors.leftMargin: Config.scaled(10, bar.uiScale)
                }

                Rectangle {
                    id: notificationButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Config.scaled(10, bar.uiScale)
                    }

                    border.width: Config.scaled(2, bar.uiScale)
                    border.color: Config.fgcolor
                    width: Config.scaled(34, bar.uiScale)
                    height: Config.scaled(34, bar.uiScale)
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

                        // Previously had no anchors at all, so it sat
                        // at the button's top-left corner instead of
                        // centered in it.
                        anchors.centerIn: parent
                        implicitSize: Config.scaled(32, bar.uiScale)
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

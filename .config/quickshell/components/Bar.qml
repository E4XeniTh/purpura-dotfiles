import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import "lockscreen"
import "powermenu"
import "dashboard"
import "tray"

Scope {
    id: root
    // Falls back to a sane default until hyprctl responds
    Variants {
        model: Quickshell.screens
        PanelWindow {
            visible: !LockScreenState.locked && !PowerMenuState.open
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
                color: Theme.fillcolor
                radius: 0
                border.width: 2
                border.color: Theme.fgcolor
                Tray {
                    border.width: 2
                    border.color: Theme.fgcolor
                    width: trayWidth < 16 ? 0 : trayWidth + 16
                    implicitHeight: 26+8
                    anchors.margins: 10
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    screen: modelData
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: clock.implicitWidth + 16
                    height: clock.implicitHeight + 4
                    border.width: 2
                    border.color: Theme.fgcolor
                    color: clockmouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                    Clock {
                        id: clock
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        id: clockmouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: DashboardState.toggle(modelData)
                    }
                }

                // Placeholder for now - will open a notification manager
                // once one exists.
                Rectangle {
                    id: notificationButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 10
                    }

                    border.width: 2
                    border.color: Theme.fgcolor
                    width: 34
                    height: 34
                    color: notifmouseArea.containsMouse ? Theme.fgcolorhover : "transparent"

                    MouseArea {
                        id: notifmouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        // onClicked: DashboardState.toggle(modelData)
                    }

                    IconImage {

                        implicitSize: 32
                        source: Quickshell.iconPath("notifications-symbolic")
                    }
                }
            }
        }
    }
}

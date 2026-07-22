import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import "../Config.js" as Config

Scope {
    id: root

    // PowerMenu/LockScreen are separate files with their own IpcHandler-
    // driven state now (no more shared *State.qml singleton to read), so
    // shell.qml passes these down from the actual PowerMenu/LockScreen
    // instances it creates.
    property bool locked: false
    property bool powerMenuOpen: false

    // Falls back to a sane default until hyprctl responds
    Variants {
        model: Quickshell.screens
        PanelWindow {
            visible: !root.locked && !root.powerMenuOpen
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
                    border.width: 2
                    border.color: Config.fgcolor
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
                    border.color: Config.fgcolor
                    color: clockmouseArea.containsMouse ? Config.fgcolorhover : "transparent"
                    Clock {
                        id: clock
                        anchors.centerIn: parent
                    }

                    // Dashboard.qml is a separate file/Scope with its own
                    // open/screen state now - same IPC path as `qs ipc
                    // call dashboard toggle`. Note this always targets
                    // the primary screen (no click-position context over
                    // IPC), so on multi-monitor setups this may open the
                    // dashboard on a different monitor than the one you
                    // clicked.
                    Process {
                        id: dashboardToggleProcess
                        command: ["qs", "ipc", "call", "dashboard", "toggle"]
                    }

                    MouseArea {
                        id: clockmouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: {
                            dashboardToggleProcess.running = false
                            dashboardToggleProcess.running = true
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

                    // Notification.qml is a separate file/Scope with its own
                    // centerOpen - the only way in is through its
                    // IpcHandler, same as `qs ipc call notificationpanel
                    // toggle` from a terminal.
                    Process {
                        id: notifToggleProcess
                        command: ["qs", "ipc", "call", "notificationpanel", "toggle"]
                    }

                    MouseArea {
                        id: notifmouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: {
                            notifToggleProcess.running = false
                            notifToggleProcess.running = true
                        }
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

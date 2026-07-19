import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

Scope {
    id: root
    // Falls back to a sane default until hyprctl responds
    Variants {
        model: Quickshell.screens
        PanelWindow {
            visible: !LockState.locked
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
                    anchors.margins: 10
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    screen: modelData
                }

                Clock {
                    anchors.centerIn: parent
                }

                Rectangle {
                    id: powerButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 10
                    }

                    width: 32
                    height: 24
                    radius: 8
                    color: Theme.fillcolor

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: Quickshell.iconPath("system-shutdown-symbolic")
                    }

                    MouseArea {
                        anchors.fill: parent

                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                PowerMenuState.open = true
                            } else if (mouse.button === Qt.RightButton) {
                                LockMenuState.locked = true
                            }
                        }
                    }
                }
            }
        }
    }
}




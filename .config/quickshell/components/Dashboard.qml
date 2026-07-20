import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// Dashboard dropdown, toggled from the avatar button in Bar.qml. Uses the
// same two-phase stretch-then-drop animation as TrayMenu.qml, but is
// positioned to overlap the bar's own bottom border by exactly its width
// (2px) so the two read as one continuous shape instead of a separate
// floating box. Content is a placeholder for now (just the relocated power
// button) - meant to grow over time.
Scope {
    id: root

    readonly property int dashWidth: 800

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dashWindow

            property var modelData
            screen: modelData

            visible: DashboardState.open && DashboardState.screen === modelData

            WlrLayershell.namespace: "dashboard"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: true
            }
            exclusiveZone: 0

            margins {
                // Bar's own top margin (10) + height (48) - border width (2),
                // so this window's top edge lands exactly on the bar's
                // bottom border instead of leaving a gap or a seam.
                top: 10
                left: (modelData.width - root.dashWidth) / 2
                right: (modelData.width + root.dashWidth) / 2
            }

            implicitWidth: root.dashWidth
            implicitHeight: Math.max(dashContent.height, 1)

            color: "transparent"

            Rectangle {
                id: dashBox

                anchors.horizontalCenter: parent.horizontalCenter

                width: 0
                height: 4

                color: Theme.fillcolor

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: dashBox

                            width: root.dashWidth
                            height: 2
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: dashBox

                            width: root.dashWidth
                            height: Math.max(dashContent.height, 1)
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

                Item {
                    id: contentMask

                    anchors.fill: parent
                    clip: true

                    Column {
                        id: dashContent

                        width: root.dashWidth

                        topPadding: 16
                        bottomPadding: 16

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                id: powerButton

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
                                            DashboardState.close()
                                        } else if (mouse.button === Qt.RightButton) {
                                            LockMenuState.locked = true
                                            DashboardState.close()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.width: 2
                    border.color: Theme.fgcolor

                    radius: 0

                    z: 10
                }
            }

            onVisibleChanged: {
                if (visible) {
                    dashBox.width = 0
                    dashBox.height = 4

                    dashBox.state = "horizontal"
                    dashOpenTimer.start()
                }
            }

            Timer {
                id: dashOpenTimer

                // Must match the transition's duration above, so phase 1
                // (width) fully finishes before phase 2 (height) starts.
                interval: 300
                repeat: false

                onTriggered: {
                    dashBox.state = "open"
                }
            }
        }
    }
}

import Quickshell
import Quickshell.Wayland
import QtQuick

// Themed right-click context menu for tray items (components/Tray.qml).
// One PanelWindow per screen, shown only on the screen a menu was opened on.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: menuWindow

            property var modelData
            screen: modelData

            visible: TrayMenuState.open && TrayMenuState.screen === modelData

            WlrLayershell.namespace: "trayMenu"
            WlrLayershell.layer: WlrLayer.Overlay

            exclusiveZone: 0

            anchors {
                top: true
                left: true
            }

            margins {
                top: TrayMenuState.marginTop
                left: TrayMenuState.marginLeft
            }

            implicitWidth: 160
            implicitHeight: Math.max(entryColumn.height + (2 * 5), 1)

            color: "transparent"

            QsMenuOpener {
                id: opener
                menu: TrayMenuState.menu
            }

            Rectangle {
                id: menuBox

                width: 0
                height: 4
                color: Theme.fillcolorSolid

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: menuBox

                            width: 160
                            height: 2
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: menuBox

                            width: 160
                            height: Math.max(entryColumn.height + (2 * 5), 1)
                        }
                    }

                ]

                transitions: [

                    Transition {

                        NumberAnimation {

                            properties: "height"

                            duration: 350

                            easing.type: Easing.OutCubic

                        }

                    }

                ]

                Item {
                    id: contentMask
                    anchors.fill: parent
                    anchors.topMargin: 5
                    anchors.bottomMargin: 5
                    clip: true


                    Column {
                        id: entryColumn
                        width: 160

                        Repeater {
                            model: opener.children

                            delegate: Item {
                                id: entryDelegate

                                required property var modelData

                                width: entryColumn.width
                                height: entryDelegate.modelData.isSeparator ? 9 : 28

                                Rectangle {
                                    visible: entryDelegate.modelData.isSeparator

                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 8
                                        rightMargin: 8
                                    }

                                    height: 1
                                    color: Theme.fgcolordark
                                }

                                Rectangle {
                                    visible: !entryDelegate.modelData.isSeparator

                                    anchors.fill: parent

                                    color: entryMouse.containsMouse ? Theme.fgcolordark : "transparent"

                                    Text {
                                        anchors {
                                            fill: parent
                                            leftMargin: 10
                                            rightMargin: 10
                                        }

                                        verticalAlignment: Text.AlignVCenter

                                        text: entryDelegate.modelData.isSeparator ? "" : entryDelegate.modelData.text
                                        color: entryDelegate.modelData.enabled ? Theme.fgcolor : Qt.rgba(1, 1, 1, 0.35)
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        id: entryMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !entryDelegate.modelData.isSeparator && entryDelegate.modelData.enabled

                                        onClicked: {
                                            entryDelegate.modelData.triggered()
                                            TrayMenuState.close()
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
                    menuBox.width = 0
                    menuBox.height = 4

                    menuBox.state = "horizontal"
                    menuOpenTimer.start()
                }
            }

            Timer {
                id: menuOpenTimer

                interval: 80
                repeat: false

                onTriggered: {
                    menuBox.state = "open"
                }
            }
        }
    }
}

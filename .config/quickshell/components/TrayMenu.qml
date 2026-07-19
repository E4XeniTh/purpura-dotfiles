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

            property bool everActivated: false

            visible: TrayMenuState.open && TrayMenuState.screen === modelData

            WlrLayershell.namespace: "trayMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrLayershell.OnDemand : WlrLayershell.None

            exclusiveZone: 0

            anchors {
                top: true
                left: true
            }

            margins {
                top: TrayMenuState.marginTop
                left: TrayMenuState.marginLeft
            }

            implicitWidth: 180
            implicitHeight: Math.max(entryColumn.height, 1)

            color: "transparent"

            // Best-effort dismiss when focus moves elsewhere. Only reacts
            // once we've actually been active, so opening the window doesn't
            // immediately close it before the compositor grants focus.
            onActiveChanged: {
                if (active) {
                    everActivated = true
                } else if (everActivated) {
                    everActivated = false
                    TrayMenuState.close()
                }
            }

            QsMenuOpener {
                id: opener
                menu: TrayMenuState.menu
            }

            Rectangle {
                anchors.fill: parent

                color: Theme.fillcolor
                border.width: 2
                border.color: Theme.fgcolor
                radius: 0

                Column {
                    id: entryColumn

                    width: parent.width

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
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 10
                                        rightMargin: 10
                                    }

                                    text: entryDelegate.modelData.isSeparator ? "" : entryDelegate.modelData.text
                                    color: entryDelegate.modelData.enabled ? "white" : Qt.rgba(1, 1, 1, 0.35)
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
        }
    }
}

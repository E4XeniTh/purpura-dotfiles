import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "../"

Rectangle {
    id: root

    // Set from Bar.qml so right-clicked items open their menu on the
    // right monitor.
    property var screen: null

    radius: 8
    color: Theme.fillcolor

    implicitHeight: 24
    implicitWidth: trayRow.width + 12

    Process {
        id: killProcess
    }

    Row {
        id: trayRow

        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem

                required property var modelData

                width: 30
                height: width

                Image {
                    anchors.fill: parent
                    source: trayItem.modelData.icon
                }

                MouseArea {
                    anchors.fill: parent

                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            trayItem.modelData.activate()
                        }

                        if (mouse.button === Qt.RightButton) {
                            if (TrayMenuState.open && TrayMenuState.menu === trayItem.modelData.menu) {
                                // Right-clicking the same item again toggles it shut.
                                TrayMenuState.close()
                            } else if (trayItem.modelData.menu) {
                                // Bar.qml's own margins (10 left, 10 top, 48 tall) plus
                                // this item's offset within the tray row. Keep these in
                                // sync if the bar's layout ever changes.
                                TrayMenuState.marginLeft = 10 + trayItem.x
                                TrayMenuState.marginTop = 4
                                TrayMenuState.screen = root.screen
                                TrayMenuState.menu = trayItem.modelData.menu
                            } else {
                                trayItem.modelData.secondaryActivate()
                            }
                        }
                    }
                }
            }
        }
    }
}

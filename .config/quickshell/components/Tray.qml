import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Controls
import Quickshell.Io

Rectangle {
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
                required property var modelData

                width: 16
                height: 16

                Image {
                    anchors.fill: parent
                    source: modelData.icon
                }

                MouseArea {
                    anchors.fill: parent

                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: {
                        if (mouse.button === Qt.LeftButton) {
                            modelData.activate()
                        }

                        if (mouse.button === Qt.RightButton) {
                            modelData.secondaryActivate()
                        }
                    }
                }
            }
        }
    }
}

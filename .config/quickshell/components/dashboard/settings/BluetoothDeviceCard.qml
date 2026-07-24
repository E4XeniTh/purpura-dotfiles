import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Bluetooth
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One bluetooth device: an icon (BlueZ already reports a fitting one per
// device via .icon, so no guessing needed) + name, DashCard-style.
// Left-click pairs (if unpaired), connects (if paired but not connected),
// or disconnects (if already connected). Right-click forgets the device.
DashCard {
    id: root

    required property var device
    property real uiScale: 1.0

    border.color: !device.paired ? Config.fgcolordark
        : (device.connected ? Config.fgcolorlight : Config.fgcolor)

    // Auto-trust the instant a device becomes paired, so it can
    // reconnect later without prompting.
    Connections {
        target: root.device

        function onPairedChanged() {
            if (root.device.paired) {
                root.device.trusted = true
            }
        }
    }

    RowLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: 0

        Item {
            Layout.preferredWidth: parent.width * 0.25
            Layout.fillHeight: true

            IconImage {
                id: deviceIcon
                anchors.centerIn: parent
                implicitSize: Config.scaled(22, root.uiScale)
                source: root.device.icon.length > 0 ? Quickshell.iconPath(root.device.icon) : Quickshell.iconPath("bluetooth-symbolic")
            }

            ColorOverlay {
                anchors.fill: deviceIcon
                source: deviceIcon
                color: root.border.color
            }
        }

        Rectangle {
            Layout.preferredWidth: Config.scaled(1, root.uiScale)
            Layout.fillHeight: true
            color: Config.fgcolordark
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Config.scaled(10, root.uiScale)
            text: root.device.name.length > 0 ? root.device.name : root.device.deviceName
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                if (!root.device.paired) {
                    root.device.pair()
                } else if (!root.device.connected) {
                    root.device.connect()
                } else {
                    root.device.disconnect()
                }
            } else {
                root.device.forget()
            }
        }
    }
}

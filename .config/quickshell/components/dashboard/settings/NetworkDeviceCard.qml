import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Networking
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One network device (interface) in NetworkSettings' Devices tab. Right-
// click toggles nmManaged - NetworkDevice has no separate on/off switch
// of its own, so "enable/disable" here means whether NetworkManager
// manages the interface at all.
DashCard {
    id: root

    required property var device
    property real uiScale: 1.0

    border.color: root.device.nmManaged ? Config.fgcolor : "red"

    RowLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(10, root.uiScale)

        Item {
            Layout.preferredWidth: Config.scaled(24, root.uiScale)
            Layout.preferredHeight: Config.scaled(24, root.uiScale)

            IconImage {
                id: deviceIcon
                anchors.fill: parent
                source: Quickshell.iconPath(
                    root.device.type === DeviceType.Wifi ? "network-wireless-symbolic" : "network-wired-symbolic"
                )
            }

            ColorOverlay {
                anchors.fill: deviceIcon
                source: deviceIcon
                color: root.border.color
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Config.scaled(2, root.uiScale)

            Text {
                Layout.fillWidth: true
                text: root.device.name
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(15, root.uiScale)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: DeviceType.toString(root.device.type)
                color: Config.fgcolordark
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.device.nmManaged = !root.device.nmManaged
    }
}

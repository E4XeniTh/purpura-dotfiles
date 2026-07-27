import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// A read-only "connection" row for interfaces NetworkManager itself
// sees but Quickshell.Networking's own device model never surfaces -
// Bluetooth tethering, ZeroTier and other tun/bridge/etc. interfaces
// (see NetworkSettings.qml's own note: only Wifi/Ethernet device types
// are ever wrapped by that module). Fed from parsing plain `nmcli`'s
// device dump, not a live Quickshell object, so unlike NetworkCard.qml
// there's no real .connect()/.disconnect()/.forget() to wire a
// MouseArea to here - this is display only until/unless that's built
// out with its own nmcli/zerotier-cli calls.
DashCard {
    id: root

    property string displayName: ""
    property string secondaryLabel: ""
    property string iconName: "network-wired-symbolic"
    property bool connected: false
    property real uiScale: 1.0

    border.color: root.connected ? Config.fgcolorlight : Config.fgcolor

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
                id: extraIcon
                anchors.fill: parent
                source: Quickshell.iconPath(root.iconName, "network-wired-symbolic")
            }

            ColorOverlay {
                anchors.fill: extraIcon
                source: extraIcon
                color: root.border.color
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.displayName
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(15, root.uiScale)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: root.secondaryLabel.length > 0
                text: root.secondaryLabel
                color: Config.fgcolordark
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(11, root.uiScale)
                elide: Text.ElideRight
            }
        }
    }
}

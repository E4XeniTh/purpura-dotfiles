import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Networking
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One network (a wifi SSID or wired connection) in NetworkSettings'
// Connections and WiFi tabs. Left-click connects (if not connected) or
// disconnects (if connected). Right-click forgets it, but only where
// allowForget is set (the WiFi tab). Connecting to a secured wifi
// network that needs a password surfaces NetworkManager's own polkit
// agent prompt (a separate system dialog, not drawn by this shell), so
// there's no in-panel password UI here.
//
// `network` can go null out from under an already-instantiated card:
// NetworkManager can remove an access point/connection profile (wifi
// out of range, a saved connection deleted) while this card's delegate
// is still alive - confirmed from a live crash log showing exactly
// that ("Cannot read property of null" here, moments before a
// segfault) even while the panel wasn't visible, since ListView
// delegates aren't torn down just because the window is hidden. Every
// access below guards for that.
DashCard {
    id: root

    required property var network
    property real uiScale: 1.0
    property bool allowForget: false

    // Set from NetworkSettings.qml's Connections tab only (WiFi tab
    // leaves both at their default, unchanged look) - secondaryLabel
    // distinguishes what kind of connection this actually is (e.g. a
    // USB-tethered phone showing up as a plain Ethernet device would
    // otherwise be indistinguishable from a real wired NIC), and
    // iconOverride swaps the icon to match when set.
    property string secondaryLabel: ""
    property string iconOverride: ""

    readonly property bool isWifi: !!(root.network && root.network.device && root.network.device.type === DeviceType.Wifi)

    border.color: (root.network && root.network.connected) ? Config.fgcolorlight : Config.fgcolor

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
                id: networkIcon
                anchors.fill: parent
                source: root.iconOverride.length > 0
                    ? Quickshell.iconPath(root.iconOverride, "network-wired-symbolic")
                    : Quickshell.iconPath(root.isWifi ? "network-wireless-symbolic" : "network-wired-symbolic", "network-wired-symbolic")
            }

            ColorOverlay {
                anchors.fill: networkIcon
                source: networkIcon
                color: root.border.color
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.network ? root.network.name : ""
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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (!root.network) return

            if (mouse.button === Qt.RightButton) {
                if (root.allowForget) root.network.forget()
            } else if (root.network.connected) {
                root.network.disconnect()
            } else {
                root.network.connect()
            }
        }
    }
}

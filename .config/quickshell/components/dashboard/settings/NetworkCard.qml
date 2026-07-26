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
// disconnects (if connected). If connecting to a wifi network fails
// because it needs a password, a DialogCard prompt opens right here
// asking for one - connectWithPsk() only exists on WifiNetwork, but
// QML dispatches off the actual underlying object regardless of how
// it's typed where this card got it from, so calling it unconditionally
// on a wifi-only code path is safe.
DashCard {
    id: root

    required property var network
    property real uiScale: 1.0

    readonly property bool isWifi: root.network.device && root.network.device.type === DeviceType.Wifi

    border.color: root.network.connected ? Config.fgcolorlight : Config.fgcolor

    // A wired network never fails for lack of a password, so this is
    // effectively wifi-only in practice even though it's wired up
    // unconditionally.
    Connections {
        target: root.network
        function onConnectionFailed(reason) {
            if (root.isWifi && reason === ConnectionFailReason.NoSecrets) {
                pskDialog.show("PASSWORD FOR " + root.network.name)
            }
        }
    }

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
                source: Quickshell.iconPath(root.isWifi ? "network-wireless-symbolic" : "network-wired-symbolic")
            }

            ColorOverlay {
                anchors.fill: networkIcon
                source: networkIcon
                color: root.border.color
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.network.name
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(15, root.uiScale)
            font.bold: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // The dialog (if it opens) covers this card and has its own
        // input - avoid also toggling connect/disconnect underneath it.
        enabled: !pskDialog.open
        onClicked: {
            if (root.network.connected) {
                root.network.disconnect()
            } else {
                root.network.connect()
            }
        }
    }

    DialogCard {
        id: pskDialog
        uiScale: root.uiScale
        onConfirmed: (text) => root.network.connectWithPsk(text)
    }
}

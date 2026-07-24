import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Bluetooth
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One bluetooth controller (adapter): a fixed usb icon + name, DashCard-
// style. Right-click toggles the adapter on/off. There's no left-click
// "select" - Quickshell's bluez wrapper has no settable "preferred
// adapter" (it always uses the first one it sees), so a selection
// concept here wouldn't change anything system-side, and only made
// every controller start out looking dim/disabled until clicked once.
DashCard {
    id: root

    required property var adapter
    property real uiScale: 1.0

    readonly property bool blocked: adapter.state === BluetoothAdapterState.Blocked

    // Blocked (rfkill) is visually distinct from merely off (red) - it
    // can't be toggled on from here at all, so it needs its own color
    // rather than looking like any other disabled controller.
    border.color: root.blocked ? Config.fgcolordark : (adapter.enabled ? Config.fgcolor : "red")

    RowLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(10, root.uiScale)

        // Fixed-size icon instead of a width fraction of the card - a
        // percentage split fought resizing/finding a good width, this
        // just takes its own natural size and lets the name fill the
        // rest.
        Item {
            Layout.preferredWidth: Config.scaled(24, root.uiScale)
            Layout.preferredHeight: Config.scaled(24, root.uiScale)

            IconImage {
                id: usbIcon
                anchors.fill: parent
                // Adapters have no per-device icon like BluetoothDevice
                // does - controllers are almost always a USB dongle (or a
                // laptop's built-in radio, which shares the same generic
                // icon in most themes). Flag if your theme names this
                // differently.
                source: Quickshell.iconPath("drive-harddisk-usb-symbolic")
            }

            ColorOverlay {
                anchors.fill: usbIcon
                source: usbIcon
                color: root.border.color
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.adapter.name
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(16, root.uiScale)
            font.bold: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        // Enabling a blocked adapter is rejected outright (see
        // BluetoothAdapter::setEnabled) - skip the doomed attempt
        // instead of just logging a critical error every click.
        onClicked: {
            if (!root.blocked) {
                root.adapter.enabled = !root.adapter.enabled
            }
        }
    }
}

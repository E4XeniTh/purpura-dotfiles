import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One bluetooth controller (adapter): a fixed usb icon + name, DashCard-
// style. Left-click selects it - cosmetic only, since Quickshell's bluez
// wrapper has no settable "preferred adapter" (it always uses the first
// one it sees), so this doesn't change anything system-side. Right-click
// toggles the adapter on/off, which is real.
DashCard {
    id: root

    required property var adapter
    property bool isSelected: false
    property real uiScale: 1.0

    signal selected()

    border.color: !adapter.enabled ? "red"
        : (isSelected ? Config.fgcolor : Config.fgcolordark)

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
                id: usbIcon
                anchors.centerIn: parent
                implicitSize: Config.scaled(22, root.uiScale)
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

        Rectangle {
            Layout.preferredWidth: Config.scaled(1, root.uiScale)
            Layout.fillHeight: true
            color: Config.fgcolordark
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Config.scaled(10, root.uiScale)
            text: root.adapter.name
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
                root.selected()
            } else {
                root.adapter.enabled = !root.adapter.enabled
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../"
import "../../../Config.js" as Config

// Bluetooth controllers (left, 30%) + paired/unpaired devices (right,
// 70%), split by a vertical line. Instantiated inside dashWindow (see
// Dashboard.qml), which drives `active` through its settings-panel
// coordinator so this closes seamlessly if another panel opens.
//
// Note: pairing goes through BlueZ's pair() directly - Quickshell's
// bluetooth module doesn't implement a pairing agent (org.bluez.Agent1),
// so devices needing "Just Works" pairing succeed fine, but ones that
// actually require a PIN/passkey prompt have nothing here to answer that
// request yet. Revisit once an agent exists.
SettingsPanel {
    id: root

    namespaceName: "bluetoothSettings"

    // Cosmetic only - see ControllerCard.qml's own comment on why this
    // doesn't (and can't) change which adapter BlueZ actually uses.
    property var selectedAdapter: null

    readonly property var pairedDevices: Bluetooth.devices.values.filter(d => d.paired)
    readonly property var unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired)

    // Scan for nearby devices only while this panel is open.
    onActiveChanged: {
        const adapters = Bluetooth.adapters.values
        for (let i = 0; i < adapters.length; i++) {
            adapters[i].discovering = root.active
        }
    }

    RowLayout {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Config.scaled(16, root.uiScale)
        }
        spacing: Config.scaled(12, root.uiScale)

        readonly property real dividerWidth: Config.scaled(2, root.uiScale)
        readonly property real availableWidth: width - spacing * 2 - dividerWidth
        readonly property real leftWidth: availableWidth * 0.3
        readonly property real rightWidth: availableWidth * 0.7
        readonly property real listMaxHeight: Config.scaled(280, root.uiScale)
        readonly property real cardHeight: Config.scaled(56, root.uiScale)

        // ---------------- LEFT: controllers ----------------
        ColumnLayout {
            Layout.preferredWidth: content.leftWidth
            Layout.alignment: Qt.AlignTop
            spacing: Config.scaled(8, root.uiScale)

            Text {
                text: "Controllers"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
            }

            ListView {
                id: controllerList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, content.listMaxHeight)
                clip: true
                spacing: Config.scaled(8, root.uiScale)
                boundsBehavior: Flickable.StopAtBounds

                model: ScriptModel { values: Bluetooth.adapters.values }

                delegate: ControllerCard {
                    required property var modelData

                    width: controllerList.width
                    height: content.cardHeight
                    uiScale: root.uiScale
                    adapter: modelData
                    isSelected: root.selectedAdapter === modelData
                    onSelected: root.selectedAdapter = modelData
                }
            }
        }

        // ---------------- divider ----------------
        Rectangle {
            Layout.preferredWidth: content.dividerWidth
            Layout.fillHeight: true
            color: Config.fgcolordark
        }

        // ---------------- RIGHT: paired / unpaired devices ----------------
        ColumnLayout {
            Layout.preferredWidth: content.rightWidth
            Layout.alignment: Qt.AlignTop
            spacing: Config.scaled(8, root.uiScale)

            Text {
                text: "Paired"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
            }

            ListView {
                id: pairedList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, content.listMaxHeight)
                clip: true
                spacing: Config.scaled(8, root.uiScale)
                boundsBehavior: Flickable.StopAtBounds

                model: ScriptModel { values: root.pairedDevices }

                delegate: BluetoothDeviceCard {
                    required property var modelData

                    width: pairedList.width
                    height: content.cardHeight
                    uiScale: root.uiScale
                    device: modelData
                }
            }

            // Separator between paired and unpaired lists.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.scaled(2, root.uiScale)
                color: Config.fgcolordark
            }

            Text {
                text: "Unpaired"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
            }

            ListView {
                id: unpairedList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, content.listMaxHeight)
                clip: true
                spacing: Config.scaled(8, root.uiScale)
                boundsBehavior: Flickable.StopAtBounds

                model: ScriptModel { values: root.unpairedDevices }

                delegate: BluetoothDeviceCard {
                    required property var modelData

                    width: unpairedList.width
                    height: content.cardHeight
                    uiScale: root.uiScale
                    device: modelData
                }

                // Dialog box (PIN/password prompts) will go here once a
                // pairing agent exists - see the file-level note above.
            }
        }
    }
}

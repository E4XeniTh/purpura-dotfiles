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

    // Paired and unpaired devices share a single scrollable ListView, with
    // "header" and "separator" entries mixed into the same model instead
    // of two side-by-side lists - kind distinguishes what each row is.
    readonly property var deviceEntries: {
        const list = [{ kind: "header", label: "Paired" }]
        for (const d of root.pairedDevices) {
            list.push({ kind: "device", device: d })
        }
        list.push({ kind: "separator" })
        list.push({ kind: "header", label: "Unpaired" })
        for (const d of root.unpairedDevices) {
            list.push({ kind: "device", device: d })
        }
        return list
    }

    // Scan for nearby devices only while this panel is open.
    onActiveChanged: {
        const adapters = Bluetooth.adapters.values
        for (let i = 0; i < adapters.length; i++) {
            adapters[i].discovering = root.active
        }
    }

    RowLayout {
        id: contentRow

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
        readonly property real listMaxHeight: Config.scaled(160, root.uiScale)
        readonly property real cardHeight: Config.scaled(56, root.uiScale)

        // ---------------- LEFT: controllers ----------------
        ColumnLayout {
            Layout.preferredWidth: contentRow.leftWidth
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
                Layout.preferredHeight: Math.min(contentHeight, contentRow.listMaxHeight)
                clip: true
                spacing: Config.scaled(8, root.uiScale)
                boundsBehavior: Flickable.StopAtBounds

                model: ScriptModel { values: Bluetooth.adapters.values }

                delegate: ControllerCard {
                    required property var modelData

                    width: controllerList.width
                    height: contentRow.cardHeight
                    uiScale: root.uiScale
                    adapter: modelData
                    isSelected: root.selectedAdapter === modelData
                    onSelected: root.selectedAdapter = modelData
                }
            }
        }

        // ---------------- divider ----------------
        Rectangle {
            Layout.preferredWidth: contentRow.dividerWidth
            Layout.fillHeight: true
            color: Config.fgcolordark
        }

        // ---------------- RIGHT: paired + unpaired devices, one list ----------------
        ListView {
            id: deviceList

            Layout.preferredWidth: contentRow.rightWidth
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: Math.min(contentHeight, contentRow.listMaxHeight)
            clip: true
            spacing: Config.scaled(8, root.uiScale)
            boundsBehavior: Flickable.StopAtBounds

            model: root.deviceEntries

            delegate: Item {
                id: entryItem

                required property var modelData

                width: deviceList.width
                height: modelData.kind === "device" ? contentRow.cardHeight
                    : modelData.kind === "separator" ? Config.scaled(2, root.uiScale)
                    : headerText.implicitHeight

                Text {
                    id: headerText
                    visible: entryItem.modelData.kind === "header"
                    text: entryItem.modelData.kind === "header" ? entryItem.modelData.label : ""
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                Rectangle {
                    visible: entryItem.modelData.kind === "separator"
                    anchors.fill: parent
                    color: Config.fgcolordark
                }

                // Guarded by a Loader (not just visible: false) - a
                // BluetoothDeviceCard instantiated for a header/separator
                // row would dereference a null device the instant its
                // bindings evaluate, regardless of visibility.
                Loader {
                    anchors.fill: parent
                    active: entryItem.modelData.kind === "device"

                    BluetoothDeviceCard {
                        uiScale: root.uiScale
                        device: entryItem.modelData.device
                    }
                }

                // Dialog box (PIN/password prompts) will go here once a
                // pairing agent exists - see the file-level note above.
            }
        }
    }
}

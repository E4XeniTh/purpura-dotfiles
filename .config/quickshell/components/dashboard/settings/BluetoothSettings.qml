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

    // Auto-trust the instant a device becomes paired, so it can
    // reconnect later without prompting. Lives here (keyed on the
    // device objects themselves via Bluetooth.devices.values, which
    // doesn't change identity when a device's paired state flips)
    // rather than inside each row's BluetoothDeviceCard - that card
    // gets destroyed and recreated the moment a device moves between
    // the "Paired"/"Unpaired" sections of deviceEntries above, which is
    // the exact same paired-state change this needs to react to, so a
    // Connections binding living there could get torn down before (or
    // race) its own handler running.
    Repeater {
        model: ScriptModel { values: Bluetooth.devices.values }

        delegate: Item {
            required property var modelData

            Connections {
                target: modelData

                function onPairedChanged() {
                    if (modelData.paired) {
                        modelData.trusted = true
                    }
                }
            }
        }
    }

    // Scan for nearby devices only while this panel is open. Skips any
    // adapter blocked by rfkill entirely - StartDiscovery on a blocked
    // adapter is rejected by BlueZ ("Resource Not Ready"), so trying it
    // there was pure noise (a critical log line every time the panel
    // opened, for an adapter that can never discover until unblocked).
    onActiveChanged: {
        const adapters = Bluetooth.adapters.values
        for (let i = 0; i < adapters.length; i++) {
            if (adapters[i].state !== BluetoothAdapterState.Blocked) {
                adapters[i].discovering = root.active
            }
        }
    }

    // SettingsPanel sizes itself off this outer Item's height via
    // childrenRect, which only reliably tracks plain Column/Row
    // positioners - contentRow below is a RowLayout, and Layout types'
    // settled size lives in their own implicitHeight, not in a generic
    // childrenRect measurement of their children. Binding this wrapper's
    // height explicitly to the tallest side (plus real top+bottom
    // padding, which contentRow never had before) is what the panel
    // actually measures now.
    Item {
        id: contentWrapper

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: contentRow.margins * 2 + Math.max(leftColumn.implicitHeight, deviceList.height)

        RowLayout {
            id: contentRow

            readonly property real margins: Config.scaled(18, root.uiScale)

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: contentRow.margins
            }
            spacing: Config.scaled(12, root.uiScale)

            readonly property real dividerWidth: Config.scaled(2, root.uiScale)
            readonly property real availableWidth: width - spacing * 2 - dividerWidth
            readonly property real leftWidth: availableWidth * 0.325
            readonly property real rightWidth: availableWidth * 0.675
            readonly property real listMaxHeight: Config.scaled(400, root.uiScale)
            readonly property real cardHeight: Config.scaled(56, root.uiScale)

            // ---------------- LEFT: controllers ----------------
            ColumnLayout {
                id: leftColumn

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
                    }
                }
            }

            // ---------------- divider ----------------
            // Layout.fillHeight here used to depend on the RowLayout's own
            // (unreliably-tracked, see contentWrapper above) implicit height -
            // bound directly to the same explicit tallest-side expression
            // instead, so the divider always reaches exactly as far as the
            // taller of the two columns actually does.
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.preferredHeight: Math.max(leftColumn.implicitHeight, deviceList.height)
                color: Config.fgcolor
            }

            // ---------------- RIGHT: paired + unpaired devices, one list ----------------
            // Each row's delegate is a Loader picking one of three dedicated
            // Components below by kind - only the one relevant piece of
            // content is ever instantiated per row, unlike the earlier version
            // which always created all three (header Text, separator
            // Rectangle, device Loader) and just toggled visible: false on the
            // unused ones. That left a stray Config.fillcolor rectangle
            // showing on header/separator rows even after disabling ListView's
            // delegate reuse, so the actual bug wasn't reuse at all - this
            // restructure removes the always-present siblings entirely.
            ListView {
                id: deviceList

                Layout.preferredWidth: contentRow.rightWidth
                Layout.alignment: Qt.AlignTop
                Layout.preferredHeight: Math.min(contentHeight, contentRow.listMaxHeight)
                clip: true
                spacing: Config.scaled(8, root.uiScale)
                boundsBehavior: Flickable.StopAtBounds
                model: root.deviceEntries

                delegate: Loader {
                    id: entryLoader

                    required property var modelData

                    width: deviceList.width
                    height: modelData.kind === "device" ? contentRow.cardHeight
                        : modelData.kind === "separator" ? Config.scaled(2, root.uiScale)
                        : Config.scaled(20, root.uiScale)

                    sourceComponent: modelData.kind === "device" ? deviceRowComponent
                        : modelData.kind === "separator" ? separatorRowComponent
                        : headerRowComponent
                }
            }

            // These reference `parent` (the Loader that instantiated them, per
            // Loader's own reparenting behavior) rather than `entryLoader` by
            // id - a shared Component declared outside a per-row delegate
            // doesn't get that delegate's own isolated id scope, so
            // `entryLoader.modelData` here would either fail to resolve or
            // resolve to the wrong row's Loader entirely.
            Component {
                id: headerRowComponent

                Text {
                    text: parent.modelData.label
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }
            }

            Component {
                id: separatorRowComponent

                Rectangle {
                    anchors.fill: parent
                    color: Config.fgcolor
                }
            }

            Component {
                id: deviceRowComponent

                BluetoothDeviceCard {
                    anchors.fill: parent
                    uiScale: root.uiScale
                    device: parent.modelData.device
                }
            }

            // Dialog box (PIN/password prompts) will go here once a pairing
            // agent exists - see the file-level note above.
        }
    }
}

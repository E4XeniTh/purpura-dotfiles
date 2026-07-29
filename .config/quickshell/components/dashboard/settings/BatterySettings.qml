import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Qt5Compat.GraphicalEffects
import "../"
import "../../"
import "../../../Config.js" as Config

// Battery levels list, opened from Dashboard's battery icon. Sections
// in one scrollable list, each separated by a divider, in order: the
// system/laptop battery (hidden entirely on a desktop with no real
// battery - see hasSystemBattery), Solaar-managed Logitech peripherals
// (devices only, never the USB receiver itself; see Dashboard.qml,
// which owns the actual `solaar show` polling and is entirely inert
// when Config.solaarEnabled is false), then everything else with a
// battery UPower or BlueZ know about - Bluetooth devices via BlueZ's
// own Battery1 interface, plus controllers/phones/etc. via UPower's
// device list (upowerBatteryDevices below), which also covers Logitech
// peripherals UPower can see independently of Solaar - those are
// excluded outright while Solaar integration is enabled, since Solaar's
// own entries above already cover the same physical devices with a
// properly-parsed charging state. Every row's icon is a plain
// battery-level icon (Config.batteryIconName - "battery-NNN[-charging]",
// bucketed in 10% increments), not a device-type icon - most of these
// devices have nothing else to show one against anyway.
SettingsPanel {
    id: root

    namespaceName: "batterySettings"

    // Dashboard.qml's shared root Scope - owns the actual Solaar
    // Process/Timer (see there for why: one shared poll instead of one
    // per screen's own panel instance, and started at Quickshell init
    // rather than waiting for this panel to ever be opened).
    property var dashboardRoot: null

    readonly property var systemDevice: UPower.displayDevice
    readonly property bool hasSystemBattery: !!(root.systemDevice && root.systemDevice.ready && root.systemDevice.isLaptopBattery)
    readonly property bool systemCharging: root.hasSystemBattery
        ? (root.systemDevice.state === UPowerDeviceState.Charging || root.systemDevice.state === UPowerDeviceState.PendingCharge)
        : false

    readonly property var solaarDevices: root.dashboardRoot ? root.dashboardRoot.solaarDevices : []

    // ---------------- Bluetooth device batteries ----------------
    // BlueZ's Battery1 interface, already exposed directly by
    // Quickshell's own Bluetooth module (batteryAvailable/battery) -
    // no CLI parsing needed here, unlike Solaar. Connected only - a
    // paired-but-disconnected device has no live battery reading to
    // show.
    readonly property var bluetoothBatteryDevices: Bluetooth.devices.values.filter(d => d.connected && d.batteryAvailable)

    // ---------------- UPower device batteries (controllers, phones, etc.) ----------------
    // UPower.devices is built from the UPower daemon's own
    // EnumerateDevices() call, which structurally excludes the
    // synthetic DisplayDevice aggregate (that's fetched separately, via
    // UPower.displayDevice above) - nativePath.length > 0 is a
    // defensive backstop for that in case some UPower version behaves
    // differently, not the primary filter. Logitech's own
    // hidpp_battery_* entries are excluded outright while Solaar
    // integration is enabled - UPower tracks those independently of
    // Solaar, so without this they'd show up twice for the exact same
    // physical peripheral.
    readonly property var upowerBatteryDevices: UPower.devices.values.filter(d =>
        d.ready && d.nativePath.length > 0 &&
        !(Config.solaarEnabled && d.nativePath.startsWith("hidpp_battery")))

    onActiveChanged: {
        if (active && root.dashboardRoot) root.dashboardRoot.refreshSolaar()
    }

    // Single combined list - kind distinguishes what each row renders,
    // same "kind"-tagged-model approach BluetoothSettings.qml/
    // NetworkSettings.qml already use for their own mixed lists. The
    // separator between the Solaar and Bluetooth/UPower sections is
    // unconditional (mirrors the system section's own separator above),
    // regardless of whether either section actually has any rows.
    readonly property var batteryEntries: {
        const list = []
        if (root.hasSystemBattery) {
            list.push({ kind: "system", name: "System", percentage: root.systemDevice.percentage, charging: root.systemCharging })
            list.push({ kind: "separator" })
        }
        for (const d of root.solaarDevices) {
            list.push({ kind: "device", name: d.name, percentage: d.percentage, charging: d.charging })
        }
        list.push({ kind: "separator" })
        for (const d of root.bluetoothBatteryDevices) {
            list.push({ kind: "device", name: d.name, percentage: d.battery, charging: false })
        }
        // Deduped by name against the Bluetooth entries just added -
        // BlueZ and UPower can both end up tracking the same physical
        // device (e.g. a phone) independently.
        const usedNames = new Set(root.bluetoothBatteryDevices.map(d => d.name.toLowerCase()))
        for (const d of root.upowerBatteryDevices) {
            if (usedNames.has(d.model.toLowerCase())) continue
            list.push({
                kind: "device",
                name: d.model,
                percentage: d.percentage,
                charging: d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.PendingCharge
            })
        }
        return list
    }

    // batteryEntries always has at least the two separators, even with
    // nothing to actually show either side of them - this is what the
    // empty-state message/list visibility below actually check instead,
    // so a completely empty machine doesn't render two lone dividers
    // with nothing between them.
    readonly property bool hasAnyBattery: root.hasSystemBattery || root.solaarDevices.length > 0
        || root.bluetoothBatteryDevices.length > 0 || root.upowerBatteryDevices.length > 0

    Column {
        id: batteryContent

        width: root.panelWidth

        topPadding: Config.scaled(16, root.uiScale)
        bottomPadding: Config.scaled(16, root.uiScale)
        leftPadding: Config.scaled(16, root.uiScale)
        rightPadding: Config.scaled(16, root.uiScale)
        spacing: Config.scaled(10, root.uiScale)

        readonly property real contentWidth: width - leftPadding - rightPadding
        readonly property real rowHeight: Config.scaled(40, root.uiScale)
        // Same cap as Audio/Bluetooth/Network/Screen Settings' own
        // lists - keeps this panel from growing without bound with a
        // lot of peripherals connected.
        readonly property real listMaxHeight: Config.scaled(400, root.uiScale)

        Text {
            visible: root.hasAnyBattery
            text: "Battery"
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(14, root.uiScale)
            font.bold: true
        }

        // Same fixed-height empty-state swap BluetoothSettings.qml uses
        // for "No Bluetooth receiver detected." - a plain centered
        // message in a reserved-height box instead of the title +
        // (now-empty) list.
        Item {
            visible: !root.hasAnyBattery
            width: batteryContent.contentWidth
            height: Config.scaled(200, root.uiScale)

            Text {
                anchors.centerIn: parent
                text: "No Internal/External battery detected."
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(16, root.uiScale)
                font.bold: true
            }
        }

        ListView {
            width: batteryContent.contentWidth
            height: Math.min(contentHeight, batteryContent.listMaxHeight)
            visible: root.hasAnyBattery
            clip: true
            spacing: Config.scaled(8, root.uiScale)
            boundsBehavior: Flickable.StopAtBounds
            model: root.batteryEntries

            delegate: Item {
                required property var modelData

                width: batteryContent.contentWidth
                height: modelData.kind === "separator" ? Config.scaled(2, root.uiScale) : batteryContent.rowHeight

                Rectangle {
                    visible: parent.modelData.kind === "separator"
                    anchors.fill: parent
                    color: Config.fgcolor
                }

                RowLayout {
                    visible: parent.modelData.kind !== "separator"
                    anchors.fill: parent
                    spacing: Config.scaled(10, root.uiScale)

                    // Fixed-size icon instead of a width fraction of the
                    // row - same reasoning ControllerCard.qml/
                    // AudioSettings' own hint icons use.
                    Item {
                        Layout.preferredWidth: Config.scaled(24, root.uiScale)
                        Layout.preferredHeight: Config.scaled(24, root.uiScale)

                        IconImage {
                            id: rowIcon
                            anchors.fill: parent
                            // Same battery-NNN[-charging] icon scheme
                            // BatteryControl.qml's bar widget uses -
                            // Solaar/Bluetooth devices have no icon of
                            // their own to fall back on the way UPower
                            // provides one for the system battery, so
                            // this is the one scheme that covers all
                            // three sections uniformly.
                            source: Quickshell.iconPath(
                                Config.batteryIconName(modelData.percentage * 100, modelData.charging),
                                "battery-missing-symbolic")
                        }

                        ColorOverlay {
                            anchors.fill: rowIcon
                            source: rowIcon
                            color: Config.fgcolor
                        }
                    }

                    // Wider than the bar widgets' own compact labels -
                    // full device names (e.g. "G703 LIGHTSPEED Wireless
                    // Gaming Mouse w/ HERO") need the room, at the
                    // bar's expense (see DigitalBar below, which simply
                    // fills whatever's left in this RowLayout).
                    Text {
                        Layout.preferredWidth: Config.scaled(170, root.uiScale)
                        text: modelData.name + ":"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // The "long" bar - fills whatever space is left
                    // between the label and the percentage instead of
                    // the compact bar widgets' own fixed segment count/
                    // width (see DigitalBar.qml's targetWidth). Red
                    // below 11% (and not charging - a device that's
                    // just started charging while still low isn't in
                    // the same kind of trouble), otherwise a slow
                    // breathe between fgcolor/fgcolorlight while
                    // actually charging.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: bar.implicitHeight

                        DigitalBar {
                            id: bar
                            uiScale: root.uiScale
                            targetWidth: parent.width
                            segmentCount: 28
                            value: modelData.percentage
                            litColor: modelData.percentage < 0.11 && !modelData.charging
                                ? Config.fgcolorred
                                : (modelData.charging ? chargingBlink.color : Config.fgcolor)
                        }

                        Item {
                            id: chargingBlink
                            property color color: Config.fgcolor

                            SequentialAnimation on color {
                                running: modelData.charging
                                loops: Animation.Infinite
                                ColorAnimation { to: Config.fgcolorlight; duration: 1800 }
                                ColorAnimation { to: Config.fgcolor; duration: 1800 }
                            }
                        }
                    }

                    Text {
                        Layout.preferredWidth: Config.scaled(40, root.uiScale)
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(modelData.percentage * 100) + "%"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }
                }
            }
        }
    }
}

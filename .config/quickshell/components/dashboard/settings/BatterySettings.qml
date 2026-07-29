import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import "../"
import "../../"
import "../../../Config.js" as Config

// Battery levels list, opened from Dashboard's battery icon. Three
// sections in one scrollable list, each separated by a divider, in
// order: the system/laptop battery (hidden entirely on a desktop with
// no real battery - see hasSystemBattery), Solaar-managed Logitech
// peripherals (devices only, never the USB receiver itself - receivers
// have no battery of their own to report; skipped entirely if solaar
// isn't installed/running), then connected Bluetooth devices that
// report one (BlueZ's Battery1 interface, already exposed directly as
// BluetoothDevice.battery/.batteryAvailable - no extra plumbing needed,
// unlike Solaar). Every row's icon is a plain battery-level icon
// (Config.batteryIconName - "battery-NNN[-charging]", bucketed in 10%
// increments), not a device-type icon - Solaar/Bluetooth devices have
// nothing else to show one against anyway.
SettingsPanel {
    id: root

    namespaceName: "batterySettings"

    readonly property var systemDevice: UPower.displayDevice
    readonly property bool hasSystemBattery: !!(root.systemDevice && root.systemDevice.ready && root.systemDevice.isLaptopBattery)
    readonly property bool systemCharging: root.hasSystemBattery
        ? (root.systemDevice.state === UPowerDeviceState.Charging || root.systemDevice.state === UPowerDeviceState.PendingCharge)
        : false

    // ---------------- Solaar (Logitech Unifying/Bolt peripherals) ----------------
    // Best-effort text parsing of `solaar show`'s default (human-
    // readable, no stable JSON output as of writing) dump. Two header
    // shapes exist and both need handling: a receiver-paired peripheral
    // is indented exactly 2 spaces as "N: Name" (e.g. "  1: G703
    // LIGHTSPEED..."), while a standalone peripheral (no receiver - a
    // Bluetooth/USB-wired device like a headset) or a receiver itself
    // is a bare, unindented name line at column 0 (e.g. "PRO X TKL",
    // "Lightspeed Receiver"). A receiver's own block never contains a
    // "Battery:" line (only "Has N paired device(s)..."), so treating
    // its name the same as a real device's is harmless - it just gets
    // silently overwritten by the next real header before any battery
    // match ever fires for it, without needing to special-case
    // receivers vs. devices at all.
    //
    // Deeper "N: ..." lines also exist further down in a real device's
    // own block (HID++ feature listings, per-effect tables) - those are
    // indented well past 2 spaces, so anchoring the receiver-paired
    // pattern to *exactly* 2 leading spaces is what keeps this from
    // misreading one of those as a new device header mid-block.
    //
    // Some HID++ features (e.g. ADC MEASUREMENT) also print their own
    // nested "Battery: ..." reading before the block's real summary
    // line at the end - pendingName is cleared the moment a match is
    // found so a second one for the same device doesn't push a
    // duplicate entry.
    //
    // If solaar isn't installed or isn't running, this command fails
    // and solaarDevices simply stays empty, which already hides the
    // section entirely (there's no separate header to hide alongside
    // it). Flag if a solaar version ever changes this format.
    property var solaarDevices: []

    function refreshSolaar() {
        solaarProcess.running = false
        solaarProcess.running = true
    }

    Process {
        id: solaarProcess
        command: ["solaar", "show"]

        stdout: StdioCollector {
            onStreamFinished: {
                const devices = []
                let pendingName = null
                for (const rawLine of text.split("\n")) {
                    const pairedMatch = rawLine.match(/^ {2}(\d+):\s+(.+?)\s*$/)
                    if (pairedMatch) {
                        pendingName = pairedMatch[2]
                        continue
                    }

                    if (/^\S/.test(rawLine) && !/^(solaar version|solaar show|rules cannot access)/i.test(rawLine)) {
                        pendingName = rawLine.trim()
                        continue
                    }

                    if (!pendingName) continue

                    // BatteryStatus suffix (DISCHARGING/FULL/RECHARGING/...)
                    // is optional here in case a future solaar version
                    // drops it - percentage alone is still useful.
                    const battMatch = rawLine.match(/Battery:\s*(\d+)%(?:.*?BatteryStatus\.(\w+))?/)
                    if (battMatch) {
                        const status = battMatch[2] ?? ""
                        devices.push({
                            name: pendingName,
                            percentage: parseInt(battMatch[1], 10) / 100,
                            charging: /RECHARG/.test(status) || status === "ALMOST_FULL"
                        })
                        pendingName = null
                    }
                }
                root.solaarDevices = devices
            }
        }
    }

    // Polled while this panel is open - solaar has no live change
    // notification this shell can subscribe to, only a point-in-time CLI
    // dump. A full `solaar show` walks every HID++ feature on every
    // paired peripheral (seconds, not milliseconds), so this is
    // deliberately slow (4.5 minutes) rather than the few-seconds
    // interval other panels poll at.
    Timer {
        id: solaarRefreshTimer
        interval: 270000
        repeat: true
        onTriggered: root.refreshSolaar()
    }

    // ---------------- Bluetooth device batteries ----------------
    // BlueZ's Battery1 interface, already exposed directly by
    // Quickshell's own Bluetooth module (batteryAvailable/battery) -
    // no CLI parsing needed here, unlike Solaar. Connected only - a
    // paired-but-disconnected device has no live battery reading to
    // show.
    readonly property var bluetoothBatteryDevices: Bluetooth.devices.values.filter(d => d.connected && d.batteryAvailable)

    onActiveChanged: {
        if (active) {
            root.refreshSolaar()
            solaarRefreshTimer.restart()
        } else {
            solaarRefreshTimer.stop()
        }
    }

    // Single combined list - kind distinguishes what each row renders,
    // same "kind"-tagged-model approach BluetoothSettings.qml/
    // NetworkSettings.qml already use for their own mixed lists. The
    // separator between the Solaar and Bluetooth sections is
    // unconditional (mirrors the system section's own separator above),
    // regardless of whether either section actually has any rows.
    readonly property var batteryEntries: {
        const list = []
        if (root.hasSystemBattery) {
            list.push({ kind: "system" })
            list.push({ kind: "separator" })
        }
        for (const d of root.solaarDevices) {
            list.push({ kind: "device", name: d.name, percentage: d.percentage, charging: d.charging })
        }
        list.push({ kind: "separator" })
        for (const d of root.bluetoothBatteryDevices) {
            list.push({ kind: "device", name: d.name, percentage: d.battery, charging: false })
        }
        return list
    }

    // batteryEntries always has at least the two separators, even with
    // nothing to actually show either side of them - this is what the
    // empty-state message/list visibility below actually check instead,
    // so a completely empty machine doesn't render two lone dividers
    // with nothing between them.
    readonly property bool hasAnyBattery: root.hasSystemBattery || root.solaarDevices.length > 0 || root.bluetoothBatteryDevices.length > 0

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
                                Config.batteryIconName(
                                    (modelData.kind === "system" ? root.systemDevice.percentage : modelData.percentage) * 100,
                                    modelData.kind === "system" ? root.systemCharging : modelData.charging),
                                "battery-missing-symbolic")
                        }

                        ColorOverlay {
                            anchors.fill: rowIcon
                            source: rowIcon
                            color: Config.fgcolor
                        }
                    }

                    Text {
                        Layout.preferredWidth: Config.scaled(120, root.uiScale)
                        text: (modelData.kind === "system" ? "System" : modelData.name) + ":"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // The "long" bar - fills whatever space is left
                    // between the label and the percentage instead of
                    // the compact bar widgets' own fixed segment count/
                    // width (see DigitalBar.qml's targetWidth).
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: bar.implicitHeight

                        DigitalBar {
                            id: bar
                            uiScale: root.uiScale
                            targetWidth: parent.width
                            segmentCount: 28
                            value: modelData.kind === "system" ? root.systemDevice.percentage : modelData.percentage
                            litColor: (modelData.kind === "system" && root.systemCharging) ? Config.fgcolorlight : Config.fgcolor
                        }
                    }

                    Text {
                        Layout.preferredWidth: Config.scaled(40, root.uiScale)
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((modelData.kind === "system" ? root.systemDevice.percentage : modelData.percentage) * 100) + "%"
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

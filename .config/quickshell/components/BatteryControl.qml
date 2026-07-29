import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Bar widget: battery icon + a horizontal "digital"/segmented level bar
// (DigitalBar.qml, same style VolumeControl.qml uses) + a percentage
// readout. Read-only - unlike VolumeControl.qml there's nothing here to
// drag/scroll/click, it's purely a status indicator. Hidden entirely
// (see visible below) on a desktop with no real system battery -
// isLaptopBattery is Quickshell's own "this is a real, valid battery"
// check (type == Battery && powerSupply == true), not just "some
// UPower device happens to exist".
Rectangle {
    id: root

    property real uiScale: 1.0

    readonly property var device: UPower.displayDevice
    readonly property bool isLaptop: !!(root.device && root.device.ready && root.device.isLaptopBattery)
    readonly property real percentage: root.device ? root.device.percentage : 0
    readonly property bool charging: root.device
        ? (root.device.state === UPowerDeviceState.Charging || root.device.state === UPowerDeviceState.PendingCharge)
        : false

    visible: root.isLaptop
    // A hidden Rectangle would otherwise still occupy its own reserved
    // space in Bar.qml's Row-anchored layout - collapsed to nothing so
    // neighboring widgets close the gap instead of leaving a blank slot
    // on desktops.
    width: visible ? implicitWidth : 0
    height: visible ? implicitHeight : 0

    color: "transparent"
    border.width: Config.scaled(2, root.uiScale)
    border.color: Config.fgcolor
    radius: 0

    implicitHeight: Config.scaled(34, root.uiScale)
    implicitWidth: content.implicitWidth + Config.scaled(20, root.uiScale)

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Config.scaled(8, root.uiScale)

        Item {
            width: Config.scaled(20, root.uiScale)
            height: Config.scaled(20, root.uiScale)
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
                id: battIcon
                anchors.fill: parent
                // Config.batteryIconName buckets in 10% increments
                // (battery-000 .. battery-100, "-charging" suffixed) -
                // same scheme BatterySettings.qml uses for Solaar/
                // Bluetooth devices, which UPower has no icon for at all.
                source: Quickshell.iconPath(
                    Config.batteryIconName(root.percentage * 100, root.charging),
                    "battery-missing-symbolic")
            }

            ColorOverlay {
                anchors.fill: battIcon
                source: battIcon
                color: Config.fgcolor
            }
        }

        Item {
            id: barBox
            width: bar.implicitWidth
            height: bar.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            // No anchors/explicit size on bar itself - see
            // VolumeControl.qml's identical segmentsBox for why that'd
            // be a binding cycle.
            DigitalBar {
                id: bar
                uiScale: root.uiScale
                value: root.percentage
                segmentCount: 18
                litColor: root.charging ? Config.fgcolorlight : Config.fgcolor
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.percentage * 100) + "%"
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Networking
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// Network devices/connections/wifi, opened from Dashboard's network icon.
// One ListView whose model swaps between three tabs, picked via a
// vertical icon-tab strip on the left instead of Bluetooth's two
// side-by-side lists. Instantiated inside dashWindow (see Dashboard.qml),
// which drives `active` through its settings-panel coordinator.
//
// Backed by Quickshell.Networking (NetworkManager only) - confirmed
// against Quickshell's own source that only Wifi and Ethernet device
// types are ever surfaced by this module; other NetworkManager device
// types (tun/VPN/bridge/etc, e.g. a ZeroTier interface) are silently
// ignored at the backend level and will never appear here, regardless of
// anything done in this file.
SettingsPanel {
    id: root

    namespaceName: "networkSettings"

    // Needed for the WiFi tab's password prompt (DialogCard) to actually
    // receive keystrokes - see DialogCard.qml's own note.
    wantsKeyboardFocus: true

    // 0 = Devices, 1 = Connections, 2 = WiFi.
    property int currentTab: 0

    readonly property var wifiDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    // Whether the WiFi tab has anything usable to show - matches the
    // same nmManaged concept the Devices tab's enable/disable toggles.
    readonly property bool wifiUsable: root.wifiDevices.some(d => d.nmManaged)

    readonly property var allNetworks: {
        const list = []
        for (const dev of Networking.devices.values) {
            for (const net of dev.networks.values) {
                list.push(net)
            }
        }
        return list
    }

    readonly property var wifiNetworks: {
        const list = []
        for (const dev of root.wifiDevices) {
            for (const net of dev.networks.values) {
                list.push(net)
            }
        }
        return list
    }

    // ---------------- Devices tab ----------------
    readonly property var deviceEntries: Networking.devices.values.map(d => ({ kind: "device", device: d }))

    // ---------------- Connections tab: connected, separator, disconnected ----------------
    readonly property var connectionEntries: {
        const connected = root.allNetworks.filter(n => n.connected)
        const disconnected = root.allNetworks.filter(n => !n.connected)
        const list = connected.map(n => ({ kind: "network", network: n }))
        list.push({ kind: "separator" })
        for (const n of disconnected) list.push({ kind: "network", network: n })
        return list
    }

    // ---------------- WiFi tab: connected network on top, separator, rest by signal strength ----------------
    readonly property var wifiEntries: {
        const connected = root.wifiNetworks.filter(n => n.connected)
        const rest = root.wifiNetworks.filter(n => !n.connected)
            .slice()
            .sort((a, b) => b.signalStrength - a.signalStrength)
        const list = connected.map(n => ({ kind: "network", network: n }))
        if (connected.length > 0 && rest.length > 0) list.push({ kind: "separator" })
        for (const n of rest) list.push({ kind: "network", network: n })
        return list
    }

    readonly property var currentEntries: root.currentTab === 0 ? root.deviceEntries
        : root.currentTab === 1 ? root.connectionEntries
        : root.wifiEntries

    // Only scan (which costs power/radio time) while the WiFi tab is
    // actually the one showing, same reasoning as Bluetooth's
    // `discovering` being tied to this panel's own active state.
    function updateWifiScanning() {
        const shouldScan = root.active && root.currentTab === 2
        for (const dev of root.wifiDevices) {
            dev.scannerEnabled = shouldScan
        }
    }

    onActiveChanged: root.updateWifiScanning()
    onCurrentTabChanged: root.updateWifiScanning()

    // SettingsPanel sizes itself off this outer Item's height via
    // childrenRect, which only reliably tracks plain Column/Row
    // positioners, not Layout types - see BluetoothSettings.qml for the
    // same reasoning and the anchors-vs-Layout pitfall this avoids by
    // keeping contentRow a direct, non-nested child here.
    Item {
        id: contentWrapper

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: contentRow.margins * 2 + Math.max(tabColumn.implicitHeight, listColumn.implicitHeight)
            + hintSeparator.anchors.topMargin + hintSeparator.height
            + hintRow.anchors.topMargin + hintRow.height

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

            readonly property real listMaxHeight: Config.scaled(400, root.uiScale)
            readonly property real cardHeight: Config.scaled(56, root.uiScale)

            // ---------------- LEFT: icon tabs ----------------
            ColumnLayout {
                id: tabColumn

                Layout.preferredWidth: Config.scaled(44, root.uiScale)
                Layout.alignment: Qt.AlignTop
                spacing: Config.scaled(8, root.uiScale)

                DashCard {
                    Layout.preferredWidth: Config.scaled(40, root.uiScale)
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: devicesTabMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentTab === 0 ? Config.fgcolorlight : Config.fgcolor

                    IconImage {
                        id: devicesTabIcon
                        anchors.centerIn: parent
                        implicitSize: Config.scaled(20, root.uiScale)
                        source: Quickshell.iconPath("network-workgroup-symbolic")
                    }

                    ColorOverlay {
                        anchors.fill: devicesTabIcon
                        source: devicesTabIcon
                        color: parent.border.color
                    }

                    MouseArea {
                        id: devicesTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentTab = 0
                    }
                }

                DashCard {
                    Layout.preferredWidth: Config.scaled(40, root.uiScale)
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: connectionsTabMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentTab === 1 ? Config.fgcolorlight : Config.fgcolor

                    IconImage {
                        id: connectionsTabIcon
                        anchors.centerIn: parent
                        implicitSize: Config.scaled(20, root.uiScale)
                        source: Quickshell.iconPath("network-transmit-receive-symbolic")
                    }

                    ColorOverlay {
                        anchors.fill: connectionsTabIcon
                        source: connectionsTabIcon
                        color: parent.border.color
                    }

                    MouseArea {
                        id: connectionsTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentTab = 1
                    }
                }

                DashCard {
                    Layout.preferredWidth: Config.scaled(40, root.uiScale)
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    // Grayed out and unclickable when there's no enabled
                    // wifi device to show anything for - matches the
                    // Devices tab's own enable/disable (nmManaged)
                    // concept rather than introducing a separate one.
                    color: (root.wifiUsable && wifiTabMouse.containsMouse) ? Config.fgcolorhover : Config.fillcolor
                    border.color: !root.wifiUsable ? Config.fgcolordark
                        : (root.currentTab === 2 ? Config.fgcolorlight : Config.fgcolor)

                    IconImage {
                        id: wifiTabIcon
                        anchors.centerIn: parent
                        implicitSize: Config.scaled(20, root.uiScale)
                        source: Quickshell.iconPath("network-wireless-symbolic")
                    }

                    ColorOverlay {
                        anchors.fill: wifiTabIcon
                        source: wifiTabIcon
                        color: parent.border.color
                    }

                    MouseArea {
                        id: wifiTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.wifiUsable
                        onClicked: root.currentTab = 2
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ---------------- RIGHT: current tab's list ----------------
            ColumnLayout {
                id: listColumn

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Config.scaled(8, root.uiScale)

                Text {
                    text: root.currentTab === 0 ? "Devices" : root.currentTab === 1 ? "Connections" : "WiFi"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                ListView {
                    id: entryList

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, contentRow.listMaxHeight)
                    clip: true
                    spacing: Config.scaled(8, root.uiScale)
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.currentEntries

                    delegate: Loader {
                        id: entryLoader

                        required property var modelData

                        width: entryList.width
                        height: modelData.kind === "separator" ? Config.scaled(2, root.uiScale) : contentRow.cardHeight

                        sourceComponent: modelData.kind === "device" ? deviceRowComponent
                            : modelData.kind === "network" ? networkRowComponent
                            : separatorRowComponent
                    }
                }

                // These reference `parent` (the Loader that instantiated them,
                // per Loader's own reparenting behavior) rather than
                // `entryLoader` by id - see BluetoothSettings.qml for the
                // same pattern and why.
                Component {
                    id: deviceRowComponent

                    NetworkDeviceCard {
                        anchors.fill: parent
                        uiScale: root.uiScale
                        device: parent.modelData.device
                    }
                }

                Component {
                    id: networkRowComponent

                    NetworkCard {
                        anchors.fill: parent
                        uiScale: root.uiScale
                        network: parent.modelData.network
                    }
                }

                Component {
                    id: separatorRowComponent

                    Rectangle {
                        anchors.fill: parent
                        color: Config.fgcolor
                    }
                }
            }
        }

        // ---------------- separator ----------------
        Rectangle {
            id: hintSeparator
            anchors {
                left: parent.left
                right: parent.right
                top: contentRow.bottom
                topMargin: Config.scaled(14, root.uiScale)
                margins: contentRow.margins
            }
            height: Config.scaled(2, root.uiScale)
            color: Config.fgcolor
        }

        // ---------------- hint row ----------------
        RowLayout {
            id: hintRow

            anchors {
                left: parent.left
                right: parent.right
                top: hintSeparator.bottom
                topMargin: Config.scaled(10, root.uiScale)
                margins: contentRow.margins
            }
            spacing: Config.scaled(16, root.uiScale)

            HintItem {
                uiScale: root.uiScale
                visible: root.currentTab === 0
                iconSource: Quickshell.iconPath("input-mouse-click-right-symbolic")
                label: "Enable/Disable"
            }

            HintItem {
                uiScale: root.uiScale
                visible: root.currentTab !== 0
                iconSource: Quickshell.iconPath("input-mouse-click-left-symbolic")
                label: "Connect/Disconnect"
            }

            Item { Layout.fillWidth: true }
        }
    }
}

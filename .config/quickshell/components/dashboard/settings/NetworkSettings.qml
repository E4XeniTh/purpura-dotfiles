import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Networking
import Quickshell.Io
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
// anything done in this file. The Connections tab below works around
// that for a few specific cases (Bluetooth tethering, USB tethering,
// ZeroTier) by separately parsing plain `nmcli`'s own device dump -
// see nmcliBlocks/extraConnectionEntries/etherOverrides.
SettingsPanel {
    id: root

    namespaceName: "networkSettings"

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

    // ---------------- Connections tab: wired only, connected/disconnected (no separator) ----------------
    // Wireless networks have their own dedicated WiFi tab, so they're
    // excluded here rather than duplicated in both places.
    readonly property var wiredNetworks: root.allNetworks.filter(n => !(n.device && n.device.type === DeviceType.Wifi))

    // ---------------- nmcli device dump (Bluetooth/USB tethering, ZeroTier, etc.) ----------------
    // Plain `nmcli` (no args) prints one block per device it knows
    // about, in a fixed shape regardless of device type, e.g.:
    //
    //   enp14s0u3: disconnected
    //
    //           "Samsung Galaxy series misc."
    //
    //           1 connection available
    //
    //           ethernet (rndis_host), 2E:35:19:35:D6:6E, autoconnect, hw, mtu 1500
    //
    // Unlike Quickshell.Networking, NetworkManager (and therefore
    // nmcli) is aware of every device on the system, managed or not - a
    // live nmcli dump showed a ZeroTier zt* interface listed here (as
    // "unmanaged") even though nothing in this shell ever asked
    // NetworkManager to manage it. Refreshed only while this panel is
    // open (see onActiveChanged/nmcliRefreshTimer below), since none of
    // this is reactive the way Networking.devices is.
    property var nmcliBlocks: []

    function refreshNmcli() {
        nmcliDumpProcess.running = false
        nmcliDumpProcess.running = true
    }

    Process {
        id: nmcliDumpProcess
        command: ["nmcli"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.nmcliBlocks = root.parseNmcliDump(text)
            }
        }
    }

    Timer {
        id: nmcliRefreshTimer
        interval: 4000
        repeat: true
        onTriggered: root.refreshNmcli()
    }

    // Splits nmcli's block-per-device dump into { id, state, name,
    // typeLine } objects. Header lines (device id/MAC + state) are
    // never indented; every other non-blank line in a block is. The
    // header's own id/state split uses ": " (colon-space) rather than
    // a plain colon split, since a Bluetooth device's id is itself a
    // colon-separated MAC address - only the real id/state boundary
    // has a space after its colon.
    function parseNmcliDump(text) {
        const blocks = []
        let current = null

        for (const rawLine of text.split("\n")) {
            if (rawLine.trim().length === 0) continue

            if (!/^\s/.test(rawLine)) {
                const sepIdx = rawLine.lastIndexOf(": ")
                if (sepIdx === -1) { current = null; continue }
                current = {
                    id: rawLine.slice(0, sepIdx).trim(),
                    state: rawLine.slice(sepIdx + 2).trim(),
                    name: "",
                    typeLine: ""
                }
                blocks.push(current)
                continue
            }

            if (!current) continue
            const trimmed = rawLine.trim()
            if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
                current.name = trimmed.slice(1, -1)
            } else if (/^\d+\s+connections?\s+available$/i.test(trimmed)) {
                // Just a count, nothing worth keeping.
            } else {
                current.typeLine = trimmed
            }
        }

        return blocks
    }

    // typeLine looks like "bt (bluez), MAC, hw" or plain "tun, MAC, sw,
    // mtu 2800" (no driver in parens) - only the leading type token and
    // optional driver are needed here.
    function nmcliTypeInfo(block) {
        const m = block.typeLine.match(/^(\S+)(?:\s*\(([^)]*)\))?/)
        return {
            baseType: m ? m[1].toLowerCase() : "",
            driver: (m && m[2]) ? m[2].toLowerCase() : ""
        }
    }

    // Common Linux driver names for a phone's USB-tethered "ethernet"
    // interface (Android's rndis_host, iOS's ipheth, etc.) - matched
    // against so a tethered phone doesn't look identical to a real
    // wired NIC in this tab.
    readonly property var usbTetherDrivers: ["rndis_host", "rndis", "cdc_ether", "cdc_ncm", "cdc_acm", "usbnet", "ipheth"]

    // Interface name -> { label, icon }, only for nmcli's "ethernet"
    // blocks whose driver matches usbTetherDrivers - these interfaces
    // already appear via Quickshell.Networking's own wiredNetworks
    // (Ethernet is a supported device type there), so this only
    // relabels/re-icons the existing entry rather than duplicating it.
    readonly property var etherOverrides: {
        const map = {}
        for (const block of root.nmcliBlocks) {
            const info = root.nmcliTypeInfo(block)
            if (info.baseType !== "ethernet") continue
            if (root.usbTetherDrivers.indexOf(info.driver) === -1) continue
            map[block.id] = { label: "USB Tether", icon: "drive-harddisk-usb-symbolic" }
        }
        return map
    }

    function wiredSecondaryLabel(n) {
        const override = (n.device && root.etherOverrides[n.device.name]) ? root.etherOverrides[n.device.name] : null
        return override ? override.label : "Wired"
    }

    function wiredIconOverride(n) {
        const override = (n.device && root.etherOverrides[n.device.name]) ? root.etherOverrides[n.device.name] : null
        return override ? override.icon : ""
    }

    // Every nmcli block Quickshell.Networking will never surface on
    // its own - anything that isn't wifi (own tab), ethernet (already
    // covered above, whether tethered or not) or loopback. Read-only:
    // there's no Network object here to call .connect()/.forget() on,
    // just what nmcli reported this refresh.
    readonly property var extraConnectionEntries: {
        const skip = { wifi: true, ethernet: true, loopback: true }
        const list = []

        for (const block of root.nmcliBlocks) {
            const info = root.nmcliTypeInfo(block)
            if (!info.baseType || skip[info.baseType]) continue

            let label = info.baseType.charAt(0).toUpperCase() + info.baseType.slice(1)
            let icon = "network-wired-symbolic"

            if (info.baseType === "bt") {
                label = "BT Tether"
                icon = "bluetooth-symbolic"
            } else if (info.baseType === "tun") {
                icon = "network-vpn-symbolic"
                // ZeroTier's own interface naming convention: "zt"
                // followed by its 10-hex-digit network address, e.g.
                // "zthnhadv3s" - any other tun interface (a VPN client
                // not otherwise identified) just gets a generic label.
                label = /^zt[0-9a-f]+$/i.test(block.id) ? "ZeroTier" : "Tunnel"
            }

            list.push({
                kind: "extra",
                displayName: block.name.length > 0 ? block.name : block.id,
                secondaryLabel: label,
                icon: icon,
                connected: block.state === "connected"
            })
        }

        return list
    }

    readonly property var connectionEntries: {
        const connected = root.wiredNetworks.filter(n => n.connected)
        const disconnected = root.wiredNetworks.filter(n => !n.connected)
        const list = connected.map(n => ({
            kind: "network",
            network: n,
            secondaryLabel: root.wiredSecondaryLabel(n),
            iconOverride: root.wiredIconOverride(n)
        }))
        for (const n of disconnected) list.push({
            kind: "network",
            network: n,
            secondaryLabel: root.wiredSecondaryLabel(n),
            iconOverride: root.wiredIconOverride(n)
        })
        return list.concat(root.extraConnectionEntries)
    }

    // ---------------- WiFi tab: connected + remembered on top, separator, then found networks ----------------
    readonly property var wifiEntries: {
        const connected = root.wifiNetworks.filter(n => n.connected)
        const remembered = root.wifiNetworks.filter(n => !n.connected && n.known)
            .slice()
            .sort((a, b) => b.signalStrength - a.signalStrength)
        const found = root.wifiNetworks.filter(n => !n.connected && !n.known)
            .slice()
            .sort((a, b) => b.signalStrength - a.signalStrength)
        const list = connected.map(n => ({ kind: "network", network: n }))
        for (const n of remembered) list.push({ kind: "network", network: n })
        if ((connected.length > 0 || remembered.length > 0) && found.length > 0) list.push({ kind: "separator" })
        for (const n of found) list.push({ kind: "network", network: n })
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

    onActiveChanged: {
        root.updateWifiScanning()
        if (root.active) {
            root.refreshNmcli()
            nmcliRefreshTimer.restart()
        } else {
            nmcliRefreshTimer.stop()
        }
    }
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
        height: Math.max(
            Config.scaled(300, root.uiScale),
            contentRow.margins * 2 + Math.max(tabColumn.implicitHeight, listColumn.implicitHeight))

        RowLayout {
            id: contentRow
            readonly property real margins: Config.scaled(18, root.uiScale)

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                margins: contentRow.margins
            }
            spacing: Config.scaled(12, root.uiScale)

            readonly property real listMaxHeight: Config.scaled(400, root.uiScale)
            readonly property real cardHeight: Config.scaled(56, root.uiScale)
            readonly property real dividerWidth: Config.scaled(2, root.uiScale)

            // ---------------- LEFT: icon tabs ----------------
            ColumnLayout {
                id: tabColumn

                // Snug to the tab buttons themselves, locked to
                // min == preferred == max so it can never be squeezed (or
                // stretched) by the list column's own content.
                readonly property real contentWidth: Config.scaled(40, root.uiScale)

                Layout.preferredWidth: tabColumn.contentWidth
                Layout.minimumWidth: tabColumn.contentWidth
                Layout.maximumWidth: tabColumn.contentWidth
                Layout.fillHeight: true
                spacing: Config.scaled(8, root.uiScale)

                DashCard {
                    Layout.preferredWidth: Config.scaled(40, root.uiScale)
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    Layout.alignment: Qt.AlignHCenter
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
                    Layout.alignment: Qt.AlignHCenter
                    uiScale: root.uiScale
                    color: connectionsTabMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentTab === 1 ? Config.fgcolorlight : Config.fgcolor

                    IconImage {
                        id: connectionsTabIcon
                        anchors.centerIn: parent
                        implicitSize: Config.scaled(20, root.uiScale)
                        // Same icon NetworkCard uses for every row this
                        // tab ever lists (root.wiredNetworks excludes
                        // Wifi devices entirely) - "network-transmit-
                        // receive-symbolic" isn't in every icon theme
                        // and was rendering as a missing-texture image
                        // instead of a blank/wrong one.
                        source: Quickshell.iconPath("network-wired-symbolic")
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
                    Layout.alignment: Qt.AlignHCenter
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

            // ---------------- divider between tabs and list ----------------
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.fillHeight: true
                color: Config.fgcolor
            }

            // ---------------- RIGHT: current tab's list ----------------
            ColumnLayout {
                id: listColumn

                Layout.fillWidth: true
                Layout.fillHeight: true
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
                            : modelData.kind === "extra" ? extraRowComponent
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
                        allowForget: root.currentTab === 2
                        secondaryLabel: parent.modelData.secondaryLabel ?? ""
                        iconOverride: parent.modelData.iconOverride ?? ""
                    }
                }

                // Connections tab only - see extraConnectionEntries.
                Component {
                    id: extraRowComponent

                    ExtraConnectionCard {
                        anchors.fill: parent
                        uiScale: root.uiScale
                        displayName: parent.modelData.displayName
                        secondaryLabel: parent.modelData.secondaryLabel
                        iconName: parent.modelData.icon
                        connected: parent.modelData.connected
                    }
                }

                Component {
                    id: separatorRowComponent

                    Rectangle {
                        anchors.fill: parent
                        color: Config.fgcolor
                    }
                }

                Item { Layout.fillHeight: true }

                // ---------------- separator ----------------
                Rectangle {
                    id: hintSeparator
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(14, root.uiScale)
                    Layout.preferredHeight: Config.scaled(2, root.uiScale)
                    color: Config.fgcolor
                }

                // ---------------- hint row ----------------
                RowLayout {
                    id: hintRow

                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(10, root.uiScale)
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

                    HintItem {
                        uiScale: root.uiScale
                        visible: root.currentTab === 2
                        iconSource: Quickshell.iconPath("input-mouse-click-right-symbolic")
                        label: "Forget"
                        tint: "red"
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}

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
// anything done in this file.
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

    // ---------------- ZeroTier (simple presence check via nmcli) ----------------
    // zerotier-cli needs root (its local API socket is root-only by
    // default on most installs) - confirmed live, so it's not something
    // this shell can just shell out to as the logged-in user. nmcli
    // works instead: NetworkManager is aware of every device on the
    // system whether or not it actually manages it, and a live nmcli
    // dump showed the zt* interface listed there (as "unmanaged") even
    // though nothing here ever asked NetworkManager to manage it. Kept
    // deliberately minimal: just "is a zt* interface present, and what
    // does nmcli say its state is" - no generic device parsing beyond
    // that (see the file-level note above for why nmcli is needed at
    // all instead of Quickshell.Networking).
    property var zerotierNetworks: []

    function refreshZerotier() {
        zerotierProcess.running = false
        zerotierProcess.running = true
    }

    Process {
        id: zerotierProcess
        command: ["nmcli"]

        // Plain `nmcli` (no args) prints one block per device it knows
        // about, e.g.:
        //
        //   zthnhadv3s: unmanaged
        //
        //           "zthnhadv3s"
        //
        //           tun, 46:F0:70:70:22:48, sw, mtu 2800
        //
        // Only the un-indented header line (id + state) is needed here
        // - ZeroTier's own interface naming convention ("zt" + a
        // generated lowercase-alphanumeric id, NOT necessarily hex -
        // "zthnhadv3s" itself has 'h'/'n' in it, which the previous
        // hex-only pattern here missed entirely, hiding it regardless
        // of managed state) is what identifies it, not nmcli's "tun"
        // type token, since any other VPN client could just as easily
        // show up as a tun device too. Deliberately not filtered by
        // state - unmanaged is the expected/common case here, not a
        // reason to hide it.
        stdout: StdioCollector {
            onStreamFinished: {
                const nets = []
                for (const rawLine of text.split("\n")) {
                    if (/^\s/.test(rawLine)) continue
                    const sepIdx = rawLine.lastIndexOf(": ")
                    if (sepIdx === -1) continue
                    const id = rawLine.slice(0, sepIdx).trim()
                    const state = rawLine.slice(sepIdx + 2).trim()
                    if (!/^zt[0-9a-z]+$/i.test(id)) continue
                    nets.push({ name: id, connected: state === "connected" })
                }
                root.zerotierNetworks = nets
            }
        }
    }

    Timer {
        id: zerotierRefreshTimer
        interval: 4000
        repeat: true
        onTriggered: root.refreshZerotier()
    }

    readonly property var connectionEntries: {
        const connected = root.wiredNetworks.filter(n => n.connected)
        const disconnected = root.wiredNetworks.filter(n => !n.connected)
        const list = connected.map(n => ({ kind: "network", network: n }))
        for (const n of disconnected) list.push({ kind: "network", network: n })
        for (const zt of root.zerotierNetworks) {
            list.push({ kind: "zerotier", name: zt.name, connected: zt.connected })
        }
        return list
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
            root.refreshZerotier()
            zerotierRefreshTimer.restart()
        } else {
            zerotierRefreshTimer.stop()
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
                            : modelData.kind === "zerotier" ? zerotierRowComponent
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
                    }
                }

                // Connections tab only - see zerotierNetworks above.
                // rowData is captured once here (rather than each
                // nested child reaching back through parent.parent...)
                // since only this root item's own `parent` is actually
                // the Loader that instantiated it.
                Component {
                    id: zerotierRowComponent

                    DashCard {
                        id: ztCard
                        anchors.fill: parent
                        uiScale: root.uiScale
                        readonly property var rowData: ztCard.parent.modelData
                        border.color: ztCard.rowData.connected ? Config.fgcolorlight : Config.fgcolor

                        RowLayout {
                            anchors {
                                fill: parent
                                margins: Config.scaled(10, root.uiScale)
                            }
                            spacing: Config.scaled(10, root.uiScale)

                            Item {
                                Layout.preferredWidth: Config.scaled(24, root.uiScale)
                                Layout.preferredHeight: Config.scaled(24, root.uiScale)

                                IconImage {
                                    id: zerotierIcon
                                    anchors.fill: parent
                                    source: Quickshell.iconPath("network-vpn-symbolic", "network-wired-symbolic")
                                }

                                ColorOverlay {
                                    anchors.fill: zerotierIcon
                                    source: zerotierIcon
                                    color: ztCard.border.color
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                // No "ZeroTier: " prefix - just the
                                // interface/network name itself, same
                                // as every other row in this list.
                                // Renaming these (they currently show
                                // nmcli's raw interface id) is a later
                                // task.
                                text: ztCard.rowData.name
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(15, root.uiScale)
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
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

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../../Config.js" as Config
import "../common"
import "cards"
import "controls"
import "ConnectionsLogic.js" as Logic

// Settings > Connections: everything this computer is connected through, as a
// directory tree, and the details of whatever's picked in it.
//
// The tree (left), a row each, top to bottom, every row indented under its
// parent and hung off a line from it, with an icon before its name: this
// computer (user@host) branches into its devices - Solaar, Wi-Fi, Bluetooth,
// ZeroTier, Ethernet - and each device into what's connected through it:
// Solaar's Logitech peripherals, Wi-Fi networks that are connected or
// remembered, paired Bluetooth devices, joined ZeroTier networks, the wired
// connection. Networks only in range, and Bluetooth devices nearby but not
// paired, are in the details panel's lists instead.
//
// A box's border says its state (ConnectionsLogic.js): fgcolor for a device
// that's on or a plain connection, fgcolorlight for a connection that's
// remembered too (disconnecting it leaves it forgettable), fgcolordark for one
// that's only remembered, red for anything disabled. Something with a battery
// - a laptop, a Solaar peripheral, a controller - has a segmented bar and its
// percentage beside its row, red when it's low.
//
// Left click picks a box for the details panel (right). Middle click renames
// it - for this shell only (AliasStore.qml, connectionaliases.json): nothing
// changes for the system, not even BlueZ's own alias. Right click disables or
// enables a device, disconnects a connection, and forgets one that's only
// remembered; a wired connection, which can't be forgotten, connects again.
//
// Backed by Quickshell.Networking (Wi-Fi and Ethernet through
// NetworkManager), Quickshell.Bluetooth (BlueZ), UPower (the laptop battery)
// and Dashboard.qml's Solaar poll. ZeroTier's interfaces come from plain
// `nmcli`, which lists them although NetworkManager doesn't manage them, and
// its service from systemctl: zerotier-cli itself needs root.
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false
    // Dashboard.qml's shared root, which polls Solaar (solaarDevices).
    property var dashboardRoot: null

    anchors.fill: parent

    AliasStore {
        id: aliasStore
        file: "connectionaliases.json"
    }

    // For the details panel's lists.
    property alias names: aliasStore

    // ---------------- this computer ----------------
    readonly property string userName: Quickshell.env("USER") || ""
    property string hostName: ""
    property string kernel: ""

    readonly property var laptopBattery: {
        const d = UPower.displayDevice
        return d && d.ready && d.isLaptopBattery ? d : null
    }
    readonly property bool laptopCharging: !!root.laptopBattery
        && (root.laptopBattery.state === UPowerDeviceState.Charging || root.laptopBattery.state === UPowerDeviceState.PendingCharge)

    Process {
        id: hostProcess
        command: ["uname", "-nr"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/)
                root.hostName = parts[0] || ""
                root.kernel = parts[1] || ""
            }
        }
    }

    // ---------------- Solaar ----------------
    readonly property var solaarDevices: root.dashboardRoot ? root.dashboardRoot.solaarDevices : []

    function refreshSolaar() {
        if (root.dashboardRoot) root.dashboardRoot.refreshSolaar()
    }

    // ---------------- ZeroTier ----------------
    property var zerotierInterfaces: []
    property var zerotierService: ({ installed: false, active: false })

    function refreshZerotier() {
        zerotierProcess.running = false
        zerotierProcess.running = true
    }

    Process {
        id: zerotierProcess
        command: ["sh", "-c", "nmcli 2>/dev/null; echo @@service; systemctl show -p LoadState -p ActiveState zerotier-one.service 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                const at = text.indexOf("@@service")
                root.zerotierInterfaces = Logic.parseZerotierInterfaces(at === -1 ? text : text.slice(0, at))
                root.zerotierService = Logic.parseServiceState(at === -1 ? "" : text.slice(at))
            }
        }
    }

    // Starting and stopping the service needs root, which systemctl asks the
    // polkit agent for - a password prompt.
    Process {
        id: zerotierToggle
        onExited: root.refreshZerotier()
    }

    function setZerotierRunning(running) {
        if (zerotierToggle.running) return
        zerotierToggle.command = ["systemctl", running ? "start" : "stop", "zerotier-one.service"]
        zerotierToggle.running = true
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.active
        onTriggered: root.refreshZerotier()
    }

    onActiveChanged: {
        if (root.active) {
            hostProcess.running = true
            root.refreshZerotier()
            root.refreshSolaar()
        }
        root.updateRadios()
    }

    // ---------------- the tree ----------------
    // A node: `key` is its place in the tree, `aliasKey` what its name is
    // kept under - the same Wi-Fi network seen by two adapters is two nodes
    // with one name.
    function makeNode(key, aliasKey, kind, systemName, ref, fields) {
        return Object.assign({
            key: key,
            aliasKey: aliasKey,
            kind: kind,
            systemName: systemName,
            name: aliasStore.name(aliasKey, systemName),
            ref: ref,
            state: "on",
            subtitle: "",
            battery: -1,
            charging: false,
            // Icon names to try, best first (ConnectionsLogic.js).
            icons: Logic.nodeIcons(kind, {}),
            children: []
        }, fields)
    }

    function percent(fraction) {
        return Math.round(fraction * 100) + "%"
    }

    function solaarNode(d, key) {
        const parts = []
        if (d.kind) parts.push(d.kind)
        parts.push(root.percent(d.percentage) + (d.charging ? " charging" : ""))
        return root.makeNode(key, "solaar:" + d.name, "solaar", d.name, d, {
            subtitle: parts.join(" · "),
            battery: d.percentage,
            charging: d.charging,
            icons: Logic.nodeIcons("solaar", { kind: d.kind })
        })
    }

    // Solaar itself, with the peripherals it sees under it.
    function solaarHubNode() {
        const children = []
        // Two peripherals of the same name still get a box each.
        const seen = {}
        for (const d of root.solaarDevices) {
            seen[d.name] = (seen[d.name] || 0) + 1
            children.push(root.solaarNode(d, "solaar:" + d.name + (seen[d.name] > 1 ? "#" + seen[d.name] : "")))
        }
        const count = root.solaarDevices.length
        const low = root.solaarDevices.filter(d => d.percentage >= 0 && Logic.batteryLow(d.percentage, d.charging)).length
        return root.makeNode("solaar", "solaar", "solaarHub", "Solaar", null, {
            subtitle: "Logitech · " + count + (count === 1 ? " device" : " devices") + (low > 0 ? " · " + low + " low" : ""),
            children: children
        })
    }

    function wifiNetworkNode(dev, n) {
        const state = Logic.wifiNetworkState({ changing: n.stateChanging, connected: n.connected, known: n.known })
        const signal = n.signalStrength > 0 ? " · " + root.percent(n.signalStrength) : ""
        const subtitle = state === "busy" ? (n.connected ? "disconnecting…" : "connecting…")
            : n.connected ? "connected" + signal
            : n.signalStrength > 0 ? "remembered" + signal
            : "remembered · out of range"
        return root.makeNode("wifi:" + dev.name + ":" + n.name, "wifi:" + n.name, "wifiNetwork", n.name, n, {
            state: state,
            subtitle: subtitle,
            device: dev,
            icons: Logic.nodeIcons("wifiNetwork", { signal: n.signalStrength })
        })
    }

    function wifiDeviceNode(dev) {
        const radioOff = Networking.wifiEnabled === false
        const switchedOff = Networking.wifiHardwareEnabled === false
        const enabled = !radioOff && !switchedOff && dev.nmManaged !== false
        const networks = Logic.sortNetworks(dev.networks.values
            .filter(n => n.connected || n.known)
            .map(n => ({ net: n, name: n.name, connected: n.connected, signal: n.signalStrength || 0 })))
            .map(e => root.wifiNetworkNode(dev, e.net))
        const current = dev.networks.values.find(n => n.connected)
        return root.makeNode("netdev:" + dev.name, "netdev:" + dev.name, "wifiDevice", dev.name, dev, {
            state: Logic.deviceState(enabled),
            subtitle: switchedOff ? "Wi-Fi · switched off"
                : radioOff ? "Wi-Fi · radio off"
                : !enabled ? "Wi-Fi · disabled"
                : current ? "Wi-Fi · " + aliasStore.name("wifi:" + current.name, current.name)
                : "Wi-Fi · not connected",
            icons: Logic.nodeIcons("wifiDevice", { off: !enabled }),
            children: networks
        })
    }

    function bluetoothDeviceNode(adapter, d) {
        const changing = d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
        const state = Logic.bluetoothDeviceState({ changing: changing, connected: d.connected, paired: d.paired })
        const battery = d.batteryAvailable ? d.battery : -1
        const systemName = d.name.length > 0 ? d.name : d.deviceName.length > 0 ? d.deviceName : d.address
        const subtitle = state === "busy" ? (d.connected ? "disconnecting…" : "connecting…")
            : d.connected ? "connected" + (battery >= 0 ? " · " + root.percent(battery) : "")
            : "remembered"
        return root.makeNode("bt:" + adapter.adapterId + ":" + d.address, "bt:" + d.address, "btDevice", systemName, d, {
            state: state,
            subtitle: subtitle,
            battery: battery,
            icons: Logic.nodeIcons("btDevice", { icon: d.icon })
        })
    }

    function adapterNode(a) {
        const blocked = a.state === BluetoothAdapterState.Blocked
        const enabled = a.enabled && !blocked
        const devices = Logic.sortDevices(a.devices.values
            .filter(d => d.paired || d.connected)
            .map(d => ({ dev: d, name: d.name || d.deviceName || d.address, connected: d.connected })))
            .map(e => root.bluetoothDeviceNode(a, e.dev))
        const connected = a.devices.values.filter(d => d.connected).length
        return root.makeNode("btadapter:" + a.adapterId, "btadapter:" + a.adapterId, "btAdapter", a.name, a, {
            state: Logic.deviceState(enabled),
            subtitle: blocked ? "Bluetooth · blocked" : !a.enabled ? "Bluetooth · off" : "Bluetooth · " + connected + " connected",
            icons: Logic.nodeIcons("btAdapter", { off: !enabled }),
            children: devices
        })
    }

    function zerotierNode() {
        // Not installed as a service but its interfaces are up: running
        // some other way.
        const running = root.zerotierService.active || (!root.zerotierService.installed && root.zerotierInterfaces.length > 0)
        return root.makeNode("zerotier", "zerotier", "ztService", "ZeroTier One", null, {
            state: Logic.deviceState(running),
            subtitle: running ? "ZeroTier · running" : "ZeroTier · stopped",
            children: root.zerotierInterfaces.map(i => root.makeNode("zt:" + i.name, "zt:" + i.name, "ztNetwork", i.name, i, {
                state: "connected",
                subtitle: "ZeroTier network"
            }))
        })
    }

    function wiredNetworkNode(dev, n) {
        const state = Logic.wiredNetworkState({ changing: n.stateChanging, connected: n.connected })
        return root.makeNode("wired:" + dev.name + ":" + n.name, "wired:" + n.name, "wiredNetwork", n.name, n, {
            state: state,
            subtitle: state === "busy" ? (n.connected ? "disconnecting…" : "connecting…") : n.connected ? "connected" : "disconnected",
            device: dev,
            icons: Logic.nodeIcons("wiredNetwork", { off: !n.connected })
        })
    }

    function wiredDeviceNode(dev) {
        const enabled = dev.nmManaged !== false
        const link = dev.hasLink === undefined ? true : dev.hasLink
        return root.makeNode("netdev:" + dev.name, "netdev:" + dev.name, "wiredDevice", dev.name, dev, {
            state: Logic.deviceState(enabled),
            subtitle: !enabled ? "Ethernet · disabled"
                : !link ? "Ethernet · cable unplugged"
                : dev.linkSpeed > 0 ? "Ethernet · " + dev.linkSpeed + " Mbit/s"
                : "Ethernet",
            icons: Logic.nodeIcons("wiredDevice", { off: !enabled, unplugged: !link }),
            children: dev.networks.values.map(n => root.wiredNetworkNode(dev, n))
        })
    }

    readonly property var treeRoot: {
        const children = []
        if (root.solaarDevices.length > 0) children.push(root.solaarHubNode())
        const devices = Networking.devices.values
        for (const dev of devices) {
            if (dev.type === DeviceType.Wifi) children.push(root.wifiDeviceNode(dev))
        }
        for (const a of Bluetooth.adapters.values) children.push(root.adapterNode(a))
        if (root.zerotierService.installed || root.zerotierInterfaces.length > 0) children.push(root.zerotierNode())
        for (const dev of devices) {
            if (dev.type === DeviceType.Wired) children.push(root.wiredDeviceNode(dev))
        }

        const battery = root.laptopBattery ? root.laptopBattery.percentage : -1
        return root.makeNode("host", "host", "host", root.userName + "@" + (root.hostName || "localhost"), null, {
            subtitle: battery >= 0 ? "battery " + root.percent(battery) + (root.laptopCharging ? " · charging" : "") : "this computer",
            battery: battery,
            charging: root.laptopCharging,
            icons: Logic.nodeIcons("host", { laptop: !!root.laptopBattery }),
            children: children
        })
    }

    // A child's trunk comes down from under its parent's icon (TreeNode.qml:
    // 10 in from the box's edge, 18 wide).
    readonly property var treeMetrics: ({
        rowHeight: Config.scaled(34, root.uiScale),
        rowGap: Config.scaled(12, root.uiScale),
        indent: Config.scaled(44, root.uiScale),
        trunkInset: Config.scaled(19, root.uiScale)
    })

    readonly property var treeLayout: Logic.layoutList(root.treeRoot, root.treeMetrics)

    // Every box ends at the same right edge, so the battery bars beside them
    // line up in a column, and the bars run on to the end of the pane with
    // their percentage last - kept free whether anything has a battery or
    // not, so nothing shifts when one connects. The boxes stop at a width
    // that still reads well, but never narrower than the deepest row needs,
    // and always leave the bars at least minBatteryBar.
    readonly property real batteryGap: Config.scaled(12, root.uiScale)
    // TreeNode.qml's gap after the bar and its percentage's width.
    readonly property real batteryPercentRoom: Config.scaled(48, root.uiScale)
    readonly property real minBatteryBar: Config.scaled(230, root.uiScale)
    readonly property real treeRoom: treeView.width - treeArea.pad * 2
    readonly property real boxesRight: Math.max(
        root.treeLayout.depth * root.treeMetrics.indent + Config.scaled(240, root.uiScale),
        Math.min(root.treeRoom - root.batteryGap - root.minBatteryBar - root.batteryPercentRoom, Config.scaled(540, root.uiScale)))
    readonly property real batteryBarWidth: Math.max(root.minBatteryBar,
        root.treeRoom - root.boxesRight - root.batteryGap - root.batteryPercentRoom)
    readonly property real batteryColumn: root.batteryGap + root.batteryBarWidth + root.batteryPercentRoom

    readonly property var nodeByKey: {
        const map = {}
        for (const n of root.treeLayout.nodes) map[n.key] = n
        return map
    }

    // Just the keys go to the Repeater, which keeps a box for as long as its
    // key's there - the tree is rebuilt whenever anything in it changes, and
    // a rename in progress has to outlive that.
    readonly property var nodeKeys: root.treeLayout.nodes.map(n => n.key)

    function stateColor(state) {
        const role = Logic.colorRole(state)
        return role === "light" ? Config.fgcolorlight
            : role === "dark" ? Config.fgcolordark
            : role === "red" ? Config.fgcolorred
            : Config.fgcolor
    }

    // ---------------- selection, renaming, actions ----------------
    property string selectedKey: "host"
    property string selectedParentKey: ""
    readonly property var selectedNode: root.nodeByKey[root.selectedKey] || null

    // When what's picked goes (forgotten, unplugged), its parent is picked
    // instead - or this computer.
    onSelectedNodeChanged: {
        if (root.selectedNode) {
            root.selectedParentKey = root.selectedNode.parentKey
            return
        }
        root.selectedKey = root.nodeByKey[root.selectedParentKey] ? root.selectedParentKey : "host"
    }

    onSelectedKeyChanged: root.updateRadios()

    function select(key) {
        root.selectedKey = key
    }

    property string renamingKey: ""

    function startRename(key) {
        root.selectedKey = key
        root.renamingKey = key
    }

    function finishRename(node, newName) {
        if (root.renamingKey !== node.key) return
        root.renamingKey = ""
        aliasStore.rename(node.aliasKey, newName, node.systemName)
    }

    function cancelRename() {
        root.renamingKey = ""
    }

    // `action` is one of ConnectionsLogic.js's: enable, disable, connect,
    // disconnect, forget.
    function perform(node, action) {
        if (!node || !action) return
        const ref = node.ref
        switch (node.kind) {
        case "wifiDevice":
            if (action === "disable") {
                // The radio, as Wi-Fi's own switch does - or, where
                // Quickshell can't reach it, just this device.
                if (Networking.wifiEnabled !== undefined) Networking.wifiEnabled = false
                else ref.nmManaged = false
            } else if (action === "enable") {
                ref.nmManaged = true
                if (Networking.wifiEnabled !== undefined) Networking.wifiEnabled = true
            }
            break
        case "wiredDevice":
            ref.nmManaged = action === "enable"
            break
        case "btAdapter":
            ref.enabled = action === "enable"
            break
        case "ztService":
            root.setZerotierRunning(action === "enable")
            break
        case "wifiNetwork":
        case "wiredNetwork":
        case "btDevice":
            if (action === "disconnect") ref.disconnect()
            else if (action === "forget") ref.forget()
            else if (action === "connect") ref.connect()
            break
        }
    }

    function rightClick(node) {
        root.selectedKey = node.key
        root.perform(node, Logic.rightClickAction(node.kind, node.state))
    }

    // Wi-Fi scans only while a Wi-Fi device or one of its networks is picked,
    // and Bluetooth looks for devices only while its adapter is - both cost
    // radio time and power.
    function updateRadios() {
        const picked = root.active ? root.selectedNode : null
        const scanning = !picked ? null
            : picked.kind === "wifiDevice" ? picked.ref
            : picked.kind === "wifiNetwork" ? picked.device
            : null
        for (const dev of Networking.devices.values) {
            if (dev.type === DeviceType.Wifi) dev.scannerEnabled = dev === scanning
        }
        const discovering = picked && picked.kind === "btAdapter" ? picked.ref : null
        for (const a of Bluetooth.adapters.values) {
            const want = a === discovering && a.enabled
            if (a.discovering !== want) a.discovering = want
        }
    }

    // ---------------- layout ----------------
    Item {
        id: contentWrapper

        anchors.fill: parent

        RowLayout {
            id: contentRow

            readonly property real margins: Config.scaled(18, root.uiScale)
            readonly property real dividerWidth: Config.scaled(2, root.uiScale)

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: hintSeparator.top
                margins: contentRow.margins
                bottomMargin: Config.scaled(14, root.uiScale)
            }
            spacing: Config.scaled(12, root.uiScale)

            // ---------------- LEFT: the tree ----------------
            Flickable {
                id: treeView

                Layout.preferredWidth: (contentRow.width - contentRow.spacing * 2 - contentRow.dividerWidth) * 0.6
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(treeView.width, treeArea.width + treeArea.pad * 2)
                contentHeight: root.treeLayout.height + treeArea.pad * 2

                // Top left, as a directory listing is, scrolling once it
                // outgrows the room.
                Item {
                    id: treeArea

                    readonly property real pad: Config.scaled(8, root.uiScale)

                    x: treeArea.pad
                    y: treeArea.pad
                    width: root.boxesRight + root.batteryColumn
                    height: root.treeLayout.height

                    // The tree's lines: each parent's trunk down from under
                    // it, and an arm across to each child - lit to anything
                    // that's on or connected.
                    Canvas {
                        id: lineCanvas

                        readonly property var lines: root.treeLayout.lines
                        readonly property color lit: Config.fgcolor
                        readonly property color dim: Config.fgcolordark

                        anchors.fill: parent
                        onLinesChanged: requestPaint()
                        onLitChanged: requestPaint()
                        onDimChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const thickness = Config.scaled(2, root.uiScale)
                            ctx.lineWidth = thickness
                            // On whole pixels, so the lines stay sharp.
                            const at = v => Math.round(v - thickness / 2) + thickness / 2
                            for (const l of lineCanvas.lines) {
                                const child = l.to ? root.nodeByKey[l.to] : null
                                const role = child ? Logic.colorRole(child.state) : "dark"
                                ctx.strokeStyle = role === "dark" || role === "red" ? lineCanvas.dim : lineCanvas.lit
                                ctx.beginPath()
                                ctx.moveTo(at(l.x1), at(l.y1))
                                ctx.lineTo(at(l.x2), at(l.y2))
                                ctx.stroke()
                            }
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: root.nodeKeys
                        }

                        delegate: TreeNode {
                            id: treeNode

                            required property string modelData
                            readonly property var info: root.nodeByKey[treeNode.modelData] || null

                            visible: !!treeNode.info
                            x: treeNode.info ? Math.round(treeNode.info.x) : 0
                            y: treeNode.info ? Math.round(treeNode.info.y) : 0
                            width: root.boxesRight - x
                            height: root.treeMetrics.rowHeight
                            uiScale: root.uiScale
                            batteryGap: root.batteryGap
                            batteryBarWidth: root.batteryBarWidth

                            title: treeNode.info ? treeNode.info.name : ""
                            subtitle: treeNode.info ? treeNode.info.subtitle : ""
                            icons: treeNode.info ? treeNode.info.icons : []
                            stateColor: root.stateColor(treeNode.info ? treeNode.info.state : "on")
                            battery: treeNode.info ? treeNode.info.battery : -1
                            charging: treeNode.info ? treeNode.info.charging : false
                            selected: root.selectedKey === treeNode.modelData
                            renaming: root.renamingKey === treeNode.modelData

                            onClicked: root.select(treeNode.modelData)
                            onRenameRequested: root.startRename(treeNode.modelData)
                            onActionRequested: {
                                if (treeNode.info) root.rightClick(treeNode.info)
                            }
                            onRenamed: (newName) => {
                                if (treeNode.info) root.finishRename(treeNode.info, newName)
                            }
                            onRenameCancelled: root.cancelRename()
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.fillHeight: true
                color: Config.fgcolor
            }

            // ---------------- RIGHT: details ----------------
            ConnectionDetails {
                Layout.fillWidth: true
                Layout.fillHeight: true
                uiScale: root.uiScale
                active: root.active
                page: root
                node: root.selectedNode
            }
        }

        // ---------------- hint row ----------------
        Rectangle {
            id: hintSeparator

            anchors {
                left: parent.left
                right: parent.right
                bottom: hintRow.top
                bottomMargin: Config.scaled(10, root.uiScale)
                leftMargin: contentRow.margins
                rightMargin: contentRow.margins
            }
            height: Config.scaled(2, root.uiScale)
            color: Config.fgcolor
        }

        RowLayout {
            id: hintRow

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: contentRow.margins
            }
            spacing: Config.scaled(16, root.uiScale)

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-left-symbolic")
                label: "Select"
            }

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-middle-symbolic", "input-mouse-symbolic")
                label: "Rename (here only)"
            }

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-right-symbolic")
                label: "Disable / Disconnect"
            }

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-right-symbolic")
                label: "Forget (remembered)"
                tint: Config.fgcolorred
            }

            Item { Layout.fillWidth: true }
        }
    }
}

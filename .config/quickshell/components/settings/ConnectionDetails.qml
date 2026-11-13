import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../../Config.js" as Config
import "../common"
import "controls"
import "ConnectionsLogic.js" as Logic

// The right half of Settings > Connections (NetworkSettings.qml): what's
// picked in the tree, what there is to know about it, and what can be done
// with it - the tree's own actions as buttons and a few more, plus, for Wi-Fi,
// a searchable list of the networks in range to join, and for a Bluetooth
// adapter, the devices nearby to pair.
//
// An interface's addresses, routes and DNS come from `ip -j` and nmcli every
// few seconds, and its traffic from /sys/class/net/<name>/statistics every
// second - only while it's picked and the tab is open.
Item {
    id: root

    property real uiScale: 1.0
    property bool active: false
    // NetworkSettings.qml: its actions, its names and what it knows of this
    // computer.
    property var page: null
    property var node: null

    readonly property string kind: root.node ? root.node.kind : ""
    readonly property var ref: root.node ? root.node.ref : null
    readonly property string nodeKey: root.node ? root.node.key : ""

    // The network interface it's about, for addresses and traffic.
    readonly property string iface: {
        switch (root.kind) {
        case "wifiDevice":
        case "wiredDevice":
            return root.ref ? root.ref.name : ""
        case "wifiNetwork":
        case "wiredNetwork":
            return root.ref && root.ref.connected && root.node.device ? root.node.device.name : ""
        case "ztNetwork":
            return root.node.systemName
        default:
            return ""
        }
    }
    readonly property var wifiDevice: root.kind === "wifiDevice" ? root.ref : root.kind === "wifiNetwork" ? root.node.device : null
    readonly property var adapter: root.kind === "btAdapter" ? root.ref : null
    readonly property bool anyBluetoothOn: Bluetooth.adapters.values.some(a => a.enabled)

    // ---------------- addresses, routes, the access point ----------------
    property var routes: []
    property var links: []
    property var link: null
    property var nm: ({ connection: "", gateway: "", dns: [] })
    property var accessPoints: []
    property real uptime: 0
    // Which node the details running now are for - a slow answer for one
    // that's no longer picked is dropped.
    property string detailsFor: ""

    readonly property bool wantsDetails: root.kind === "host" || root.iface.length > 0 || !!root.wifiDevice

    readonly property string detailsScript: [
        'echo @@route; ip -j route show default 2>/dev/null',
        'if [ -n "$1" ]; then',
        '  echo @@addr; ip -j addr show dev "$1" 2>/dev/null',
        '  echo @@nm; nmcli -t -f GENERAL.CONNECTION,IP4.GATEWAY,IP4.DNS,IP6.DNS device show "$1" 2>/dev/null',
        'elif [ -z "$2" ]; then',
        '  echo @@links; ip -j addr show 2>/dev/null',
        '  echo @@uptime; cut -d" " -f1 /proc/uptime',
        'fi',
        'if [ -n "$2" ]; then',
        '  echo @@wifi; nmcli -t -f IN-USE,BSSID,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY device wifi list ifname "$2" --rescan no 2>/dev/null',
        'fi'
    ].join("\n")

    function refreshDetails() {
        if (!root.active || !root.wantsDetails || detailsProcess.running) return
        root.detailsFor = root.nodeKey
        detailsProcess.command = ["sh", "-c", root.detailsScript, "sh", root.iface, root.wifiDevice ? root.wifiDevice.name : ""]
        detailsProcess.running = true
    }

    function clearDetails() {
        root.routes = []
        root.links = []
        root.link = null
        root.nm = { connection: "", gateway: "", dns: [] }
        root.accessPoints = []
    }

    Process {
        id: detailsProcess

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.detailsFor !== root.nodeKey) {
                    Qt.callLater(root.refreshDetails)
                    return
                }
                const s = Logic.sections(text)
                root.routes = Logic.parseDefaultRoutes(s.route || "")
                root.link = s.addr !== undefined ? Logic.parseIpAddr(s.addr) : null
                root.links = s.links !== undefined ? Logic.parseIpLinks(s.links) : []
                root.nm = Logic.parseDeviceShow(s.nm || "")
                root.accessPoints = Logic.parseWifiList(s.wifi || "")
                if (s.uptime !== undefined) root.uptime = parseFloat(s.uptime) || 0
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.active && root.wantsDetails
        onTriggered: root.refreshDetails()
    }

    // ---------------- traffic ----------------
    property var lastSample: null
    property real rxRate: 0
    property real txRate: 0
    property real rxTotal: 0
    property real txTotal: 0
    property var rxHistory: []
    property var txHistory: []
    property string trafficFor: ""
    readonly property int historyLength: 60

    function resetTraffic() {
        root.lastSample = null
        root.rxRate = 0
        root.txRate = 0
        root.rxTotal = 0
        root.txTotal = 0
        root.rxHistory = []
        root.txHistory = []
    }

    Process {
        id: trafficProcess

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.trafficFor !== root.iface) return
                const parts = text.trim().split(/\s+/)
                const sample = { rx: Number(parts[0]), tx: Number(parts[1]), at: Date.now() }
                if (parts.length < 2 || !isFinite(sample.rx) || !isFinite(sample.tx)) return
                if (root.lastSample) {
                    const rate = Logic.rates(root.lastSample, sample)
                    root.rxRate = rate.rx
                    root.txRate = rate.tx
                    root.rxHistory = Logic.pushHistory(root.rxHistory, rate.rx, root.historyLength)
                    root.txHistory = Logic.pushHistory(root.txHistory, rate.tx, root.historyLength)
                }
                root.lastSample = sample
                root.rxTotal = sample.rx
                root.txTotal = sample.tx
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.active && root.iface.length > 0
        onTriggered: {
            if (trafficProcess.running) return
            root.trafficFor = root.iface
            const base = "/sys/class/net/" + root.iface + "/statistics/"
            trafficProcess.command = ["cat", base + "rx_bytes", base + "tx_bytes"]
            trafficProcess.running = true
        }
    }

    onNodeKeyChanged: {
        root.clearDetails()
        root.resetTraffic()
        searchField.text = ""
        root.search = ""
        root.joining = null
        root.joinError = ""
        root.refreshDetails()
    }
    onIfaceChanged: {
        root.resetTraffic()
        root.refreshDetails()
    }
    onActiveChanged: {
        if (root.active) root.refreshDetails()
    }

    // ---------------- facts ----------------
    readonly property var kindLabels: ({
        host: "This computer",
        solaarHub: "Solaar",
        solaar: "Logitech device",
        wifiDevice: "Wi-Fi device",
        wifiNetwork: "Wi-Fi network",
        wiredDevice: "Ethernet device",
        wiredNetwork: "Wired connection",
        btAdapter: "Bluetooth adapter",
        btDevice: "Bluetooth device",
        ztService: "ZeroTier",
        ztNetwork: "ZeroTier network"
    })

    function yesNo(value) {
        return value ? "yes" : "no"
    }

    // The access point an SSID is on: the one in use, or else its strongest.
    function accessPointFor(ssid) {
        const matches = root.accessPoints.filter(a => a.ssid === ssid)
        return matches.find(a => a.inUse) || matches.sort((a, b) => b.signal - a.signal)[0] || null
    }

    function addAccessPoint(add, ssid) {
        const ap = root.accessPointFor(ssid)
        if (!ap) return
        const band = Logic.band(ap.frequency)
        add("Band", band + (ap.channel ? (band ? " · " : "") + "channel " + ap.channel : ""))
        add("Bitrate", ap.rate)
        add("Access point", ap.bssid)
    }

    function addAddressing(add) {
        if (root.link) {
            add("IPv4", root.link.ipv4)
            add("IPv6", root.link.ipv6)
        }
        const route = root.routes.find(r => r.dev === root.iface)
        add("Gateway", root.nm.gateway || (route ? route.gateway : ""))
        add("DNS", root.nm.dns)
        add("Profile", root.nm.connection)
    }

    readonly property var facts: {
        const out = []
        const add = (label, value) => {
            if (value === undefined || value === null) return
            const text = Array.isArray(value) ? value.join(", ") : String(value)
            if (text.length > 0) out.push({ label: label, value: text })
        }
        const r = root.ref
        if (!root.page) return out
        switch (root.kind) {
        case "host": {
            add("User", root.page.userName)
            add("Hostname", root.page.hostName)
            add("Kernel", root.page.kernel)
            add("Up for", root.uptime > 0 ? Logic.formatDuration(root.uptime) : "")
            if (Networking.connectivity !== undefined && typeof NetworkConnectivity !== "undefined")
                add("Internet", NetworkConnectivity.toString(Networking.connectivity))
            const route = root.routes[0]
            if (route) add("Default route", route.dev + (route.gateway ? " via " + route.gateway : ""))
            for (const l of root.links) add(l.name, l.ipv4.concat(l.ipv6))
            const b = root.page.laptopBattery
            if (b) {
                add("Battery", root.page.percent(b.percentage) + " · " + UPowerDeviceState.toString(b.state).toLowerCase())
                if (b.timeToEmpty > 0) add("Time left", Logic.formatDuration(b.timeToEmpty))
                if (b.timeToFull > 0) add("Until full", Logic.formatDuration(b.timeToFull))
                if (b.changeRate > 0) add("Power", b.changeRate.toFixed(1) + " W")
                if (b.healthSupported) add("Battery health", Math.round(b.healthPercentage) + "%")
            }
            break
        }
        case "solaarHub": {
            const devices = root.page.solaarDevices
            add("Devices", String(devices.length))
            const receivers = []
            for (const d of devices) {
                if (d.receiver && receivers.indexOf(d.receiver) === -1) receivers.push(d.receiver)
            }
            add("Receivers", receivers)
            const low = devices.filter(d => d.percentage >= 0 && Logic.batteryLow(d.percentage, d.charging))
            add("Low battery", low.map(d => root.page.names.name("solaar:" + d.name, d.name)))
            break
        }
        case "solaar":
            add("Battery", root.page.percent(r.percentage) + (r.status ? " · " + r.status : ""))
            add("Kind", r.kind)
            add("Connected through", r.receiver || "Bluetooth or USB")
            add("Codename", r.codename)
            add("Serial", r.serial)
            add("Firmware", r.firmware)
            add("Protocol", r.protocol)
            add("Report rate", r.reportRate)
            add("Wireless PID", r.wpid)
            break
        case "wifiDevice": {
            add("Interface", r.name)
            add("MAC", root.link ? root.link.mac : r.address)
            add("Radio", Networking.wifiHardwareEnabled === false ? "switched off" : Networking.wifiEnabled === false ? "off" : "on")
            const current = r.networks.values.find(n => n.connected)
            if (current) {
                add("Network", root.page.names.name("wifi:" + current.name, current.name))
                add("Signal", root.page.percent(current.signalStrength))
                add("Security", WifiSecurityType.toString(current.security))
                root.addAccessPoint(add, current.name)
            }
            root.addAddressing(add)
            break
        }
        case "wifiNetwork":
            add("SSID", r.name)
            add("State", r.connected ? "connected" : r.known ? "remembered" : "in range")
            add("Signal", r.signalStrength > 0 ? root.page.percent(r.signalStrength) : "out of range")
            add("Security", WifiSecurityType.toString(r.security))
            root.addAccessPoint(add, r.name)
            if (r.connected) root.addAddressing(add)
            break
        case "wiredDevice":
            add("Interface", r.name)
            add("MAC", root.link ? root.link.mac : r.address)
            if (r.hasLink !== undefined) add("Cable", r.hasLink ? "plugged in" : "unplugged")
            if (r.linkSpeed > 0) add("Speed", r.linkSpeed + " Mbit/s")
            add("Enabled", root.yesNo(r.nmManaged !== false))
            root.addAddressing(add)
            break
        case "wiredNetwork":
            add("Profile", r.name)
            add("State", r.connected ? "connected" : "disconnected")
            add("Interface", root.node.device ? root.node.device.name : "")
            if (r.connected) root.addAddressing(add)
            break
        case "btAdapter":
            add("Adapter", r.adapterId)
            add("State", BluetoothAdapterState.toString(r.state))
            add("Discoverable", root.yesNo(r.discoverable))
            add("Pairable", root.yesNo(r.pairable))
            add("Paired devices", String(r.devices.values.filter(d => d.paired).length))
            add("Connected", String(r.devices.values.filter(d => d.connected).length))
            break
        case "btDevice":
            add("Address", r.address)
            if (r.deviceName.length > 0 && r.deviceName !== root.node.systemName) add("Calls itself", r.deviceName)
            add("Type", Logic.bluetoothKind(r.icon))
            add("State", r.connected ? "connected" : r.paired ? "remembered" : "nearby")
            add("Paired", root.yesNo(r.paired))
            add("Bonded", root.yesNo(r.bonded))
            add("Trusted", root.yesNo(r.trusted))
            if (r.blocked) add("Blocked", "yes")
            if (root.node.battery >= 0) add("Battery", root.page.percent(root.node.battery) + (root.node.charging ? " · charging" : ""))
            add("Adapter", r.adapter ? r.adapter.name : "")
            break
        case "ztService":
            add("Service", root.page.zerotierService.installed
                ? (root.page.zerotierService.active ? "running" : "stopped")
                : "not installed as a service")
            add("Networks", String(root.page.zerotierInterfaces.length))
            break
        case "ztNetwork":
            add("Interface", root.node.systemName)
            if (root.link) {
                add("MAC", root.link.mac)
                add("MTU", root.link.mtu > 0 ? String(root.link.mtu) : "")
                add("State", root.link.state)
                add("IPv4", root.link.ipv4)
                add("IPv6", root.link.ipv6)
            }
            break
        }
        return out
    }

    // ---------------- actions ----------------
    readonly property var actions: {
        const out = []
        const add = (label, action, extra) => out.push(Object.assign({ label: label, action: action, lit: false, danger: false }, extra || {}))
        const n = root.node
        const r = root.ref
        if (!n || !root.page) return out
        switch (root.kind) {
        case "host":
            if (Networking.wifiEnabled !== undefined && Networking.devices.values.some(d => d.type === DeviceType.Wifi))
                add(Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on", "wifiRadio", { lit: Networking.wifiEnabled })
            if (Bluetooth.adapters.values.length > 0)
                add(root.anyBluetoothOn ? "Turn Bluetooth off" : "Turn Bluetooth on", "bluetoothPower", { lit: root.anyBluetoothOn })
            break
        case "solaarHub":
        case "solaar":
            add("Refresh", "solaarRefresh")
            add("Open Solaar", "solaarOpen")
            break
        case "wifiDevice":
        case "wiredDevice":
        case "btAdapter":
        case "ztService":
            if (root.kind !== "ztService" || root.page.zerotierService.installed)
                add(n.state === "off" ? "Enable" : "Disable", n.state === "off" ? "enable" : "disable")
            if (root.kind === "btAdapter" && r.enabled)
                add(r.discoverable ? "Stop being discoverable" : "Make discoverable", "discoverable", { lit: r.discoverable })
            break
        case "wifiNetwork":
        case "wiredNetwork":
        case "btDevice": {
            const connected = n.state === "connected" || n.state === "saved"
            if (n.state !== "busy") add(connected ? "Disconnect" : "Connect", connected ? "disconnect" : "connect")
            if (root.kind === "btDevice") add(r.trusted ? "Stop trusting" : "Trust", "trust", { lit: r.trusted })
            if (root.kind === "wifiNetwork" && r.known) add("Forget", "forget", { danger: true })
            if (root.kind === "btDevice" && r.paired) add("Forget", "forget", { danger: true })
            break
        }
        }
        if (root.page.canRename(n)) {
            add("Rename", "rename")
            if (n.name !== n.systemName) add("Use system name", "resetName")
        }
        return out
    }

    function run(action) {
        const n = root.node
        if (!n) return
        switch (action) {
        case "rename":
            root.page.startRename(n.key)
            break
        case "resetName":
            root.page.names.rename(n.aliasKey, "", n.systemName)
            break
        case "wifiRadio":
            Networking.wifiEnabled = !Networking.wifiEnabled
            break
        case "bluetoothPower": {
            const on = !root.anyBluetoothOn
            for (const a of Bluetooth.adapters.values) a.enabled = on
            break
        }
        case "solaarRefresh":
            root.page.refreshSolaar()
            break
        case "solaarOpen":
            Quickshell.execDetached(["solaar"])
            break
        case "discoverable":
            root.ref.discoverable = !root.ref.discoverable
            break
        case "trust":
            root.ref.trusted = !root.ref.trusted
            break
        case "connect":
            if (root.kind === "wifiNetwork") root.join(root.ref)
            else root.page.perform(n, action)
            break
        default:
            root.page.perform(n, action)
        }
    }

    // ---------------- Wi-Fi: networks in range ----------------
    property string search: ""
    // The network waiting on a password, and why the last attempt failed.
    property var joining: null
    property string joinError: ""

    readonly property bool wifiListShown: !!root.wifiDevice && Networking.wifiEnabled !== false && root.wifiDevice.nmManaged !== false

    readonly property var networkList: {
        if (!root.wifiListShown || !root.page) return []
        const query = root.search.trim().toLowerCase()
        const names = root.page.names
        return Logic.sortNetworks(root.wifiDevice.networks.values
            .filter(n => query.length === 0 || n.name.toLowerCase().includes(query)
                || names.name("wifi:" + n.name, n.name).toLowerCase().includes(query))
            .map(n => ({ net: n, name: n.name, connected: n.connected, signal: n.signalStrength || 0 })))
            .map(e => e.net)
    }

    function needsPassword(net) {
        return net.security === WifiSecurityType.WpaPsk || net.security === WifiSecurityType.Wpa2Psk || net.security === WifiSecurityType.Sae
    }

    // A network it knows, or an open one, just connects; one wanting a
    // password asks for it first. Anything else (enterprise, WEP) is left to
    // NetworkManager, and a failure says why.
    function join(net) {
        root.joinError = ""
        if (net.known || !root.needsPassword(net)) {
            root.joining = null
            net.connect()
        } else {
            root.joining = net
        }
    }

    // ---------------- Bluetooth: devices nearby ----------------
    readonly property var nearbyDevices: !root.adapter || !root.adapter.enabled ? []
        : root.adapter.devices.values
            .filter(d => !d.paired && !d.connected)
            .slice()
            .sort((a, b) => (b.name.length > 0) - (a.name.length > 0) || (a.name || a.address).localeCompare(b.name || b.address))

    // ---------------- pieces ----------------
    // A bordered one-line text field.
    component Field: Rectangle {
        id: field

        property alias text: fieldInput.text
        property string placeholder: ""
        property bool secret: false

        signal accepted()

        function focusInput() {
            fieldInput.forceActiveFocus()
        }

        implicitHeight: Config.scaled(32, root.uiScale)
        color: Config.fillcolor
        border.width: Config.scaled(2, root.uiScale)
        border.color: fieldInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

        TextInput {
            id: fieldInput

            anchors {
                fill: parent
                margins: Config.scaled(8, root.uiScale)
            }
            verticalAlignment: TextInput.AlignVCenter
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            selectByMouse: true
            clip: true
            onAccepted: field.accepted()

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: fieldInput.text.length === 0
                text: field.placeholder
                color: Config.fgcolorhint
                font: fieldInput.font
            }
        }
    }

    // Four bars, lit by a 0 - 1 signal.
    component SignalBars: Item {
        id: bars

        property real strength: 0
        property color color: Config.fgcolor

        implicitWidth: Config.scaled(18, root.uiScale)
        implicitHeight: Config.scaled(14, root.uiScale)

        Repeater {
            model: 4

            Rectangle {
                required property int index

                readonly property real barWidth: (bars.width - Config.scaled(2, root.uiScale) * 3) / 4

                x: index * (barWidth + Config.scaled(2, root.uiScale))
                y: bars.height - height
                width: barWidth
                height: bars.height * (index + 1) / 4
                color: index < Logic.signalBars(bars.strength) ? bars.color : Config.fgcolordark
            }
        }
    }

    // ---------------- layout ----------------
    Flickable {
        id: scroller

        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body

            width: scroller.width
            spacing: Config.scaled(10, root.uiScale)

            // ---------------- what it is ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.scaled(10, root.uiScale)

                Text {
                    Layout.fillWidth: true
                    text: root.node ? root.node.name : ""
                    textFormat: Text.PlainText
                    color: Config.fgcolorlight
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(20, root.uiScale)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Tag {
                    uiScale: root.uiScale
                    label: root.kindLabels[root.kind] || ""
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !!root.node && root.node.name !== root.node.systemName
                text: root.node ? "Renamed here from " + root.node.systemName : ""
                textFormat: Text.PlainText
                color: Config.fgcolorhint
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                elide: Text.ElideRight
            }

            // ---------------- details ----------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Config.scaled(4, root.uiScale)
                spacing: Config.scaled(4, root.uiScale)

                Repeater {
                    model: root.facts

                    delegate: RowLayout {
                        id: factRow

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Config.scaled(12, root.uiScale)

                        Text {
                            Layout.preferredWidth: Config.scaled(130, root.uiScale)
                            Layout.alignment: Qt.AlignTop
                            text: factRow.modelData.label
                            textFormat: Text.PlainText
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: factRow.modelData.value
                            textFormat: Text.PlainText
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }

            // ---------------- what to do ----------------
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Config.scaled(6, root.uiScale)
                spacing: Config.scaled(8, root.uiScale)

                Repeater {
                    model: root.actions

                    delegate: ActionButton {
                        required property var modelData

                        uiScale: root.uiScale
                        text: modelData.label
                        lit: modelData.lit
                        danger: modelData.danger
                        onClicked: root.run(modelData.action)
                    }
                }
            }

            // ---------------- traffic ----------------
            SectionHeader {
                visible: root.iface.length > 0
                uiScale: root.uiScale
                text: "Traffic"
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.iface.length > 0
                spacing: Config.scaled(18, root.uiScale)

                Text {
                    text: "↓ " + Logic.formatRate(root.rxRate)
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(15, root.uiScale)
                    font.bold: true
                }

                Text {
                    text: "↑ " + Logic.formatRate(root.txRate)
                    color: Config.fgcolorlight
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(15, root.uiScale)
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "since boot ↓ " + Logic.formatBytes(root.rxTotal) + "  ↑ " + Logic.formatBytes(root.txTotal)
                    color: Config.fgcolorhint
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, root.uiScale)
                }
            }

            // The last minute: down in fgcolor, up in fgcolorlight, scaled to
            // the busiest second.
            Canvas {
                id: trafficGraph

                readonly property var rx: root.rxHistory
                readonly property var tx: root.txHistory

                Layout.fillWidth: true
                Layout.preferredHeight: Config.scaled(70, root.uiScale)
                visible: root.iface.length > 0

                onRxChanged: requestPaint()
                onTxChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const line = Config.scaled(2, root.uiScale)
                    ctx.lineWidth = line
                    ctx.strokeStyle = Config.fgcolordark
                    ctx.strokeRect(line / 2, line / 2, width - line, height - line)
                    const peak = Math.max(1024, Math.max.apply(null, trafficGraph.rx.concat(trafficGraph.tx, [0])))
                    const step = (width - line * 2) / (root.historyLength - 1)
                    const draw = (values, color) => {
                        if (values.length < 2) return
                        ctx.strokeStyle = color
                        ctx.beginPath()
                        const offset = root.historyLength - values.length
                        for (let i = 0; i < values.length; i++) {
                            const x = line + (offset + i) * step
                            const y = height - line * 2 - (height - line * 4) * values[i] / peak
                            if (i === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                    }
                    draw(trafficGraph.tx, Config.fgcolorlight)
                    draw(trafficGraph.rx, Config.fgcolor)
                }
            }

            // ---------------- Wi-Fi networks ----------------
            SectionHeader {
                visible: root.wifiListShown
                uiScale: root.uiScale
                text: "Networks"
            }

            Field {
                id: searchField

                Layout.fillWidth: true
                visible: root.wifiListShown
                placeholder: "Search networks"
                onTextChanged: root.search = searchField.text
            }

            Repeater {
                model: ScriptModel {
                    values: root.networkList
                }

                delegate: ColumnLayout {
                    id: networkRow

                    required property var modelData

                    readonly property var net: networkRow.modelData
                    readonly property bool asking: root.joining === networkRow.net
                    readonly property string displayName: root.page.names.name("wifi:" + networkRow.net.name, networkRow.net.name)

                    Layout.fillWidth: true
                    spacing: Config.scaled(6, root.uiScale)

                    Connections {
                        target: networkRow.net

                        function onConnectionFailed(reason) {
                            if (reason === ConnectionFailReason.NoSecrets && root.needsPassword(networkRow.net)) {
                                root.joining = networkRow.net
                                root.joinError = "Wrong or missing password for " + networkRow.displayName + "."
                            } else {
                                root.joinError = networkRow.displayName + ": " + ConnectionFailReason.toString(reason)
                            }
                        }
                    }

                    DashCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.scaled(40, root.uiScale)
                        uiScale: root.uiScale
                        color: rowMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                        border.color: networkRow.net.connected ? Config.fgcolorlight : Config.fgcolor

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            // Known ones are in the tree: show them there.
                            onClicked: {
                                if (networkRow.net.known || networkRow.net.connected)
                                    root.page.select("wifi:" + root.wifiDevice.name + ":" + networkRow.net.name)
                            }
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: Config.scaled(10, root.uiScale)
                                rightMargin: Config.scaled(6, root.uiScale)
                            }
                            spacing: Config.scaled(10, root.uiScale)

                            SignalBars {
                                strength: networkRow.net.signalStrength
                                color: networkRow.net.connected ? Config.fgcolorlight : Config.fgcolor
                            }

                            Text {
                                Layout.fillWidth: true
                                text: networkRow.displayName
                                textFormat: Text.PlainText
                                color: networkRow.net.connected ? Config.fgcolorlight : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: networkRow.net.connected
                                elide: Text.ElideRight
                            }

                            Text {
                                text: WifiSecurityType.toString(networkRow.net.security)
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(11, root.uiScale)
                            }

                            Tag {
                                visible: networkRow.net.connected || networkRow.net.known
                                uiScale: root.uiScale
                                label: networkRow.net.connected ? "Connected" : "Saved"
                            }

                            ActionButton {
                                Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                uiScale: root.uiScale
                                enabled: !networkRow.net.stateChanging
                                text: networkRow.net.stateChanging ? "…" : networkRow.net.connected ? "Disconnect" : "Connect"
                                onClicked: {
                                    if (networkRow.net.connected) networkRow.net.disconnect()
                                    else root.join(networkRow.net)
                                }
                            }
                        }
                    }

                    // Asked for when joining a network that needs one.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: networkRow.asking
                        spacing: Config.scaled(8, root.uiScale)

                        Field {
                            id: passwordField

                            Layout.fillWidth: true
                            secret: true
                            placeholder: "Password for " + networkRow.displayName
                            onAccepted: {
                                if (passwordField.text.length > 0) joinButton.clicked()
                            }
                        }

                        ActionButton {
                            id: joinButton
                            uiScale: root.uiScale
                            text: "Join"
                            lit: true
                            enabled: passwordField.text.length > 0
                            onClicked: {
                                root.joinError = ""
                                root.joining = null
                                networkRow.net.connectWithPsk(passwordField.text)
                                passwordField.text = ""
                            }
                        }

                        ActionButton {
                            uiScale: root.uiScale
                            text: "Cancel"
                            onClicked: {
                                root.joining = null
                                passwordField.text = ""
                            }
                        }
                    }

                    onAskingChanged: {
                        if (networkRow.asking) passwordField.focusInput()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.wifiListShown && root.networkList.length === 0
                text: root.search.length > 0 ? "No network matches." : "Looking for networks…"
                color: Config.fgcolorhint
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
            }

            Text {
                Layout.fillWidth: true
                visible: root.wifiListShown && root.joinError.length > 0
                text: root.joinError
                textFormat: Text.PlainText
                color: Config.fgcolorred
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                wrapMode: Text.Wrap
            }

            // ---------------- Bluetooth: nearby ----------------
            SectionHeader {
                visible: !!root.adapter && root.adapter.enabled
                uiScale: root.uiScale
                text: "Nearby devices"
            }

            Repeater {
                model: ScriptModel {
                    values: root.nearbyDevices
                }

                delegate: DashCard {
                    id: nearbyRow

                    required property var modelData

                    readonly property var device: nearbyRow.modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale

                    // Paired: trusted, so it can reconnect by itself, and
                    // connected - it then shows up in the tree.
                    Connections {
                        target: nearbyRow.device

                        function onPairedChanged() {
                            if (!nearbyRow.device.paired) return
                            nearbyRow.device.trusted = true
                            nearbyRow.device.connect()
                        }
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: Config.scaled(10, root.uiScale)
                            rightMargin: Config.scaled(6, root.uiScale)
                        }
                        spacing: Config.scaled(10, root.uiScale)

                        Text {
                            Layout.fillWidth: true
                            text: nearbyRow.device.name.length > 0 ? nearbyRow.device.name : nearbyRow.device.address
                            textFormat: Text.PlainText
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            elide: Text.ElideRight
                        }

                        Text {
                            text: Logic.bluetoothKind(nearbyRow.device.icon)
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, root.uiScale)
                        }

                        ActionButton {
                            Layout.preferredHeight: Config.scaled(28, root.uiScale)
                            uiScale: root.uiScale
                            enabled: !nearbyRow.device.pairing
                            text: nearbyRow.device.pairing ? "Pairing…" : "Pair"
                            onClicked: nearbyRow.device.pair()
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !!root.adapter && root.adapter.enabled && root.nearbyDevices.length === 0
                text: "Looking for devices… (they need to be in pairing mode)"
                color: Config.fgcolorhint
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                wrapMode: Text.Wrap
            }

            // ---------------- notes ----------------
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Config.scaled(8, root.uiScale)
                visible: text.length > 0
                text: root.kind === "ztService" || root.kind === "ztNetwork"
                    ? "Joining and leaving ZeroTier networks needs root: sudo zerotier-cli join <network id>. Stopping or starting the service asks for your password."
                    : root.kind === "solaar" || root.kind === "solaarHub"
                    ? "Read from Solaar once a minute. Solaar's own window has the devices' settings."
                    : ""
                color: Config.fgcolorhint
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                wrapMode: Text.Wrap
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.scaled(8, root.uiScale)
            }
        }
    }
}

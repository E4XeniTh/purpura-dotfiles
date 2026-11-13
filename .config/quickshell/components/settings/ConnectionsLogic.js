.pragma library

// Settings > Connections (NetworkSettings.qml), kept apart from it so it can
// be tested on its own: what state each node of the tree is in and what that
// looks like, what a right click does to it, the battery ring drawn round a
// node, the tree's layout, the display names given to nodes, and the text
// parsing behind the details panel.

// ---------------- states ----------------
// on          a device that's enabled, or a node that's simply there (the host)
// connected   a live connection with nothing remembered about it
// saved       connected and remembered: disconnecting leaves it forgettable
// remembered  known but not connected - a right click forgets it
// found       in range, never connected (search lists only, not the tree)
// busy        connecting or disconnecting
// off         a disabled device, or a disconnected connection that can't be
//             forgotten (wired)
function wifiNetworkState(n) {
    if (n.changing) return "busy"
    if (n.connected) return n.known ? "saved" : "connected"
    return n.known ? "remembered" : "found"
}

function bluetoothDeviceState(d) {
    if (d.changing) return "busy"
    if (d.connected) return d.paired ? "saved" : "connected"
    return d.paired ? "remembered" : "found"
}

function wiredNetworkState(n) {
    if (n.changing) return "busy"
    return n.connected ? "connected" : "off"
}

function deviceState(enabled) {
    return enabled ? "on" : "off"
}

// Border colours: fgcolor, fgcolorlight, fgcolordark or red.
var colorRoles = { on: "normal", connected: "normal", busy: "normal", saved: "light", remembered: "dark", found: "dark", off: "red" }

function colorRole(state) {
    return colorRoles[state] || "normal"
}

// What a right click does to a node; empty for nothing. Devices switch on and
// off; connections disconnect, and what's left remembered is forgotten; a
// wired connection, which can't be forgotten, connects again instead.
function rightClickAction(kind, state) {
    if (state === "busy") return ""
    switch (kind) {
    case "wifiDevice":
    case "wiredDevice":
    case "btAdapter":
    case "ztService":
        return state === "off" ? "enable" : "disable"
    case "wifiNetwork":
    case "btDevice":
        if (state === "connected" || state === "saved") return "disconnect"
        if (state === "remembered") return "forget"
        return "connect"
    case "wiredNetwork":
        return state === "off" ? "connect" : "disconnect"
    default:
        return ""
    }
}

// ---------------- battery ring ----------------
// A node with a battery has its border drawn as a ring of segments, lit up to
// its charge, clockwise from the middle of the top edge - red when it's low.
var lowBattery = 0.11

function batteryLow(fraction, charging) {
    return fraction < lowBattery && !charging
}

function litSegments(fraction, count) {
    return Math.round(Math.max(0, Math.min(1, fraction)) * count)
}

// The point `d` along a w x h box's edge, clockwise from the top's middle.
function edgePoint(w, h, d) {
    const perimeter = 2 * (w + h)
    d = ((d % perimeter) + perimeter) % perimeter
    if (d <= w / 2) return [w / 2 + d, 0]
    d -= w / 2
    if (d <= h) return [w, d]
    d -= h
    if (d <= w) return [w - d, h]
    d -= w
    if (d <= h) return [0, h - d]
    d -= h
    return [d, 0]
}

// `count` segments round the edge, `gap` apart, each as the points to draw
// through - corners included, so a segment bends round them.
function ringSegments(w, h, count, gap) {
    const perimeter = 2 * (w + h)
    const step = perimeter / count
    const corners = [w / 2, w / 2 + h, w / 2 + h + w, w / 2 + 2 * h + w]
    const out = []
    for (let i = 0; i < count; i++) {
        const from = i * step + gap / 2
        const to = (i + 1) * step - gap / 2
        const points = [edgePoint(w, h, from)]
        for (const c of corners) {
            if (c > from && c < to) points.push(edgePoint(w, h, c))
        }
        points.push(edgePoint(w, h, to))
        out.push(points)
    }
    return out
}

// ---------------- the tree ----------------
// Left to right: a column per level, every leaf on a row of its own and each
// parent level with the middle of its children, joined by straight lines from
// a parent's right edge to its children's left. `root` is { key, children };
// anything else on a node is carried over. Returns the placed nodes (with
// depth, x, y and their parent's key), the lines, and the size of it all.
function layoutTree(root, m) {
    const nodes = []
    const edges = []
    const pitch = m.nodeHeight + m.rowGap
    let row = 0

    function place(node, depth, parentKey) {
        const children = node.children || []
        const x = depth * (m.nodeWidth + m.columnGap)
        let y = 0
        if (children.length === 0) y = row++ * pitch
        const placedChildren = children.map(c => place(c, depth + 1, node.key))
        if (placedChildren.length > 0)
            y = (placedChildren[0].y + placedChildren[placedChildren.length - 1].y) / 2
        const placed = Object.assign({}, node, { depth: depth, x: x, y: y, parentKey: parentKey })
        delete placed.children
        nodes.push(placed)
        for (const c of placedChildren) {
            edges.push({ from: node.key, to: c.key, x1: x + m.nodeWidth, y1: y + m.nodeHeight / 2, x2: c.x, y2: c.y + m.nodeHeight / 2 })
        }
        return placed
    }

    place(root, 0, "")
    const depth = nodes.reduce((most, n) => Math.max(most, n.depth), 0)
    return {
        nodes: nodes,
        edges: edges,
        width: (depth + 1) * m.nodeWidth + depth * m.columnGap,
        height: Math.max(1, row) * pitch - m.rowGap
    }
}

// Connected first, then the strongest signal, then by name.
function sortNetworks(list) {
    return list.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.signal - a.signal) || a.name.localeCompare(b.name))
}

// Connected first, then by name.
function sortDevices(list) {
    return list.slice().sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
}

// ---------------- names ----------------
// A node's name here, never the system's: its own if it was given one.
function displayName(aliases, key, systemName) {
    const alias = aliases ? aliases[key] : ""
    return typeof alias === "string" && alias.length > 0 ? alias : systemName
}

// The aliases with `key` renamed to `name` - or back to the system's own name
// when that's blank or the same as it.
function withAlias(aliases, key, name, systemName) {
    const next = Object.assign({}, aliases)
    const trimmed = (name || "").trim()
    if (trimmed.length === 0 || trimmed === systemName) delete next[key]
    else next[key] = trimmed
    return next
}

// ---------------- details ----------------
// The details panel's one shell call prints each command's output after a
// "@@name" line; this splits it back up.
function sections(text) {
    const out = {}
    let current = ""
    for (const line of text.split("\n")) {
        const marker = line.match(/^@@(\w+)$/)
        if (marker) {
            current = marker[1]
            out[current] = []
        } else if (current) {
            out[current].push(line)
        }
    }
    for (const k in out) out[k] = out[k].join("\n").trim()
    return out
}

// nmcli -t puts several fields on a line split by ':', escaping ':' and '\'
// inside them with '\'.
function splitTerse(line) {
    const out = []
    let current = ""
    for (let i = 0; i < line.length; i++) {
        const c = line[i]
        if (c === "\\" && i + 1 < line.length) {
            current += line[++i]
        } else if (c === ":") {
            out.push(current)
            current = ""
        } else {
            current += c
        }
    }
    out.push(current)
    return out
}

// `nmcli -t -f IN-USE,BSSID,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY device wifi list`
function parseWifiList(text) {
    const out = []
    for (const line of text.split("\n")) {
        if (line.trim().length === 0) continue
        const f = splitTerse(line)
        if (f.length < 8) continue
        out.push({
            inUse: f[0].trim() === "*",
            bssid: f[1],
            ssid: f[2],
            channel: f[3],
            frequency: f[4],
            rate: f[5],
            signal: parseInt(f[6], 10) || 0,
            security: f[7].trim()
        })
    }
    return out
}

// `nmcli -t -f GENERAL.CONNECTION,IP4.GATEWAY,IP4.DNS,IP6.DNS device show X`:
// one "FIELD:value" a line, the value unescaped (IPv6 colons and all).
function parseDeviceShow(text) {
    const out = { connection: "", gateway: "", dns: [] }
    for (const line of text.split("\n")) {
        const colon = line.indexOf(":")
        if (colon === -1) continue
        const field = line.slice(0, colon)
        const value = line.slice(colon + 1).trim()
        if (value.length === 0 || value === "--") continue
        if (field === "GENERAL.CONNECTION") out.connection = value
        else if (field === "IP4.GATEWAY") out.gateway = value
        else if (/^IP[46]\.DNS/.test(field)) out.dns.push(value)
    }
    return out
}

// One link of `ip -j addr`: its name, MAC, MTU, state and global addresses.
function linkInfo(link) {
    const info = link.addr_info || []
    const addresses = family => info
        .filter(a => a.family === family && a.scope !== "link" && a.scope !== "host")
        .map(a => a.local + "/" + a.prefixlen)
    return {
        name: link.ifname || "",
        mac: link.address || "",
        mtu: link.mtu || 0,
        state: (link.operstate || "").toLowerCase(),
        ipv4: addresses("inet"),
        ipv6: addresses("inet6")
    }
}

// `ip -j addr show dev X`: that one link, or null.
function parseIpAddr(text) {
    let link
    try {
        link = JSON.parse(text)[0]
    } catch (e) {
        return null
    }
    return link ? linkInfo(link) : null
}

// `ip -j addr show`: every link that has an address to show.
function parseIpLinks(text) {
    let links
    try {
        links = JSON.parse(text)
    } catch (e) {
        return []
    }
    if (!Array.isArray(links)) return []
    return links.map(linkInfo).filter(l => l.ipv4.length > 0 || l.ipv6.length > 0)
}

// `ip -j route show default`: which interface each default route leaves by.
function parseDefaultRoutes(text) {
    let routes
    try {
        routes = JSON.parse(text)
    } catch (e) {
        return []
    }
    if (!Array.isArray(routes)) return []
    return routes.map(r => ({ dev: r.dev || "", gateway: r.gateway || "", metric: r.metric || 0 }))
        .sort((a, b) => a.metric - b.metric)
}

// Bytes a second between two samples of an interface's counters
// ({ rx, tx, at } with `at` in ms) - 0 across a counter reset.
function rates(previous, next) {
    if (!previous || !next) return { rx: 0, tx: 0 }
    const seconds = (next.at - previous.at) / 1000
    if (seconds <= 0) return { rx: 0, tx: 0 }
    return {
        rx: Math.max(0, next.rx - previous.rx) / seconds,
        tx: Math.max(0, next.tx - previous.tx) / seconds
    }
}

// The last `max` values, `value` added.
function pushHistory(history, value, max) {
    const next = history.concat([value])
    return next.length > max ? next.slice(next.length - max) : next
}

function formatBytes(n) {
    const units = ["B", "KB", "MB", "GB", "TB"]
    let i = 0
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024
        i++
    }
    return (i === 0 ? Math.round(n) : n.toFixed(n < 10 ? 2 : n < 100 ? 1 : 0)) + " " + units[i]
}

function formatRate(bytesPerSecond) {
    return formatBytes(bytesPerSecond) + "/s"
}

// "2 h 05 min", "12 min", "45 s".
function formatDuration(seconds) {
    seconds = Math.max(0, Math.round(seconds))
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor(seconds % 86400 / 3600)
    const minutes = Math.floor(seconds % 3600 / 60)
    if (days > 0) return days + " d " + hours + " h"
    if (hours > 0) return hours + " h " + String(minutes).padStart(2, "0") + " min"
    if (minutes > 0) return minutes + " min"
    return seconds + " s"
}

// 0 - 4 bars for a 0 - 1 signal.
function signalBars(strength) {
    if (strength <= 0) return 0
    return Math.max(1, Math.min(4, Math.ceil(strength * 4)))
}

// What `systemctl show -p LoadState,ActiveState zerotier-one.service` says.
function parseServiceState(text) {
    const out = { installed: false, active: false }
    for (const line of text.split("\n")) {
        const kv = line.match(/^(\w+)=(.*)$/)
        if (!kv) continue
        if (kv[1] === "LoadState") out.installed = kv[2] === "loaded"
        else if (kv[1] === "ActiveState") out.active = kv[2] === "active" || kv[2] === "activating"
    }
    return out
}

// ZeroTier's interfaces in plain `nmcli` output: un-indented "name: state"
// lines whose name is ZeroTier's own "zt" + an id. NetworkManager lists them
// whether or not it manages them - usually not.
function parseZerotierInterfaces(text) {
    const out = []
    for (const line of text.split("\n")) {
        if (/^\s/.test(line)) continue
        const separator = line.lastIndexOf(": ")
        if (separator === -1) continue
        const name = line.slice(0, separator).trim()
        const state = line.slice(separator + 2).trim()
        if (!/^zt[0-9a-z]+$/i.test(name)) continue
        out.push({ name: name, state: state })
    }
    return out
}

// What sort of Bluetooth device it is, from the icon name BlueZ gives it.
var bluetoothKinds = {
    "input-gaming": "game controller",
    "input-mouse": "mouse",
    "input-keyboard": "keyboard",
    "input-tablet": "tablet",
    "audio-headset": "headset",
    "audio-headphones": "headphones",
    "audio-card": "speaker",
    "audio-speakers": "speaker",
    "phone": "phone",
    "computer": "computer",
    "video-display": "display",
    "camera-photo": "camera",
    "printer": "printer",
    "network-wireless": "network"
}

function bluetoothKind(icon) {
    return bluetoothKinds[icon] || (icon ? icon.replace(/-/g, " ") : "")
}

// "5180 MHz" as "5 GHz" - Wi-Fi's bands by frequency.
function band(frequency) {
    const mhz = parseInt(frequency, 10)
    if (!(mhz > 0)) return ""
    if (mhz >= 5925) return "6 GHz"
    if (mhz >= 4900) return "5 GHz"
    return "2.4 GHz"
}

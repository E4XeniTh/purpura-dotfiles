.pragma library

// Settings > Connections (NetworkSettings.qml), kept apart from it so it can
// be tested on its own: what state each node of the tree is in and what that
// looks like, what a right click does to it, when a battery counts as low,
// the tree's layout, the display names given to nodes, and the text parsing
// behind the details panel.

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

// ---------------- battery ----------------
// A node with a battery has a segmented bar beside it, lit up to its charge -
// red when it's low and not charging.
var lowBattery = 0.11

function batteryLow(fraction, charging) {
    return fraction < lowBattery && !charging
}

// ---------------- the tree ----------------
// A directory tree: every node on a row of its own, top to bottom in order,
// each indented a step (`indent`) past its parent and hung off a line - down
// from under the parent (`trunkInset` in from its left edge), then across to
// the row. `root` is { key, children }; anything else on a node is carried
// over. Returns the placed nodes in order (with depth, row, x, y and their
// parent's key), the lines to draw (`to` is the row an arm leads to, empty
// for a parent's trunk), the deepest level, and the height of it all.
function layoutList(root, m) {
    const nodes = []
    const lines = []
    const pitch = m.rowHeight + m.rowGap
    let row = 0
    let deepest = 0

    function place(node, depth, parentKey) {
        const placed = Object.assign({}, node, {
            depth: depth,
            row: row,
            x: depth * m.indent,
            y: row * pitch,
            parentKey: parentKey
        })
        delete placed.children
        nodes.push(placed)
        row++
        deepest = Math.max(deepest, depth)

        const children = node.children || []
        if (children.length === 0) return placed
        const trunk = placed.x + m.trunkInset
        let lastMiddle = 0
        for (const c of children) {
            const child = place(c, depth + 1, node.key)
            lastMiddle = child.y + m.rowHeight / 2
            lines.push({ x1: trunk, y1: lastMiddle, x2: child.x, y2: lastMiddle, to: child.key })
        }
        lines.push({ x1: trunk, y1: placed.y + m.rowHeight, x2: trunk, y2: lastMiddle, to: "" })
        return placed
    }

    place(root, 0, "")
    return { nodes: nodes, lines: lines, depth: deepest, height: row * pitch - m.rowGap }
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

// ---------------- icons ----------------
// The icon names a row tries, best first. The row tints its icon in the
// row's colour, so every symbolic name goes before any plain one: a plain
// icon tinted is just a silhouette.
function themed(names) {
    const out = []
    for (const n of names) {
        if (out.indexOf(n + "-symbolic") === -1) out.push(n + "-symbolic")
    }
    for (const n of names) {
        if (out.indexOf(n) === -1) out.push(n)
    }
    return out
}

// Solaar's "Kind:" to an icon.
var solaarKindIcons = {
    mouse: "input-mouse",
    trackball: "input-mouse",
    touchpad: "input-touchpad",
    keyboard: "input-keyboard",
    numpad: "input-keyboard",
    headset: "audio-headset",
    remote: "input-gaming"
}

// A Wi-Fi signal (0 - 1) as the icon themes' bars: freedesktop's words, and
// Breeze's percentages.
function wifiSignalIcons(strength) {
    if (!(strength > 0)) return ["network-wireless-offline", "network-wireless-signal-none", "network-wireless-0"]
    const word = strength >= 0.75 ? "excellent" : strength >= 0.5 ? "good" : strength >= 0.25 ? "ok" : "weak"
    const percent = Math.min(100, Math.max(20, Math.round(strength * 5) * 20))
    return ["network-wireless-signal-" + word, "network-wireless-" + percent]
}

// `info` carries what the icon depends on: laptop (host), kind (a Solaar
// device's), icon (a Bluetooth device's own, e.g. "input-gaming"), signal
// (a Wi-Fi network's), off (an adapter or device that's disabled), unplugged
// (an Ethernet port).
function nodeIcons(kind, info) {
    const i = info || {}
    switch (kind) {
    case "host":
        return themed(i.laptop ? ["computer-laptop", "laptop", "computer"] : ["computer"])
    case "solaarHub":
        return themed(["preferences-desktop-peripherals", "input-mouse"])
    case "solaar":
        return themed([solaarKindIcons[String(i.kind || "").toLowerCase()] || "input-mouse", "input-mouse"])
    case "wifiDevice":
        return themed(i.off ? ["network-wireless-disconnected", "network-wireless-offline", "network-wireless"] : ["network-wireless"])
    case "wifiNetwork":
        return themed(wifiSignalIcons(i.signal).concat(["network-wireless"]))
    case "btAdapter":
        return themed([i.off ? "bluetooth-disabled" : "bluetooth-active", "bluetooth", "preferences-system-bluetooth"])
    case "btDevice":
        return themed((i.icon ? [i.icon] : []).concat(["bluetooth", "preferences-system-bluetooth"]))
    case "ztService":
        return themed(["network-vpn"])
    case "ztNetwork":
        return themed(["network-workgroup", "network-vpn"])
    case "wiredDevice":
        return themed(i.off || i.unplugged ? ["network-wired-disconnected", "network-wired"] : ["network-wired"])
    case "wiredNetwork":
        return themed(i.off ? ["network-wired-disconnected", "network-wired"] : ["network-wired-activated", "network-wired"])
    default:
        return []
    }
}

// "5180 MHz" as "5 GHz" - Wi-Fi's bands by frequency.
function band(frequency) {
    const mhz = parseInt(frequency, 10)
    if (!(mhz > 0)) return ""
    if (mhz >= 5925) return "6 GHz"
    if (mhz >= 4900) return "5 GHz"
    return "2.4 GHz"
}

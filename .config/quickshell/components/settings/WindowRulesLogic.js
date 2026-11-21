.pragma library

// Settings > General > Windows (WindowRules.qml): how each app picked there
// looks as it starts and opens. purpura.lua's How apps open makes a Hyprland
// window rule of each, matched on its windows' initial class. A rule here:
//   { app: the class,
//     layout: "" (as the app opens itself) | "tile" | "float" | "maximize" | "fullscreen",
//     width, height, center: floating only,
//     opacity: 0.1 - 1,
//     animation: "" (hyprland.lua's) | "popin" | "slide" | "gnomed" | "none" }

var LAYOUTS = [
    { value: "", label: "As it likes" },
    { value: "tile", label: "Tiled" },
    { value: "float", label: "Floating" },
    { value: "maximize", label: "Maximized" },
    { value: "fullscreen", label: "Fullscreen" }
]

var ANIMATIONS = [
    { value: "", label: "Default" },
    { value: "popin", label: "Pop in" },
    { value: "slide", label: "Slide in" },
    { value: "gnomed", label: "Unfold" },
    { value: "none", label: "None" }
]

// kitty's floating window, pre-included - the size hyprland.lua.example's
// "kittyrule" gives it, unless the hyprland.lua there is says otherwise.
var KITTY_WIDTH = 1500
var KITTY_HEIGHT = 760

var MIN_SIZE = 100
var MAX_SIZE = 16384

// A class purpura.lua takes: letters, digits, spaces and . _ + - only.
function validApp(app) {
    return typeof app === "string" && /^[A-Za-z0-9._+ -]{1,128}$/.test(app) && app.trim().length > 0
}

function valueIn(list, value) {
    return list.some(o => o.value === value) ? value : ""
}

function indexIn(list, value) {
    const i = list.findIndex(o => o.value === value)
    return i < 0 ? 0 : i
}

function clampSize(n, fallback) {
    const v = Math.round(Number(n))
    if (!isFinite(v)) return fallback
    return Math.max(MIN_SIZE, Math.min(MAX_SIZE, v))
}

function clampOpacity(n) {
    const v = Number(n)
    if (!isFinite(v)) return 1
    return Math.round(Math.max(0.1, Math.min(1, v)) * 20) / 20
}

// Every field there, and only what purpura.lua would take.
function normalize(rule) {
    const r = rule || {}
    return {
        app: String(r.app || ""),
        layout: valueIn(LAYOUTS, r.layout),
        width: clampSize(r.width, KITTY_WIDTH),
        height: clampSize(r.height, KITTY_HEIGHT),
        center: r.center === true,
        opacity: clampOpacity(r.opacity === undefined ? 1 : r.opacity),
        animation: valueIn(ANIMATIONS, r.animation)
    }
}

// windowrules.json's list, each rule normalized and every app once - or null
// when there's no list there to go by.
function parseStore(text) {
    let parsed
    try {
        parsed = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!parsed || !Array.isArray(parsed.rules)) return null
    const seen = {}
    const out = []
    for (const r of parsed.rules) {
        const rule = normalize(r)
        if (!validApp(rule.app) || seen[rule.app]) continue
        seen[rule.app] = true
        out.push(rule)
    }
    return out
}

// The size hyprland.lua's own "kittyrule" gives kitty, if it's there: the
// rule's lines from its name to the next rule, `size = "W H"` among them.
function kittySize(hyprlandText) {
    const text = String(hyprlandText || "")
    const at = text.search(/name\s*=\s*"kittyrule"/)
    if (at < 0) return null
    const rest = text.slice(at)
    const next = rest.indexOf("hl.window_rule", 1)
    const block = next < 0 ? rest : rest.slice(0, next)
    const m = block.match(/size\s*=\s*"\s*(\d+)\s+(\d+)\s*"/)
    if (!m) return null
    return { width: clampSize(m[1], KITTY_WIDTH), height: clampSize(m[2], KITTY_HEIGHT) }
}

// The list before anything's been changed here: kitty's floating window.
function defaults(hyprlandText) {
    const size = kittySize(hyprlandText) || { width: KITTY_WIDTH, height: KITTY_HEIGHT }
    return [normalize({ app: "kitty", layout: "float", width: size.width, height: size.height })]
}

function labelOf(list, value) {
    const found = list.find(o => o.value === value)
    return found ? found.label : ""
}

// One line on what a rule does, for its row in the list.
function summary(rule) {
    const r = normalize(rule)
    const parts = []
    if (r.layout === "float") {
        parts.push("Floating, " + r.width + " × " + r.height + (r.center ? ", centered" : ""))
    } else if (r.layout !== "") {
        parts.push(labelOf(LAYOUTS, r.layout))
    }
    if (r.opacity < 1) parts.push(Math.round(r.opacity * 100) + "% opaque")
    if (r.animation === "none") parts.push("no animation")
    else if (r.animation !== "") parts.push(labelOf(ANIMATIONS, r.animation).toLowerCase())
    if (parts.length === 0) return "Opens as it likes"
    const text = parts.join(", ")
    return text.charAt(0).toUpperCase() + text.slice(1)
}

// The list as a Lua table, as purpura.windowRules() and windowrules.lua take
// it: only what's set, so nothing set means no rule. The class is checked
// before it gets here, and every other string is one of the lists' own.
function luaList(rules) {
    const items = []
    for (const rule of rules) {
        const r = normalize(rule)
        if (!validApp(r.app)) continue
        const fields = ["app = " + JSON.stringify(r.app)]
        if (r.layout !== "") fields.push("layout = " + JSON.stringify(r.layout))
        if (r.layout === "float") {
            fields.push("width = " + r.width, "height = " + r.height)
            if (r.center) fields.push("center = true")
        }
        if (r.opacity < 1) fields.push("opacity = " + r.opacity.toFixed(2))
        if (r.animation !== "") fields.push("animation = " + JSON.stringify(r.animation))
        items.push("{ " + fields.join(", ") + " }")
    }
    return "{ " + items.join(", ") + " }"
}

function fileText(rules) {
    return "-- Written by the shell's Settings > General > Windows (kept in\n"
        + "-- ~/.config/quickshell/windowrules.json) - change it there. purpura.lua's\n"
        + "-- How apps open reads it once the config has loaded.\n"
        + "return " + luaList(rules) + "\n"
}

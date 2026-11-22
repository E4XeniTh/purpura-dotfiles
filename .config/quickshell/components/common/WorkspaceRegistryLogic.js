.pragma library

// The book workspace.lua keeps of Hyprland's workspaces (WORKSPACES there), as the
// shell reads it from $XDG_RUNTIME_DIR/purpura-workspaces.json:
//   { instance,
//     monitors: { "<name>": { workspaces: [Hyprland ids], pins: [1-5] } },
//     workspaces: { "<Hyprland id>": { id, number, type, monitor, since, app?, window? } } }
// - each monitor's assigned workspaces (its pins, or its spare) and what Display
// settings' buttons picked for it; each workspace's purpura number and type:
// pinned (the only managed one), spare, fullscreen, new or other.

var TYPES = ["pinned", "spare", "fullscreen", "new", "other"]

function isName(name) {
    return typeof name === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(name)
}

function isInt(n) {
    return typeof n === "number" && Number.isInteger(n)
}

// The file's text, checked - or null when it isn't one (not there, or caught
// mid-write).
function parse(text) {
    let parsed
    try {
        parsed = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
    const monitors = {}
    const rawMonitors = parsed.monitors && typeof parsed.monitors === "object" ? parsed.monitors : {}
    for (const name in rawMonitors) {
        const m = rawMonitors[name]
        if (!isName(name) || !m || typeof m !== "object") continue
        monitors[name] = {
            workspaces: Array.isArray(m.workspaces) ? m.workspaces.filter(isInt) : [],
            pins: Array.isArray(m.pins) ? m.pins.filter(n => isInt(n) && n >= 1 && n <= 5) : []
        }
    }
    const workspaces = {}
    const raw = parsed.workspaces && typeof parsed.workspaces === "object" ? parsed.workspaces : {}
    for (const key in raw) {
        const e = raw[key]
        const id = parseInt(key, 10)
        if (!e || typeof e !== "object" || !isInt(id) || String(id) !== key) continue
        if (!isInt(e.number) || TYPES.indexOf(e.type) < 0) continue
        workspaces[id] = {
            id: id,
            number: e.number,
            type: e.type,
            monitor: isName(e.monitor) ? e.monitor : "",
            app: typeof e.app === "string" ? e.app : "",
            window: typeof e.window === "string" ? e.window : ""
        }
    }
    return { monitors: monitors, workspaces: workspaces }
}

function entryOf(book, id) {
    return (book && book.workspaces[id]) || null
}

// The number purpura shows for that Hyprland workspace: the book's - else, with no
// book or one not seen yet, its own when it's one of 1-5. -1: none to show.
function numberOf(book, id) {
    const e = entryOf(book, id)
    if (e) return e.number
    return isInt(id) && id >= 1 && id <= 5 ? id : -1
}

function typeOf(book, id) {
    const e = entryOf(book, id)
    return e ? e.type : "other"
}

// One Display settings pinned - the only managed kind. With no book at all
// (workspace.lua not loaded), 1-5 count as managed, as they did by number.
function isManaged(book, id) {
    if (!book) return isInt(id) && id >= 1 && id <= 5
    return typeOf(book, id) === "pinned"
}

// What Display settings' buttons picked for that monitor - null when the book
// hasn't any for it.
function pinsOf(book, name) {
    return book && book.monitors[name] ? book.monitors[name].pins : null
}

// That monitor's assigned workspaces (its pins, or its spare), by Hyprland id.
function assignedOf(book, name) {
    return book && book.monitors[name] ? book.monitors[name].workspaces : []
}

// Every monitor the book has, with what's assigned to it and what was picked for
// it - the shape Display settings goes by.
function monitorsOf(book) {
    return book ? book.monitors : {}
}

// In number order - one without a number (no book, or one it hasn't seen) after
// the rest, by id.
function byNumber(book) {
    const key = w => {
        const n = numberOf(book, w.id)
        return n >= 1 ? n : 1e6 + w.id
    }
    return (a, b) => key(a) - key(b)
}

// The workspace widget's boxes: `list` is Hyprland's workspaces as
// { id, monitor (name), rank (the monitor's place, left to right), empty, shown },
// and comes back filtered and in order - by monitor, then number.
//   A workspace that's empty and not on screen only with opts.showEmpty (Show Empty
//   Workspaces In Widget) - Display settings' are kept by Hyprland, there or not.
//   A monitor with managed workspaces of its own shows its unmanaged ones, every
//   one. One without (a monitor none of 1-5 is pinned to) shows them only when it
//   has two or more, unless opts.showSingle (Show Single Workspace Monitors). Which
//   monitors have managed ones goes by all Hyprland has, empty and hidden ones
//   included: the pins are there whether they get a box or not.
function rowWorkspaces(book, list, opts) {
    const o = opts || {}
    const managedOn = {}
    for (const w of list) {
        if (w.monitor && isManaged(book, w.id)) managedOn[w.monitor] = true
    }
    const kept = list.filter(w => !w.monitor || o.showEmpty || !w.empty || w.shown)
    const unmanagedOn = {}
    for (const w of kept) {
        if (w.monitor && !isManaged(book, w.id)) unmanagedOn[w.monitor] = (unmanagedOn[w.monitor] || 0) + 1
    }
    const order = byNumber(book)
    return kept
        .filter(w => !w.monitor || isManaged(book, w.id) || managedOn[w.monitor] || o.showSingle
            || unmanagedOn[w.monitor] >= 2)
        .sort((a, b) => a.rank !== b.rank ? a.rank - b.rank : order(a, b))
}

// The workspace OSD's boxes for one monitor, by number: once it has more than one
// workspace, every one - managed or not, an app's own, one with a window fullscreen
// on it - with an empty one not on screen only with opts.showEmpty (Show Empty
// Workspaces In OSD); a monitor with just the one, none. opts.signalled (a
// fullscreen app's own, just given) gets one either way.
//   `list` is Hyprland's workspaces as { id, monitor (name), empty, shown,
// persistent }. What a monitor has goes by what Hyprland keeps: an empty workspace
// that's neither on screen nor persistent is one it's about to remove (one just
// switched away from), so it neither counts nor gets a box. Numbered ones only - a
// special workspace (a scratchpad) isn't one of a monitor's own, and Quickshell has
// every unnumbered one as -1. Two entries for one id (one Hyprland's just made
// again, for a moment) count once, the one with a monitor kept.
function osdWorkspaces(book, list, monitorName, opts) {
    const o = opts || {}
    const byId = new Map()
    for (const w of list) {
        if (!isInt(w.id) || w.id < 1) continue
        const prev = byId.get(w.id)
        if (!prev || (!prev.monitor && w.monitor)) byId.set(w.id, w)
    }
    const signalled = w => w.id === o.signalled
    const mine = Array.from(byId.values())
        .filter(w => w.monitor === monitorName && (!w.empty || w.shown || w.persistent || signalled(w)))
    const boxed = mine.filter(w => o.showEmpty || !w.empty || w.shown || signalled(w))
    return (mine.length >= 2 ? boxed : boxed.filter(signalled)).sort(byNumber(book))
}

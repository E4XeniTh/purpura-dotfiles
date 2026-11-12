.pragma library

// The decisions behind Idle.qml (Settings > Shell > Power), kept apart from
// the QML so they're plain functions of their inputs.
//
// Three stages, each counted from the one before it when that one's on:
//   lock     after `lockMinutes` without activity
//   dim      `dimMinutes` after that (or after `dimMinutes` without
//            activity, with auto-lock off) - the monitors fade to black
//            with a moon on them. Per monitor, each goes by its own
//            inactivity, `dimMinutes` of it, without waiting for the lock:
//            a monitor nobody's using dims while another is in use
//   suspend  `suspendMinutes` after every monitor's dimmed and the screen's
//            locked - counted down on the primary monitor the whole time,
//            after counting down to the lock if every monitor dimmed before
//            it (per-monitor dimming can) - or, without auto-dim,
//            `suspendMinutes` after the lock (or without activity), with
//            the screens going black for the last 30 seconds' countdown
// Activity is input, or anything keeping the computer awake (a video
// playing, an idle_inhibit window rule, a D-Bus inhibitor).

// ---------------- settings ----------------
// The stored settings (powersettings.json) with their defaults and limits.
function readSettings(store) {
    const s = store || {}
    const autoLock = s.autoLock !== false
    return {
        autoLock: autoLock,
        lockMinutes: wholeNumber(s.lockMinutes, 10, 1),
        lockWarning: s.lockWarning !== false,
        showTime: s.showTime !== false,
        showMedia: s.showMedia !== false,
        autoDim: s.autoDim === true,
        dimMinutes: wholeNumber(s.dimMinutes, 5, 1),
        dimOpacity: Math.min(100, wholeNumber(s.dimOpacity, 100, 50)),
        dimShowActive: s.dimShowActive !== false,
        // `perMonitor` and `autoSleep` are what these were called when
        // auto-suspend was "auto-sleep" and per-monitor belonged to it.
        dimPerMonitor: s.dimPerMonitor !== undefined ? s.dimPerMonitor === true : s.perMonitor === true,
        autoSuspend: s.autoSuspend !== undefined ? s.autoSuspend === true : s.autoSleep === true,
        suspendMinutes: wholeNumber(s.suspendMinutes, 30, 1),
        // Always on while auto-lock is: suspending unlocked would otherwise
        // skip a lock the computer was about to get anyway.
        wakeUpLock: autoLock || s.wakeUpLock !== false,
        wakeUpLockForced: autoLock
    }
}

// A positive whole number from `value`, `fallback` if there isn't one, and
// never below `min`.
function wholeNumber(value, fallback, min) {
    const n = Math.round(Number(value))
    return Math.max(min, isFinite(n) && n > 0 ? n : fallback)
}

function minutesPatch(key, minutes) {
    const patch = {}
    patch[key] = Math.max(1, Math.round(minutes))
    return patch
}

function dimOpacityPatch(percent) {
    return { dimOpacity: Math.min(100, Math.max(50, Math.round(percent))) }
}

// The seconds without activity at which each stage starts (null when it's
// off). `suspendDelay` counts from every monitor being dimmed when auto-dim
// is on; `suspendAt` is only set without it.
function thresholds(s) {
    const lockAt = s.autoLock ? s.lockMinutes * 60 : null
    const base = s.autoLock ? lockAt : 0
    // Per monitor, dimming doesn't wait for the lock (see the top).
    const dimAt = s.autoDim ? (s.dimPerMonitor ? 0 : base) + s.dimMinutes * 60 : null
    return {
        lockAt: lockAt,
        warnAt: s.autoLock && s.lockWarning && s.lockMinutes >= 2 ? lockAt - 60 : null,
        dimAt: dimAt,
        suspendDelay: s.autoSuspend ? (s.autoDim ? s.suspendMinutes * 60 : 30) : null,
        suspendAt: s.autoSuspend && !s.autoDim ? base + s.suspendMinutes * 60 : null
    }
}

// The labels in the settings, which change with what's on above them.
function dimDelayLabel(s) {
    return s.autoLock && !s.dimPerMonitor ? "min in lock state" : "min of inactivity"
}

function suspendDelayLabel(s) {
    if (s.autoDim && s.autoLock) return "min in lock & dim state"
    if (s.autoDim) return "min in dim state"
    if (s.autoLock) return "min in lock state"
    return "min of inactivity"
}

// ---------------- the stages ----------------
// One step, run every second and whenever something changes. `state`:
//   phase          "awake", or "suspended" (asked to suspend; until there's
//                  activity again)
//   readySince     when every monitor was last found dimmed (ms), null if not
//   held           won't suspend again before there's been activity - set
//                  when suspending didn't work
//   lockFired, warnFired   this idle stretch's lock/warning has been done
// `input`:
//   settings   readSettings()
//   now        ms
//   idle       seconds since the last activity anywhere
//   monitors   [{ name, idle }] - each monitor's own seconds without
//              activity (input with it focused, or a window on it keeping
//              the computer awake)
//   locked     the lock screen's up
//   forced     monitors dimmed by Focus mode, whatever their inactivity
// Returns { state, actions, dimmed, active, countdown }:
//   actions    any of "lock", "warn", "suspend"
//   dimmed     the monitors that show the black screen
//   active     with per-monitor dimming or Focus mode, the monitors still
//              active
//   countdown  seconds left before suspending - or, with every monitor
//              dimmed before the lock, before locking - or -1
//   countdownFor  "suspend", "lock" or ""
function step(state, input) {
    const s = input.settings
    const t = thresholds(s)
    // In whole seconds, to the nearest, like every threshold. The ticks
    // this runs on come a few milliseconds early or late: against unrounded
    // time a countdown would show a second twice or skip one, and the lock
    // could come a tick after its countdown had reached 1.
    const idle = Math.round(input.idle)
    const names = input.monitors.map(m => m.name)
    const next = {
        phase: state.phase,
        readySince: state.readySince,
        held: state.held,
        lockFired: state.lockFired,
        warnFired: state.warnFired
    }
    const actions = []

    if (idle < 2) {
        next.held = false
        if (next.phase === "suspended") next.phase = "awake"
    }

    // Lock, and the warning a minute before it: once per idle stretch.
    if (t.lockAt !== null && idle >= t.lockAt) {
        if (!next.lockFired && !input.locked) actions.push("lock")
        next.lockFired = true
    } else {
        next.lockFired = false
    }
    if (t.warnAt !== null && idle >= t.warnAt) {
        // Not once it's locking anyway.
        if (!next.warnFired && !input.locked && idle < t.lockAt) actions.push("warn")
        next.warnFired = true
    } else {
        next.warnFired = false
    }

    // Dim: every monitor together, or each by its own inactivity - and any
    // Focus mode dimmed, whether auto-dim's on or not.
    let byIdle = []
    if (t.dimAt !== null) {
        if (s.dimPerMonitor) byIdle = input.monitors.filter(m => Math.round(m.idle) >= t.dimAt).map(m => m.name)
        else if (idle >= t.dimAt) byIdle = names.slice()
    }
    const forced = input.forced || []
    const dimmed = names.filter(name => byIdle.indexOf(name) >= 0 || forced.indexOf(name) >= 0)
    const byMonitor = (t.dimAt !== null && s.dimPerMonitor) || forced.some(name => names.indexOf(name) >= 0)
    const stillActive = byMonitor ? names.filter(name => dimmed.indexOf(name) < 0) : []

    // In lock state: locked, or auto-lock's time is up (so a lock that
    // didn't come up can't hold everything after it back). Always, without
    // auto-lock.
    const lockReached = t.lockAt === null || input.locked || idle >= t.lockAt

    // Suspend: counted from being in lock state with every monitor dimmed
    // (and nothing at all keeping the computer awake), or the last 30
    // seconds before the delay without auto-dim. Per-monitor dimming can
    // dim every monitor before the lock; until the lock, the countdown is
    // to that instead.
    let ready = false
    let lockCountdown = -1
    if (next.phase === "awake") {
        if (s.autoDim) {
            const allDimmed = names.length > 0 && dimmed.length === names.length && idle >= t.dimAt
            if (allDimmed && !lockReached) lockCountdown = Math.max(1, t.lockAt - idle)
            ready = t.suspendDelay !== null && !next.held && allDimmed && lockReached
        } else if (t.suspendDelay !== null && !next.held) {
            ready = idle >= t.suspendAt - 30
        }
    }
    if (!ready) next.readySince = null
    else if (next.readySince === null || next.readySince === undefined) next.readySince = input.now

    // The minute's warning is already on screen as the lock countdown.
    if (lockCountdown >= 0 && actions.indexOf("warn") >= 0) actions.splice(actions.indexOf("warn"), 1)

    // The time since, in whole seconds to the nearest, for the same reason
    // as `idle` above.
    let countdown = lockCountdown
    let countdownFor = lockCountdown >= 0 ? "lock" : ""
    if (next.readySince !== null && next.readySince !== undefined) {
        countdown = Math.max(0, t.suspendDelay - Math.round((input.now - next.readySince) / 1000))
        countdownFor = "suspend"
        if (countdown === 0) {
            next.phase = "suspended"
            next.readySince = null
            countdown = -1
            countdownFor = ""
            actions.push("suspend")
        }
    }

    return { state: next, actions: actions, dimmed: dimmed, active: stillActive, countdown: countdown, countdownFor: countdownFor }
}

// What a monitor shows:
//   "countdown"  black, the moon, and on the primary monitor the countdown
//                to locking or suspending (every monitor, once it's
//                counting down or suspended - but see "black")
//   "black"      nothing but black, all the way: without auto-dim, every
//                monitor but the primary while it counts down
//   "dimmed"     black and a dimmer moon, with per-monitor dimming the
//                names of those still active
//   "none"
// `primary` is the primary monitor's name, `autoDim` the setting.
function overlay(name, phase, countdown, dimmed, primary, autoDim) {
    if (phase === "suspended" || countdown >= 0) return autoDim || name === primary ? "countdown" : "black"
    if (dimmed.indexOf(name) >= 0) return "dimmed"
    return "none"
}

// `what` is step()'s countdownFor: "lock" or "suspend".
function countdownText(seconds, what) {
    const doing = what === "lock" ? "locking in " : "suspending in "
    if (seconds >= 60) {
        const m = Math.floor(seconds / 60)
        const sec = seconds % 60
        return doing + m + ":" + (sec < 10 ? "0" : "") + sec + "..."
    }
    return doing + seconds + " second" + (seconds === 1 ? "" : "s") + "..."
}

function activeText(names) {
    return names.length ? "active: " + names.join(", ") : ""
}

// ---------------- per-monitor activity ----------------
// `stamps` maps a monitor's name to when it last had activity (ms).

// `stamps` with `names` marked active at `now` - a new object.
function stamp(stamps, names, now) {
    const out = Object.assign({}, stamps)
    for (const name of names) out[name] = now
    return out
}

// `stamps` with a fresh stamp for any monitor it doesn't know yet, so a
// monitor only counts as idle after a whole delay of being watched. The
// same object back if nothing was missing.
function withDefaults(stamps, names, now) {
    const missing = names.filter(name => stamps[name] === undefined)
    return missing.length ? stamp(stamps, missing, now) : stamps
}

// [{ name, idle }] in seconds, from the stamps.
function monitorIdle(names, stamps, now) {
    return names.map(name => ({ name: name, idle: Math.max(0, (now - (stamps[name] !== undefined ? stamps[name] : now)) / 1000) }))
}

// The monitors with a window that keeps the computer awake on them (a video
// playing, an idle-inhibit window rule): `clients` is `hyprctl clients -j`,
// `monitors` is [{ id, name }].
function inhibitedMonitors(clients, monitors) {
    const names = []
    for (const client of clients || []) {
        if (!client || client.inhibitingIdle !== true) continue
        const monitor = monitors.find(m => m.id === client.monitor)
        if (monitor && names.indexOf(monitor.name) < 0) names.push(monitor.name)
    }
    return names
}

// Where the apps behind D-Bus inhibitors (helpers/idle_inhibit) have their
// windows: { names, unmatched } - unmatched when an inhibitor's process has
// no window (a sandboxed app, a background service), so it can't be put
// down to any one monitor.
function monitorsForPids(clients, monitors, pids) {
    const names = []
    let unmatched = false
    for (const pid of pids) {
        const own = (clients || []).filter(client => client && client.pid === pid)
        if (!own.length) {
            unmatched = true
            continue
        }
        for (const client of own) {
            const monitor = monitors.find(m => m.id === client.monitor)
            if (monitor && names.indexOf(monitor.name) < 0) names.push(monitor.name)
        }
    }
    return { names: names, unmatched: unmatched }
}

// The D-Bus/systemd side of what's keeping the computer awake, from
// helpers/idle_inhibit's state file: { pids, systemd, any }.
function readExternal(text) {
    let state = null
    try {
        state = JSON.parse(text)
    } catch (e) {
        return { pids: [], systemd: false, any: false }
    }
    const inhibitors = state && Array.isArray(state.inhibitors) ? state.inhibitors : []
    const pids = inhibitors.map(i => Number(i.pid) || 0)
    const systemd = !!(state && state.systemd === true)
    return { pids: pids, systemd: systemd, any: inhibitors.length > 0 || systemd }
}

function sameList(a, b) {
    return a.length === b.length && a.every((item, i) => item === b[i])
}

// ---------------- Focus mode ----------------
// The monitors Focus mode dims: all but the one the mouse is on.
function focusTargets(names, focused) {
    return names.filter(name => name !== focused)
}

// Focus mode's monitors once `name` has been used (the mouse moved onto
// it, or input while it has focus): that one's awake again.
function focusWake(forced, name) {
    return forced.filter(other => other !== name)
}

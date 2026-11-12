.pragma library

// The decisions behind Idle.qml (Settings > Shell > Power), kept apart from
// the QML so they're plain functions of their inputs.

// ---------------- settings ----------------
// The stored settings (powersettings.json) with their defaults and limits:
// auto-lock after at least a minute, auto-sleep at least 5 minutes after
// the lock would, a countdown of 10-240 seconds.
function readSettings(store) {
    const s = store || {}
    const lockMinutes = wholeNumber(s.lockMinutes, 10, 1)
    const minSleepMinutes = lockMinutes + 5
    return {
        autoLock: s.autoLock !== false,
        lockMinutes: lockMinutes,
        showTime: s.showTime !== false,
        showMedia: s.showMedia !== false,
        autoSleep: s.autoSleep === true,
        minSleepMinutes: minSleepMinutes,
        sleepMinutes: wholeNumber(s.sleepMinutes, 60, minSleepMinutes),
        wakeUpLock: s.wakeUpLock !== false,
        perMonitor: s.perMonitor === true,
        countdown: s.countdown !== false,
        countdownSeconds: Math.min(240, wholeNumber(s.countdownSeconds, 30, 10))
    }
}

// A positive whole number from `value`, `fallback` if there isn't one, and
// never below `min`.
function wholeNumber(value, fallback, min) {
    const n = Math.round(Number(value))
    return Math.max(min, isFinite(n) && n > 0 ? n : fallback)
}

// What to store for a new auto-lock delay. Auto-sleep's delay is stored as
// it's shown, so a minimum it was raised to doesn't drop back down when
// the lock's delay later does.
function lockMinutesPatch(current, minutes) {
    const lockMinutes = Math.max(1, Math.round(minutes))
    return {
        lockMinutes: lockMinutes,
        sleepMinutes: Math.max(current.sleepMinutes, lockMinutes + 5)
    }
}

function sleepMinutesPatch(current, minutes) {
    return { sleepMinutes: Math.max(current.minSleepMinutes, Math.round(minutes)) }
}

function countdownSecondsPatch(seconds) {
    return { countdownSeconds: Math.min(240, Math.max(10, Math.round(seconds))) }
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

// The monitors that have gone `delayMs` without activity.
function idleMonitors(names, stamps, now, delayMs) {
    return names.filter(name => stamps[name] !== undefined && now - stamps[name] >= delayMs)
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

function sameList(a, b) {
    return a.length === b.length && a.every((item, i) => item === b[i])
}

// ---------------- sleeping ----------------
// One step of auto-sleep. `state` is { phase, left, held }:
//   phase  "awake", "countdown" (the screens are black and counting down),
//          or "asleep" (asked to sleep; until there's activity again)
//   left   seconds left on the countdown
//   held   won't sleep again before there's been activity - set after
//          waking up, or when sleeping didn't work
// `input`:
//   autoSleep, perMonitor, countdown, countdownSeconds   the settings
//   globalIdle   no input for the whole delay, and nothing keeping the
//                computer awake (the inhibitor-respecting idle monitor)
//   activeCount  per-monitor: how many monitors still count as active
//   resumed      the computer has just woken up
//   tick         a second has passed (counts the countdown down)
// Returns { state, action }, action being "sleep" or "".
function step(state, input) {
    const next = { phase: state.phase, left: state.left, held: state.held }
    let action = ""

    if (!input.autoSleep) return { state: { phase: "awake", left: 0, held: false }, action: action }

    // Woken up: start over, and not straight back to sleep - a computer
    // woken by its lid or power button hasn't seen any input yet.
    if (input.resumed) return { state: { phase: "awake", left: 0, held: true }, action: action }

    if (!input.globalIdle) next.held = false

    const allIdle = input.globalIdle && (!input.perMonitor || input.activeCount === 0)

    if (next.phase === "awake") {
        if (allIdle && !next.held) {
            if (input.countdown) {
                next.phase = "countdown"
                next.left = input.countdownSeconds
            } else {
                next.phase = "asleep"
                action = "sleep"
            }
        }
    } else if (next.phase === "countdown") {
        if (!allIdle) {
            next.phase = "awake"
            next.left = 0
        } else if (input.tick) {
            next.left -= 1
            if (next.left <= 0) {
                next.phase = "asleep"
                next.left = 0
                action = "sleep"
            }
        }
    } else if (next.phase === "asleep") {
        if (!input.globalIdle) next.phase = "awake"
    }

    return { state: next, action: action }
}

// What a monitor shows: "presleep" (black, the moon, and on the primary
// monitor the countdown), "waiting" (per-monitor: this one's idle, others
// aren't yet) or "none".
function overlay(name, phase, perMonitor, idleNames) {
    if (phase === "countdown" || phase === "asleep") return "presleep"
    if (perMonitor && idleNames.indexOf(name) >= 0) return "waiting"
    return "none"
}

function countdownText(seconds) {
    return "sleeping in " + seconds + " second" + (seconds === 1 ? "" : "s") + "..."
}

function activeText(names) {
    return names.length ? "active: " + names.join(", ") : "kept awake by an app"
}

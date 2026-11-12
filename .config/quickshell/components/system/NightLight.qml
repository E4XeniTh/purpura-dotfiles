import Quickshell
import Quickshell.Io
import QtQuick

// Night light: tints the screen warm through hyprsunset, driven live over
// `hyprctl hyprsunset`. A manual toggle, a strength, an optional daily
// schedule, and a fade that eases the tint in or out over a set time
// whenever it turns on or off.
//
// Unlike the other settings categories, this owns its settings file
// (nightlightsettings.json) instead of only reading it: the schedule flips
// `enabled` on its own, at times the settings screen usually isn't open.
// ShellSettings.qml's Night Light category is a view onto this object,
// handed down from shell.qml through SettingsScreen.qml.
Scope {
    id: root

    // ---------------- settings ----------------
    property var store: ({})
    property bool storeReady: false

    readonly property bool enabled: root.store.enabled === true
    readonly property real strength: {
        const n = Number(root.store.strength)
        return (root.store.strength !== undefined && !isNaN(n)) ? Math.max(0, Math.min(1, n)) : 0.5
    }
    readonly property bool scheduled: root.store.scheduled === true
    // Minutes since midnight.
    readonly property int scheduleStart: root.minutesOr(root.store.scheduleStart, 21 * 60)
    readonly property int scheduleEnd: root.minutesOr(root.store.scheduleEnd, 7 * 60)
    // Fade length is a number plus a unit. A file from before the unit
    // existed only has fadeMinutes, which reads as that many minutes.
    readonly property string fadeUnit: root.store.fadeUnit === "seconds" ? "seconds" : "minutes"
    readonly property int maxFadeAmount: root.fadeUnit === "seconds" ? 240 * 60 : 240
    readonly property int fadeAmount: {
        const raw = root.store.fadeAmount !== undefined ? root.store.fadeAmount : root.store.fadeMinutes
        const n = Number(raw)
        return (raw !== undefined && Number.isInteger(n) && n >= 0) ? Math.min(n, root.maxFadeAmount) : 5
    }
    readonly property real fadeMs: root.fadeAmount * (root.fadeUnit === "seconds" ? 1000 : 60000)

    function minutesOr(raw, fallback) {
        const n = Number(raw)
        return (raw !== undefined && Number.isInteger(n) && n >= 0 && n < 1440) ? n : fallback
    }

    function update(patch) {
        root.store = Object.assign({}, root.store, patch)
        writeTimer.restart()
    }

    function setEnabled(on) { root.update({ enabled: !!on }) }
    function setStrength(value) { root.update({ strength: Math.round(Math.max(0, Math.min(1, value)) * 100) / 100 }) }
    function setScheduled(on) { root.update({ scheduled: !!on }) }
    function setSchedule(start, end) { root.update({ scheduleStart: start, scheduleEnd: end }) }
    function setFadeAmount(amount) { root.update({ fadeAmount: Math.max(0, Math.min(root.maxFadeAmount, amount)) }) }

    // Keeps the number and changes what it counts (5 minutes -> 5
    // seconds), the way a unit picker beside a number field reads.
    function setFadeUnit(unit) {
        const max = unit === "seconds" ? 240 * 60 : 240
        root.update({ fadeUnit: unit, fadeAmount: Math.min(root.fadeAmount, max) })
    }

    // Not watched: this is the only writer, and reloading after our own
    // (debounced) write could clobber an edit made in between.
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/nightlightsettings.json"

        onLoaded: {
            try {
                root.store = JSON.parse(settingsFile.text()) || {}
            } catch (e) {
                root.store = {}
            }
            root.storeReady = true
            root.maybeStart()
        }
        // No file yet on a fresh install - start from the defaults.
        onLoadFailed: (error) => {
            root.storeReady = true
            root.maybeStart()
        }
    }

    // Debounced so dragging the strength slider doesn't write on every
    // pixel.
    Timer {
        id: writeTimer
        interval: 400
        repeat: false
        onTriggered: settingsFile.setText(JSON.stringify(root.store, null, 2) + "\n")
    }

    // ---------------- colour temperature ----------------
    // Strength maps linearly in mireds (1e6 / kelvin), not kelvin, so equal
    // slider steps - and equal fade steps - look like equal changes in
    // warmth instead of crawling at the warm end.
    readonly property real neutralMired: 1e6 / 6500
    readonly property real warmestMired: 1e6 / 2000

    function miredFor(strength) {
        return root.neutralMired + (root.warmestMired - root.neutralMired) * strength
    }

    readonly property real targetMired: root.enabled ? root.miredFor(root.strength) : root.neutralMired

    // What the screen is showing right now - eased toward targetMired
    // while fading.
    property real currentMired: root.neutralMired

    // ---------------- fade ----------------
    property bool fading: false
    property real fadeFrom: 0
    property real fadeStartMs: 0
    property real fadeDurationMs: 0

    // A reversal partway through only takes the share of the fade time
    // that's actually left to undo, so toggling twice quickly doesn't
    // start a full-length fade back from almost nowhere.
    function startFade() {
        if (!root.started) return
        const distance = Math.abs(root.targetMired - root.currentMired)
        const full = Math.abs(root.miredFor(root.strength) - root.neutralMired)
        const totalMs = root.fadeMs
        if (totalMs <= 0 || distance < 0.5 || full < 0.5) {
            root.fading = false
            fadeTimer.stop()
            root.currentMired = root.targetMired
            root.push()
            return
        }
        root.fadeFrom = root.currentMired
        root.fadeStartMs = Date.now()
        root.fadeDurationMs = totalMs * Math.min(1, distance / full)
        root.fading = true
        fadeTimer.restart()
        root.tick()
    }

    // Progress comes from the clock, not a tick count, so a suspend mid-fade
    // just finishes it on wake.
    function tick() {
        if (!root.fading) return
        const progress = Math.min(1, (Date.now() - root.fadeStartMs) / root.fadeDurationMs)
        root.currentMired = root.fadeFrom + (root.targetMired - root.fadeFrom) * progress
        if (progress >= 1) {
            root.fading = false
            fadeTimer.stop()
        }
        root.push()
    }

    Timer {
        id: fadeTimer
        interval: 1000
        repeat: true
        onTriggered: root.tick()
    }

    onEnabledChanged: root.startFade()

    // Strength edits apply straight away (it's a live preview while
    // dragging); mid-fade, tick() already eases toward the new target.
    onStrengthChanged: {
        if (root.started && root.enabled && !root.fading) {
            root.currentMired = root.targetMired
            root.push()
        }
    }

    // ---------------- schedule ----------------
    function minutesNow() {
        const d = new Date()
        return d.getHours() * 60 + d.getMinutes()
    }

    // start === end is the whole day - what TimeRangeSlider shows for its
    // handles at opposite ends (noon to noon).
    function inWindow(now, start, end) {
        if (start === end) return true
        return start < end ? (now >= start && now < end) : (now >= start || now < end)
    }

    property bool lastInWindow: false

    // Brings the toggle in line with the window right away - when the
    // schedule is switched on or edited, and at startup. Between those, a
    // manual toggle holds until the next start or end time.
    function syncSchedule() {
        if (!root.scheduled) return
        root.lastInWindow = root.inWindow(root.minutesNow(), root.scheduleStart, root.scheduleEnd)
        if (root.enabled !== root.lastInWindow) root.setEnabled(root.lastInWindow)
    }

    onScheduledChanged: if (root.started) root.syncSchedule()
    onScheduleStartChanged: if (root.started) root.syncSchedule()
    onScheduleEndChanged: if (root.started) root.syncSchedule()

    // Compares in/out of the window rather than watching for an exact
    // minute, so a start/end time that passes during suspend still flips it.
    Timer {
        interval: 20000
        repeat: true
        running: root.started && root.scheduled
        onTriggered: {
            const inside = root.inWindow(root.minutesNow(), root.scheduleStart, root.scheduleEnd)
            if (inside !== root.lastInWindow) {
                root.lastInWindow = inside
                root.setEnabled(inside)
            }
        }
    }

    // ---------------- hyprsunset ----------------
    property bool available: false
    property bool availabilityKnown: false
    // hyprsunset kept exiting right after starting - given up on until the
    // next shell restart.
    property bool failed: false
    readonly property bool usable: root.available && !root.failed

    Process {
        command: ["sh", "-c", "command -v hyprsunset"]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0
            root.availabilityKnown = true
            root.maybeStart()
        }
    }

    property bool started: false

    // Startup applies the saved state instantly - only an actual toggle
    // fades. syncSchedule() runs before `started` is set for that reason:
    // startFade() ignores the flip it may cause.
    function maybeStart() {
        if (root.started || !root.storeReady || !root.availabilityKnown) return
        root.syncSchedule()
        root.started = true
        root.currentMired = root.targetMired
        if (root.available) root.spawnDaemon()
    }

    // 0 = identity (no tint at all).
    function desiredKelvin() {
        if (!root.enabled && !root.fading) return 0
        return Math.round(1e6 / root.currentMired / 10) * 10
    }

    // Kept running for the whole session, even while off (at identity):
    // it then always owns the tint, so a shell reload can't leave a stale
    // one behind - the fresh instance starts at the right value.
    property bool daemonUp: false
    property real daemonSpawnedMs: 0
    property int quickExits: 0

    // Off starts at a neutral 6500K and is switched to true identity over
    // IPC once it's up (lastSentKelvin = -1 makes push() send it) - only
    // `-t` and the IPC commands are relied on, not a startup identity flag.
    function spawnDaemon() {
        const k = root.desiredKelvin()
        hyprsunsetProcess.command = ["hyprsunset", "-t", String(k === 0 ? 6500 : k)]
        root.lastSentKelvin = k === 0 ? -1 : k
        root.daemonUp = false
        root.daemonSpawnedMs = Date.now()
        hyprsunsetProcess.running = true
        daemonReadyTimer.restart()
    }

    Process {
        id: hyprsunsetProcess
        onExited: (exitCode, exitStatus) => {
            root.daemonUp = false
            daemonReadyTimer.stop()
            root.quickExits = (Date.now() - root.daemonSpawnedMs < 10000) ? root.quickExits + 1 : 0
            if (root.quickExits >= 3) {
                root.failed = true
                return
            }
            daemonRestartTimer.restart()
        }
    }

    // Its IPC socket isn't up the instant the process starts.
    Timer {
        id: daemonReadyTimer
        interval: 1000
        repeat: false
        onTriggered: {
            root.daemonUp = hyprsunsetProcess.running
            root.push()
        }
    }

    Timer {
        id: daemonRestartTimer
        interval: 3000
        repeat: false
        onTriggered: root.spawnDaemon()
    }

    // One hyprctl call in flight at a time; anything that changes meanwhile
    // goes out when it returns, so a fast slider drag sends at the rate
    // hyprsunset can keep up with.
    property int lastSentKelvin: -1
    property int inFlightKelvin: -1
    property bool sendQueued: false

    function push() {
        if (!root.daemonUp) return
        const k = root.desiredKelvin()
        if (k === root.lastSentKelvin) return
        if (ipcProcess.running) {
            root.sendQueued = true
            return
        }
        ipcProcess.command = k === 0 ? ["hyprctl", "hyprsunset", "identity"] : ["hyprctl", "hyprsunset", "temperature", String(k)]
        root.inFlightKelvin = k
        ipcProcess.running = true
    }

    Process {
        id: ipcProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.lastSentKelvin = root.inFlightKelvin
            } else {
                ipcRetryTimer.restart()
            }
            if (root.sendQueued) {
                root.sendQueued = false
                root.push()
            }
        }
    }

    Timer {
        id: ipcRetryTimer
        interval: 1000
        repeat: false
        onTriggered: root.push()
    }
}

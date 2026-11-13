import Quickshell
import Quickshell.Io
import QtQuick
import "NightLightLogic.js" as Fade

// Night light: tints the screen warm through hyprsunset, driven live over
// `hyprctl hyprsunset`. A manual toggle, a strength, an optional daily
// schedule, and a fade that eases the tint in or out over a set time when
// the schedule turns it on or off - through hyprsunset's 100 K steps, with
// Hyprland gliding between them (see NightLightLogic.js). Switched by hand,
// it changes at once.
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

    // By hand: at once.
    function setEnabled(on) { root.update({ enabled: !!on }) }

    // By the schedule: faded. onEnabledChanged runs inside update(), so the
    // flag is still up when it looks.
    property bool scheduleSwitching: false
    function scheduleSetEnabled(on) {
        root.scheduleSwitching = true
        root.update({ enabled: !!on })
        root.scheduleSwitching = false
    }
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

    // What the screen is heading to - the end of a fade, or where it is.
    property real currentMired: root.neutralMired

    // ---------------- fade ----------------
    property bool fading: false
    property real fadeFrom: 0
    property real fadeTo: 0
    property real fadeStartMs: 0
    property real fadeDurationMs: 0
    property bool stepIsLast: false

    // How quickly anything that isn't a fade glides: a strength change, a
    // fade set to 0, and the last bit of fading out, from 6500 K to no tint.
    readonly property int quickGlideMs: 300

    // `faded`: over the fade time, else the quick glide. A reversal
    // partway through only takes the share of the fade time that's
    // actually left to undo, so toggling twice quickly doesn't start a
    // full-length fade back from almost nowhere.
    function startFade(faded) {
        if (!root.started) return
        // Worked out here, from `enabled` itself, so it can't be a step
        // behind the change that called this.
        const target = root.enabled ? root.miredFor(root.strength) : root.neutralMired
        const distance = Math.abs(target - root.currentMired)
        const full = Math.abs(root.miredFor(root.strength) - root.neutralMired)
        fadeTimer.stop()
        if (!faded || root.fadeMs <= 0 || distance < 0.5 || full < 0.5) {
            root.fading = false
            root.currentMired = target
            root.show(root.quickGlideMs)
            return
        }
        root.fadeFrom = root.currentMired
        root.fadeTo = target
        root.fadeStartMs = Date.now()
        root.fadeDurationMs = root.fadeMs * Math.min(1, distance / full)
        root.fading = true
        root.step()
    }

    // The next step, and a wait until it's due. Timed off the clock, so a
    // suspend mid-fade just finishes it on wake.
    function step() {
        if (!root.fading) return
        const next = Fade.nextStep(root.fadeFrom, root.fadeTo, root.fadeDurationMs,
                                   Date.now() - root.fadeStartMs, Math.round(1e6 / root.currentMired))
        root.currentMired = next.last ? root.fadeTo : 1e6 / next.kelvin
        root.stepIsLast = next.last
        root.send(next.kelvin, next.glideMs)
        fadeTimer.interval = Math.max(1, Math.round(next.waitMs))
        fadeTimer.restart()
    }

    Timer {
        id: fadeTimer

        repeat: false
        onTriggered: {
            if (!root.stepIsLast) {
                root.step()
                return
            }
            root.fading = false
            // Faded out to 6500 K: now no tint at all.
            if (!root.enabled) root.show(root.quickGlideMs)
        }
    }

    onEnabledChanged: root.startFade(root.scheduleSwitching)

    // Strength edits apply straight away (it's a live preview while
    // dragging); mid-fade, the fade carries on toward the new strength.
    onStrengthChanged: {
        if (!root.started || !root.enabled) return
        if (root.fading) {
            root.startFade(true)
        } else {
            root.currentMired = root.miredFor(root.strength)
            root.show(root.quickGlideMs)
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
        if (root.enabled !== root.lastInWindow) root.scheduleSetEnabled(root.lastInWindow)
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
                root.scheduleSetEnabled(inside)
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
        root.currentMired = root.enabled ? root.miredFor(root.strength) : root.neutralMired
        if (root.available) root.spawnDaemon()
    }

    // 0 = identity (no tint at all).
    function desiredKelvin() {
        if (!root.enabled && !root.fading) return 0
        return Math.round(1e6 / root.currentMired)
    }

    // Where things stand now, gliding there over `glideMs`.
    function show(glideMs) {
        root.send(root.desiredKelvin(), glideMs)
    }

    // Kept running for the whole session, even while off (at identity):
    // it then always owns the tint, so a shell reload can't leave a stale
    // one behind - the fresh instance starts at the right value.
    property bool daemonUp: false
    property real daemonSpawnedMs: 0
    property int quickExits: 0

    // Off starts at a neutral 6500K and is switched to true identity over
    // IPC once it's up (lastSentKelvin = -1 makes send() send it) - only
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
            if (root.queued) {
                const request = root.queued
                root.queued = null
                root.send(request.kelvin, request.glideMs)
            } else {
                root.show(root.quickGlideMs)
            }
        }
    }

    Timer {
        id: daemonRestartTimer
        interval: 3000
        repeat: false
        onTriggered: root.spawnDaemon()
    }

    // ---------------- talking to hyprsunset ----------------
    // Each change goes out with how long Hyprland should glide to it: its
    // __internal_fadeCTM animation is set just before (a config reload puts
    // it back to half a second; the next change sets it again). One at a
    // time - a change asked for meanwhile waits, the latest replacing any
    // older one - so a fast slider drag sends at the rate hyprsunset can
    // keep up with.
    property int lastSentKelvin: -1
    property var queued: null
    property var inFlight: null

    function send(kelvin, glideMs) {
        const request = { kelvin: kelvin, glideMs: glideMs }
        if (!root.daemonUp || sendProcess.running) {
            root.queued = request
            return
        }
        root.queued = null
        if (kelvin === root.lastSentKelvin) return
        // Tenths of a second, 0.1 - 10.
        const speed = Math.max(1, Math.min(100, glideMs / 100))
        sendProcess.command = ["sh", "-c", "hyprctl eval \"$1\" >/dev/null 2>&1; hyprctl hyprsunset $2", "nightlight",
            "hl.animation({ leaf = \"__internal_fadeCTM\", enabled = true, speed = " + speed.toFixed(2) + ", bezier = \"linear\" })",
            kelvin === 0 ? "identity" : "temperature " + kelvin]
        root.inFlight = request
        sendProcess.running = true
    }

    Process {
        id: sendProcess

        onExited: (exitCode, exitStatus) => {
            const request = root.inFlight
            root.inFlight = null
            if (exitCode === 0) {
                root.lastSentKelvin = request.kelvin
            } else if (!root.queued) {
                // Try it again in a moment, unless something newer's waiting.
                root.queued = request
                sendRetryTimer.restart()
                return
            }
            if (root.queued) {
                const next = root.queued
                root.queued = null
                root.send(next.kelvin, next.glideMs)
            }
        }
    }

    Timer {
        id: sendRetryTimer

        interval: 1000
        repeat: false
        onTriggered: {
            if (!root.queued) return
            const request = root.queued
            root.queued = null
            root.send(request.kelvin, request.glideMs)
        }
    }
}

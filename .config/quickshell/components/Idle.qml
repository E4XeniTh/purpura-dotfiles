import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Config.js" as Config
import "IdleLogic.js" as Logic

// Settings > Shell > Power at work: locking the screen after a while
// without input, and putting the computer to sleep after a longer while.
// The decisions themselves are in IdleLogic.js.
//
// Idleness comes from Hyprland (IdleMonitor, ext-idle-notify-v1), which
// also counts anything keeping the computer awake - a Wayland idle
// inhibitor, the idle_inhibit window rules in hyprland.lua - as activity.
// Apps that ask over D-Bus instead (org.freedesktop.ScreenSaver - browsers
// playing a video, among others) or hold a systemd idle inhibitor lock
// are answered by helpers/idle_inhibit, and count too: see "kept awake
// over D-Bus" below.
//
// Auto-sleep, by its two options:
// - Countdown off: it sleeps the moment the delay is up.
// - Countdown on: every monitor fades to black with a moon on it first,
//   the primary one counting down; any input calls it off.
// - Per-monitor on: each monitor waits for its own inactivity - input on
//   it (it has focus: the mouse is on it), or a window on it keeping the
//   computer awake, counts. One that's idle while others aren't fades to
//   black with a dimmer moon and the names of those still active, and
//   only once they're all idle does the countdown start (or, without it,
//   the computer sleep).
// - Wake up lock: it locks before it sleeps, so it wakes up locked.
//
// The black screens are layers drawn above the lock screen (Hyprland's
// above_lock layer rule, which this sets itself - see applyLayerRule()).
//
// Like NightLight.qml, this owns its settings file (powersettings.json),
// and ShellSettings.qml's Power category is a view onto this object.
Scope {
    id: root

    property real shellScale: 1.0

    // LockScreen.qml, from shell.qml: what auto-lock and the wake up lock
    // lock, and where the primary monitor's name comes from.
    property var lockScreen: null

    // ---------------- settings ----------------
    property var store: ({})
    property bool settingsLoaded: false
    readonly property var settings: Logic.readSettings(root.store)

    readonly property bool autoLock: root.settings.autoLock
    readonly property int lockMinutes: root.settings.lockMinutes
    readonly property bool lockWarning: root.settings.lockWarning
    readonly property bool showTime: root.settings.showTime
    readonly property bool showMedia: root.settings.showMedia
    readonly property bool autoSleep: root.settings.autoSleep
    readonly property int sleepMinutes: root.settings.sleepMinutes
    readonly property int minSleepMinutes: root.settings.minSleepMinutes
    readonly property bool wakeUpLock: root.settings.wakeUpLock
    readonly property bool wakeUpLockForced: root.settings.wakeUpLockForced
    readonly property bool perMonitor: root.settings.perMonitor
    readonly property bool sleepCountdown: root.settings.countdown
    readonly property int countdownSeconds: root.settings.countdownSeconds

    function update(patch) {
        root.store = Object.assign({}, root.store, patch)
        writeTimer.restart()
    }

    function setAutoLock(on) { root.update({ autoLock: !!on }) }
    function setLockMinutes(minutes) { root.update(Logic.lockMinutesPatch(root.settings, minutes)) }
    function setLockWarning(on) { root.update({ lockWarning: !!on }) }
    function setShowTime(on) { root.update({ showTime: !!on }) }
    function setShowMedia(on) { root.update({ showMedia: !!on }) }
    function setAutoSleep(on) { root.update({ autoSleep: !!on }) }
    function setSleepMinutes(minutes) { root.update(Logic.sleepMinutesPatch(root.settings, minutes)) }
    function setWakeUpLock(on) { root.update({ wakeUpLock: !!on }) }
    function setPerMonitor(on) { root.update({ perMonitor: !!on }) }
    function setSleepCountdown(on) { root.update({ countdown: !!on }) }
    function setCountdownSeconds(seconds) { root.update(Logic.countdownSecondsPatch(seconds)) }

    // Not watched: this is the only writer, and reloading after our own
    // (debounced) write could clobber an edit made in between.
    FileView {
        id: settingsFile

        path: Quickshell.env("HOME") + "/.config/quickshell/powersettings.json"
        // A fresh install has no file yet - that's just the defaults.
        printErrors: false

        onLoaded: {
            try {
                root.store = JSON.parse(settingsFile.text()) || {}
            } catch (e) {
                root.store = {}
            }
            root.settingsLoaded = true
        }
        onLoadFailed: root.settingsLoaded = true
    }

    Timer {
        id: writeTimer

        interval: 400

        onTriggered: settingsFile.setText(JSON.stringify(root.store, null, 2) + "\n")
    }

    // ---------------- kept awake over D-Bus ----------------
    // helpers/idle_inhibit answers org.freedesktop.ScreenSaver and watches
    // systemd's idle inhibitor locks, keeping what's inhibiting in this file.
    // It runs on its own, outliving the shell: a reload would otherwise drop
    // every inhibitor, and apps only ask once. Starting it again is harmless
    // (a second one exits straight away), so it's started now and then in
    // case it isn't running.
    readonly property string inhibitorsPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/purpura/idle-inhibitors.json"

    FileView {
        id: inhibitorsFile

        path: root.inhibitorsPath
        watchChanges: true
        printErrors: false

        onFileChanged: inhibitorsFile.reload()
    }

    readonly property var external: Logic.readExternal(inhibitorsFile.text())

    // While anything's inhibiting this way, the idle monitors below are
    // switched off - and switched back on when it stops, which starts their
    // delays over from then, the same as a Wayland inhibitor ending does.
    readonly property bool externallyInhibited: root.external.any

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: Quickshell.execDetached([Quickshell.shellDir + "/helpers/idle_inhibit", root.inhibitorsPath])
    }

    // ---------------- auto-lock ----------------
    // Nothing waits on the settings' defaults before the file's been read:
    // an idle monitor starts its delay over whenever its settings change.
    IdleMonitor {
        id: lockIdle

        enabled: root.settingsLoaded && root.autoLock && !root.externallyInhibited
        timeout: root.lockMinutes * 60
        respectInhibitors: true

        onIsIdleChanged: {
            if (lockIdle.isIdle && root.lockScreen) root.lockScreen.lock()
        }
    }

    // A minute's warning ("Warn before auto-lock"), as hypridle used to
    // give. Only with a delay of 2 minutes or more, so it has a minute to
    // come before.
    IdleMonitor {
        id: lockWarningIdle

        enabled: root.settingsLoaded && root.autoLock && root.lockWarning && root.lockMinutes >= 2 && !root.externallyInhibited
        timeout: (root.lockMinutes - 1) * 60
        respectInhibitors: true

        onIsIdleChanged: {
            if (!lockWarningIdle.isIdle || (root.lockScreen && root.lockScreen.locked)) return
            const minutes = root.lockMinutes - 1
            Quickshell.execDetached([
                "notify-send", "-i", "system-suspend-uninhibited", "AFK",
                minutes + " minute" + (minutes === 1 ? "" : "s") + " of inactivity has passed.\nLocking screen in 1 minute."
            ])
        }
    }

    // ---------------- auto-sleep ----------------
    // No input for the whole delay, with nothing keeping the computer awake.
    IdleMonitor {
        id: sleepIdle

        enabled: root.settingsLoaded && root.autoSleep && !root.externallyInhibited
        timeout: root.sleepMinutes * 60
        respectInhibitors: true

        onIsIdleChanged: root.evaluate(false)
    }

    property string phase: "awake"
    property int countdownLeft: 0
    property bool held: false

    // Wall-clock time of the last tick. Timers don't run while the computer
    // sleeps but the clock does, so a big gap between ticks means it's just
    // woken up.
    property real lastTick: 0

    onAutoSleepChanged: root.evaluate(false)
    onPerMonitorChanged: {
        root.stamps = ({})
        root.evaluate(false)
    }

    // Runs everything that changes with time: per-monitor idleness, the
    // countdown, noticing a wake-up. Also called straight away whenever
    // something it depends on changes.
    function evaluate(tick) {
        const now = Date.now()
        const resumed = tick && root.lastTick > 0 && now - root.lastTick > 15000
        if (tick) root.lastTick = now

        const names = Quickshell.screens.map(s => s.name)
        if (resumed) root.stamps = Logic.stamp({}, names, now)
        else root.stamps = Logic.withDefaults(root.stamps, names, now)

        const tracking = root.settingsLoaded && root.autoSleep && root.perMonitor
        const idle = tracking ? Logic.idleMonitors(names, root.stamps, now, root.sleepMinutes * 60000) : []
        const active = tracking ? names.filter(name => idle.indexOf(name) < 0) : []
        if (!Logic.sameList(idle, root.idleNames)) root.idleNames = idle
        if (!Logic.sameList(active, root.activeNames)) root.activeNames = active

        const result = Logic.step({ phase: root.phase, left: root.countdownLeft, held: root.held }, {
            autoSleep: root.settingsLoaded && root.autoSleep,
            perMonitor: root.perMonitor,
            countdown: root.sleepCountdown,
            countdownSeconds: root.countdownSeconds,
            globalIdle: sleepIdle.isIdle,
            activeCount: active.length,
            resumed: resumed,
            tick: tick
        })
        root.phase = result.state.phase
        root.countdownLeft = result.state.left
        root.held = result.state.held
        if (result.action === "sleep") root.goToSleep()
    }

    Timer {
        id: ticker

        interval: 1000
        repeat: true
        running: root.settingsLoaded && root.autoSleep

        // A stale tick from before the last time it stopped isn't a wake-up.
        onRunningChanged: root.lastTick = 0

        onTriggered: {
            if (inputIdle.enabled && !inputIdle.isIdle) root.stampFocused()
            root.evaluate(true)
        }
    }

    // ---------------- per-monitor activity ----------------
    // Monitor name -> when it last had activity (ms).
    property var stamps: ({})
    property var idleNames: []
    property var activeNames: []

    function markActive(name) {
        if (!name || !root.perMonitor || !root.autoSleep) return
        root.stamps = Logic.stamp(root.stamps, [name], Date.now())
        root.evaluate(false)
    }

    function stampFocused() {
        if (Hyprland.focusedMonitor) root.stamps = Logic.stamp(root.stamps, [Hyprland.focusedMonitor.name], Date.now())
    }

    // Any input at all, a second at a time, put down to the monitor with
    // focus - the one the mouse is on.
    IdleMonitor {
        id: inputIdle

        enabled: root.settingsLoaded && root.autoSleep && root.perMonitor
        timeout: 1
        respectInhibitors: false

        onIsIdleChanged: {
            if (!inputIdle.isIdle && Hyprland.focusedMonitor) root.markActive(Hyprland.focusedMonitor.name)
        }
    }

    Connections {
        target: Hyprland

        // The mouse moving onto another monitor is activity there.
        function onFocusedMonitorChanged() {
            if (Hyprland.focusedMonitor) root.markActive(Hyprland.focusedMonitor.name)
        }

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.applyLayerRule()
        }
    }

    // A monitor with a window keeping the computer awake counts as active
    // the whole time. Hyprland doesn't announce that, so it's asked - and
    // asked straight away when a D-Bus inhibitor comes or goes.
    Timer {
        id: clientsTimer

        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: root.settingsLoaded && root.autoSleep && root.perMonitor

        onTriggered: {
            clientsProcess.running = false
            clientsProcess.running = true
        }
    }

    onExternalChanged: {
        if (clientsTimer.running) clientsTimer.triggered()
    }

    Process {
        id: clientsProcess

        command: ["hyprctl", "clients", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                let clients = []
                try {
                    clients = JSON.parse(text)
                } catch (e) {
                    return
                }
                const monitors = Hyprland.monitors.values.map(m => ({ id: m.id, name: m.name }))
                let inhibited = Logic.inhibitedMonitors(clients, monitors)

                // D-Bus inhibitors count on the monitors their app's windows
                // are on; one with no window to go by (or a systemd lock)
                // keeps every monitor awake.
                const external = Logic.monitorsForPids(clients, monitors, root.external.pids)
                if (root.external.systemd || external.unmatched) inhibited = monitors.map(m => m.name)
                else inhibited = inhibited.concat(external.names)

                if (inhibited.length) root.stamps = Logic.stamp(root.stamps, inhibited, Date.now())
            }
        }
    }

    // ---------------- sleeping ----------------
    function goToSleep() {
        if (root.wakeUpLock && root.lockScreen && !root.lockScreen.locked) {
            root.lockScreen.lock()
            lockWaitTimer.restart()
        } else {
            root.suspend()
        }
    }

    // Asleep locked: the lock goes up first, so waking up shows it rather
    // than the desktop. Hyprland confirms it's covering every screen within
    // a frame or two; this doesn't wait forever for that.
    Timer {
        id: lockWaitTimer

        interval: 3000

        onTriggered: root.suspend()
    }

    Connections {
        target: root.lockScreen

        function onSecureChanged() {
            if (lockWaitTimer.running && root.lockScreen.secure) {
                lockWaitTimer.stop()
                root.suspend()
            }
        }
    }

    function suspend() {
        lockWaitTimer.stop()
        // Woken up again before it got this far.
        if (root.phase !== "asleep") return
        suspendProcess.running = false
        suspendProcess.running = true
    }

    Process {
        id: suspendProcess

        command: ["systemctl", "suspend"]

        stderr: StdioCollector {
            id: suspendErrors
        }

        // Turned down (an inhibitor lock, say): back to awake, and no
        // trying again before there's been some activity.
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) return
            root.phase = "awake"
            root.held = true
            const reason = suspendErrors.text.trim()
            Quickshell.execDetached([
                "notify-send", "-a", "Power", "-i", "system-suspend-symbolic",
                "Couldn't put the computer to sleep",
                reason || "systemctl suspend failed."
            ])
        }
    }

    // ---------------- the black screens ----------------
    // Above the lock screen too, so the countdown shows over it.
    function applyLayerRule() {
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.layer_rule({ name = \"purpura-idle-above-lock\", match = { namespace = \"purpura-idle\" }, above_lock = 1 })"])
    }

    Component.onCompleted: root.applyLayerRule()

    readonly property string primaryName: root.lockScreen ? root.lockScreen.effectivePrimaryName : ""

    // The per-monitor label's "dark red".
    readonly property color darkRed: "#a11d1d"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            property var modelData
            screen: modelData

            readonly property string mode: Logic.overlay(win.modelData.name, root.phase, root.autoSleep && root.perMonitor, root.idleNames)
            readonly property bool isPrimary: win.modelData.name === root.primaryName

            // The shell-wide per-screen scale (see Config.uiScale).
            readonly property real uiScale: Config.uiScale(win.modelData, root.shellScale)

            WlrLayershell.namespace: "purpura-idle"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusiveZone: -1

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"

            // Stays up until it's faded out.
            visible: win.mode !== "none" || content.opacity > 0

            Item {
                id: content

                anchors.fill: parent

                readonly property bool shown: win.mode !== "none"

                // A slow fade to black, and straight back on activity.
                opacity: content.shown ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: content.shown ? 1500 : 300
                        easing.type: Easing.InOutQuad
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }

                Column {
                    anchors.centerIn: parent

                    spacing: Config.scaled(24, win.uiScale)

                    // A crescent moon: a disc with another, offset disc
                    // cut out of it. fgcolor while it's about to sleep,
                    // the dimmer purple while waiting on other monitors.
                    Canvas {
                        id: moon

                        anchors.horizontalCenter: parent.horizontalCenter

                        width: Config.scaled(160, win.uiScale)
                        height: moon.width

                        property color tint: win.mode === "waiting" ? Config.fgcolordark : Config.fgcolor

                        Behavior on tint {
                            ColorAnimation { duration: 400 }
                        }

                        onTintChanged: moon.requestPaint()
                        onWidthChanged: moon.requestPaint()
                        Component.onCompleted: moon.requestPaint()

                        onPaint: {
                            const ctx = moon.getContext("2d")
                            ctx.reset()
                            const r = moon.width / 2
                            ctx.fillStyle = moon.tint.toString()
                            ctx.beginPath()
                            ctx.arc(r, r, r * 0.9, 0, 2 * Math.PI)
                            ctx.fill()
                            ctx.globalCompositeOperation = "destination-out"
                            ctx.beginPath()
                            ctx.arc(r + r * 0.42, r - r * 0.28, r * 0.74, 0, 2 * Math.PI)
                            ctx.fill()
                            ctx.globalCompositeOperation = "source-over"
                        }
                    }

                    // The countdown - the primary monitor only.
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        visible: win.isPrimary && root.phase === "countdown"
                        text: Logic.countdownText(root.countdownLeft)
                        color: Config.fgcolordark
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(15, win.uiScale)
                        font.italic: true
                    }

                    // Per-monitor: which monitors are keeping it awake.
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        visible: win.mode === "waiting"
                        text: Logic.activeText(root.activeNames)
                        color: root.darkRed
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(15, win.uiScale)
                    }
                }

                // The mouse moving over a black screen wakes it straight away
                // (and a click on it can't land on whatever's underneath).
                // Under the lock screen the lock gets the mouse instead, and
                // the idle monitors notice the input on their own.
                MouseArea {
                    anchors.fill: parent

                    hoverEnabled: true

                    onPositionChanged: root.markActive(win.modelData.name)
                }
            }
        }
    }
}

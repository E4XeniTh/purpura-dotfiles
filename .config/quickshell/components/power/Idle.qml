import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../Config.js" as Config
import "IdleLogic.js" as Logic

// Settings > Shell > Power at work: locking the screen, dimming the
// monitors and suspending the computer after a while without activity,
// each stage counted from the one before it. The decisions themselves
// are in IdleLogic.js (see there for the stages); this measures the
// activity, carries out what they decide and draws the dimmed screens.
//
// Activity is input, or anything keeping the computer awake: Hyprland
// counts Wayland idle inhibitors and the idle_inhibit window rules in
// hyprland.lua, and apps that ask over D-Bus instead
// (org.freedesktop.ScreenSaver - browsers playing a video, among others)
// or hold a systemd idle inhibitor lock are answered by
// helpers/idle_inhibit (see "kept awake over D-Bus" below). How long
// it's been since any of that is measured here a second at a time, so
// changing a delay never starts the waiting over.
//
// With per-monitor dimming each monitor also has its own inactivity:
// input while it has focus (the mouse is on it), or a window on it
// keeping the computer awake. A dimmed one names the monitors still
// active; once every monitor's dimmed, the primary one counts down to
// suspending.
//
// The dimmed screens are layers drawn above the lock screen (Hyprland's
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
    readonly property bool autoDim: root.settings.autoDim
    readonly property int dimMinutes: root.settings.dimMinutes
    readonly property int dimOpacity: root.settings.dimOpacity
    readonly property bool dimPerMonitor: root.settings.dimPerMonitor
    readonly property bool autoSuspend: root.settings.autoSuspend
    readonly property int suspendMinutes: root.settings.suspendMinutes
    readonly property bool wakeUpLock: root.settings.wakeUpLock
    readonly property bool wakeUpLockForced: root.settings.wakeUpLockForced

    // The delays' labels, which depend on what's on before them.
    readonly property string dimDelayLabel: Logic.dimDelayLabel(root.settings)
    readonly property string suspendDelayLabel: Logic.suspendDelayLabel(root.settings)

    function update(patch) {
        root.store = Object.assign({}, root.store, patch)
        writeTimer.restart()
    }

    function setAutoLock(on) { root.update({ autoLock: !!on }) }
    function setLockMinutes(minutes) { root.update(Logic.minutesPatch("lockMinutes", minutes)) }
    function setLockWarning(on) { root.update({ lockWarning: !!on }) }
    function setShowTime(on) { root.update({ showTime: !!on }) }
    function setShowMedia(on) { root.update({ showMedia: !!on }) }
    function setAutoDim(on) { root.update({ autoDim: !!on }) }
    function setDimMinutes(minutes) { root.update(Logic.minutesPatch("dimMinutes", minutes)) }
    function setDimOpacity(percent) { root.update(Logic.dimOpacityPatch(percent)) }
    function setDimPerMonitor(on) { root.update({ dimPerMonitor: !!on }) }
    function setAutoSuspend(on) { root.update({ autoSuspend: !!on }) }
    function setSuspendMinutes(minutes) { root.update(Logic.minutesPatch("suspendMinutes", minutes)) }
    function setWakeUpLock(on) { root.update({ wakeUpLock: !!on }) }

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

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: Quickshell.execDetached([Quickshell.shellDir + "/helpers/idle_inhibit", root.inhibitorsPath])
    }

    // ---------------- activity ----------------
    // When there was last activity anywhere (ms).
    property real lastActivity: Date.now()

    // Input in the last second, or a Wayland inhibitor/idle_inhibit rule
    // keeping the computer awake: Hyprland only lets this go idle after a
    // second without either.
    IdleMonitor {
        id: activityIdle

        enabled: root.settingsLoaded
        timeout: 1
        respectInhibitors: true

        onIsIdleChanged: {
            if (!activityIdle.isIdle) root.evaluate(false)
        }
    }

    // Input alone, for per-monitor dimming: put down to the monitor with
    // focus.
    IdleMonitor {
        id: inputIdle

        enabled: root.settingsLoaded && root.autoDim && root.dimPerMonitor
        timeout: 1
        respectInhibitors: false

        onIsIdleChanged: {
            if (!inputIdle.isIdle) root.evaluate(false)
        }
    }

    // ---------------- per-monitor activity ----------------
    // Monitor name -> when it last had activity (ms).
    property var stamps: ({})

    readonly property bool tracking: root.settingsLoaded && root.autoDim && root.dimPerMonitor
    onTrackingChanged: root.stamps = ({})

    function markActive(name) {
        if (!name || !root.tracking) return
        root.stamps = Logic.stamp(root.stamps, [name], Date.now())
        root.evaluate(false)
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
        running: root.tracking

        onTriggered: {
            clientsProcess.running = false
            clientsProcess.running = true
        }
    }

    onExternalChanged: {
        if (clientsTimer.running) clientsTimer.triggered()
        root.evaluate(false)
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

    // ---------------- the stages ----------------
    property var stage: ({ phase: "awake", readySince: null, held: false, lockFired: false, warnFired: false })
    property var dimmedNames: []
    property var activeNames: []
    property int countdown: -1
    readonly property string phase: root.stage.phase

    // Wall-clock time of the last tick. Timers don't run while the computer
    // is suspended but the clock does, so a big gap between ticks means it's
    // just woken up.
    property real lastTick: 0

    function evaluate(tick) {
        if (!root.settingsLoaded) return
        const now = Date.now()
        const names = Quickshell.screens.map(s => s.name)

        if (tick && root.lastTick > 0 && now - root.lastTick > 15000) {
            // Woken up: everything starts over.
            root.lastActivity = now
            root.stamps = Logic.stamp({}, names, now)
            root.stage = { phase: "awake", readySince: null, held: false, lockFired: false, warnFired: false }
        }
        if (tick) root.lastTick = now

        if (!activityIdle.isIdle || root.external.any) root.lastActivity = now
        if (root.tracking) {
            let stamps = Logic.withDefaults(root.stamps, names, now)
            if (!inputIdle.isIdle && Hyprland.focusedMonitor) stamps = Logic.stamp(stamps, [Hyprland.focusedMonitor.name], now)
            root.stamps = stamps
        }

        const result = Logic.step(root.stage, {
            settings: root.settings,
            now: now,
            idle: Math.max(0, (now - root.lastActivity) / 1000),
            monitors: Logic.monitorIdle(names, root.stamps, now),
            locked: !!root.lockScreen && root.lockScreen.locked
        })

        root.stage = result.state
        if (!Logic.sameList(result.dimmed, root.dimmedNames)) root.dimmedNames = result.dimmed
        if (!Logic.sameList(result.active, root.activeNames)) root.activeNames = result.active
        root.countdown = result.countdown

        for (const action of result.actions) {
            if (action === "lock" && root.lockScreen) root.lockScreen.lock()
            else if (action === "warn") root.warnBeforeLock()
            else if (action === "suspend") root.suspendNow()
        }
    }

    onSettingsChanged: root.evaluate(false)

    Timer {
        interval: 1000
        repeat: true
        running: root.settingsLoaded

        onTriggered: root.evaluate(true)
    }

    // "Warn before auto-lock": a minute's notice, as hypridle used to give.
    function warnBeforeLock() {
        const minutes = root.lockMinutes - 1
        Quickshell.execDetached([
            "notify-send", "-i", "system-suspend-uninhibited", "AFK",
            minutes + " minute" + (minutes === 1 ? "" : "s") + " of inactivity has passed.\nLocking screen in 1 minute."
        ])
    }

    // ---------------- suspending ----------------
    function suspendNow() {
        if (root.wakeUpLock && root.lockScreen && !root.lockScreen.locked) {
            root.lockScreen.lock()
            lockWaitTimer.restart()
        } else {
            root.runSuspend()
        }
    }

    // Suspended locked: the lock goes up first, so waking up shows it rather
    // than the desktop. Hyprland confirms it's covering every screen within
    // a frame or two; this doesn't wait forever for that.
    Timer {
        id: lockWaitTimer

        interval: 3000

        onTriggered: root.runSuspend()
    }

    Connections {
        target: root.lockScreen

        function onSecureChanged() {
            if (lockWaitTimer.running && root.lockScreen.secure) {
                lockWaitTimer.stop()
                root.runSuspend()
            }
        }
    }

    function runSuspend() {
        lockWaitTimer.stop()
        // Woken up again before it got this far.
        if (root.phase !== "suspended") return
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
            root.stage = Object.assign({}, root.stage, { phase: "awake", readySince: null, held: true })
            const reason = suspendErrors.text.trim()
            Quickshell.execDetached([
                "notify-send", "-a", "Power", "-i", "system-suspend-symbolic",
                "Couldn't suspend the computer",
                reason || "systemctl suspend failed."
            ])
        }
    }

    // ---------------- the dimmed screens ----------------
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

            readonly property string mode: Logic.overlay(win.modelData.name, root.phase, root.countdown, root.dimmedNames)
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

                // "Dim opacity": how dark the screen goes. The moon and the
                // text stay solid.
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: root.dimOpacity / 100
                }

                Column {
                    anchors.centerIn: parent

                    spacing: Config.scaled(24, win.uiScale)

                    // A crescent moon: a disc with another, offset disc
                    // cut out of it. fgcolor once it's counting down to
                    // suspending, the dimmer purple while only dimmed.
                    Canvas {
                        id: moon

                        anchors.horizontalCenter: parent.horizontalCenter

                        width: Config.scaled(160, win.uiScale)
                        height: moon.width

                        property color tint: win.mode === "dimmed" ? Config.fgcolordark : Config.fgcolor

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

                        visible: win.isPrimary && root.countdown >= 0
                        text: Logic.countdownText(root.countdown)
                        color: Config.fgcolordark
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(15, win.uiScale)
                        font.italic: true
                    }

                    // Per-monitor: which monitors are still active.
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        visible: win.mode === "dimmed" && root.activeNames.length > 0
                        text: Logic.activeText(root.activeNames)
                        color: root.darkRed
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(15, win.uiScale)
                    }
                }

                // The mouse moving over a dimmed screen wakes it straight
                // away (and a click on it can't land on whatever's
                // underneath). Under the lock screen the lock gets the mouse
                // instead, and the idle monitors notice the input on their
                // own.
                MouseArea {
                    anchors.fill: parent

                    hoverEnabled: true

                    onPositionChanged: root.markActive(win.modelData.name)
                }
            }
        }
    }
}

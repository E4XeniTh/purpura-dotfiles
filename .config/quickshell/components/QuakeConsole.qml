import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../Config.js" as Config

// Quake console: the bar grows downward linearly, and a terminal appears in
// the space that opens up. Bar.qml draws the growing part from `expansion`;
// everything else lives here.
//
// Wayland can't embed another program's surface, so the terminal is really a
// `kitten panel`, kitty's own layer-shell surface, placed exactly over the
// bar's new area with a transparent background so the bar's colour shows
// through. It's on the overlay layer because the bar is on top: a surface
// above the bar keeps its text at full brightness.
//
// kitty starts the first time the console finishes opening. After that,
// closing only hides it, through kitty's remote control socket, so whatever's
// in it stays. It's a single Process, and a shell reload stops it, so there's
// only ever one. Should it end on its own (`exit`, a crash), the bar closes
// the same way as when closed by hand, and the next open starts a new one.
//
// While the console is closed, a hidden kitty with nothing running in its
// foreground gets stopped once the autokill delay has passed. One that's
// still running a command keeps being checked instead of being killed.
//
// Like NightLight.qml, this owns its settings file (quakesettings.json), and
// ShellSettings.qml's Quake Console category is a view onto this object.
Scope {
    id: root

    property real shellScale: 1.0
    // EdgeGaps.qml: the bar's padding from the screen's edges.
    property var edgeGaps: null
    // The bar only shows on this screen, and kitty can't change outputs once
    // it's running.
    property string screenName: ""
    property bool barHidden: false

    // ---------------- settings ----------------
    property var store: ({})

    function update(patch) {
        root.store = Object.assign({}, root.store, patch)
        writeTimer.restart()
    }

    function clamped(value, min, max) {
        return Math.round(Math.max(min, Math.min(max, value)))
    }

    function setWidthPercent(value) { root.update({ widthPercent: root.clamped(value, root.minWidthPercent, 100) }) }
    function setHeightPercent(value) { root.update({ heightPercent: root.clamped(value, root.minHeightPercent, 100) }) }
    function setAutokillEnabled(on) { root.update({ autokill: !!on }) }
    function setAutokillMinutes(value) { root.update({ autokillMinutes: Math.max(1, Math.round(value)) }) }

    readonly property int minWidthPercent: 25
    readonly property int minHeightPercent: 20
    readonly property int widthPercent: root.clamped(Number(root.store.widthPercent) || 100, root.minWidthPercent, 100)
    readonly property int heightPercent: root.clamped(Number(root.store.heightPercent) || 40, root.minHeightPercent, 100)

    readonly property bool autokillEnabled: root.store.autokill !== false
    readonly property int autokillMinutes: Math.max(1, Math.round(Number(root.store.autokillMinutes)) || 30)

    // Not watched: this is the only writer.
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/quakesettings.json"
        // A fresh install has no file yet - that's just the defaults.
        printErrors: false

        onLoaded: {
            try {
                root.store = JSON.parse(settingsFile.text()) || {}
            } catch (e) {
                root.store = {}
            }
        }
    }

    Timer {
        id: writeTimer
        interval: 400
        onTriggered: settingsFile.setText(JSON.stringify(root.store, null, 2) + "\n")
    }

    // ---------------- geometry ----------------
    readonly property var screen: Quickshell.screens.find(s => s.name === root.screenName) || null
    readonly property real uiScale: Config.uiScale(root.screen, root.shellScale)
    readonly property int borderWidth: Config.scaled(2, root.uiScale)
    readonly property int barHeight: Config.scaled(Config.barheight, root.uiScale)
    readonly property int edgeTop: root.edgeGaps ? root.edgeGaps.top : 10
    readonly property int edgeLeft: root.edgeGaps ? root.edgeGaps.left : 10
    readonly property int edgeRight: root.edgeGaps ? root.edgeGaps.right : 10
    readonly property int edgeBottom: root.edgeGaps ? root.edgeGaps.bottom : 10
    readonly property int barWidth: root.screen ? root.screen.width - root.edgeLeft - root.edgeRight : 800

    // Width is a share of the bar's, height of what's left under the bar down
    // to the bottom edge's padding, so 100% of both ends level with windows.
    readonly property int consoleWidth: Math.round(root.barWidth * root.widthPercent / 100)
    readonly property int consoleHeight: Math.round(
        ((root.screen ? root.screen.height : 600) - root.edgeTop - root.barHeight - root.edgeBottom) * root.heightPercent / 100)
    // How far in from the bar's left edge the console starts.
    readonly property int consoleOffset: Math.round((root.barWidth - root.consoleWidth) / 2)

    // The terminal fills the console inside its side and bottom borders. The
    // bar's own bottom border is the separator on top of it.
    readonly property var terminalGeometry: ({
        x: root.edgeLeft + root.consoleOffset + root.borderWidth,
        y: root.edgeTop + root.barHeight,
        width: root.consoleWidth - root.borderWidth * 2,
        height: root.consoleHeight - root.borderWidth
    })

    // ---------------- opening and closing ----------------
    // Whether the console is open or on its way there.
    property bool open: false
    // How far the bar has grown, from 0 to 1.
    property real expansion: 0
    // Whether any of it shows, which is what the bar sizes its window by.
    readonly property bool active: root.open || root.expansion > 0
    // Whether kitty's surface is meant to be up.
    property bool terminalShown: false

    readonly property int animationMs: 300
    // Hyprland's fade on a closing layer surface (layersOut in hyprland.lua),
    // which plays out before the bar starts closing around it.
    readonly property int surfaceFadeMs: 150

    function toggle() {
        if (root.open) root.closeConsole()
        else root.openConsole()
    }

    function openConsole() {
        if (root.barHidden || !root.screen) return
        root.open = true
        fadeTimer.stop()
        root.animateTo(1)
    }

    function closeConsole() {
        root.open = false
        if (root.terminalShown) {
            root.terminalShown = false
            root.control(["resize-os-window", "--match=all", "--action=hide"])
            fadeTimer.restart()
        } else {
            root.animateTo(0)
        }
    }

    function animateTo(value) {
        expandAnimation.stop()
        const distance = Math.abs(value - root.expansion)
        if (distance === 0) {
            root.expansionSettled()
            return
        }
        expandAnimation.to = value
        expandAnimation.duration = distance * root.animationMs
        expandAnimation.start()
    }

    function expansionSettled() {
        if (!root.open || root.terminalShown) return
        root.terminalShown = true
        if (terminal.running) {
            root.applyGeometry()
            root.control(["resize-os-window", "--match=all", "--action=show"])
        } else {
            root.startTerminal()
        }
    }

    NumberAnimation {
        id: expandAnimation
        target: root
        property: "expansion"
        easing.type: Easing.Linear
        onFinished: root.expansionSettled()
    }

    Timer {
        id: fadeTimer
        interval: root.surfaceFadeMs
        onTriggered: root.animateTo(0)
    }

    onBarHiddenChanged: if (root.barHidden && root.open) root.closeConsole()

    // ---------------- the terminal ----------------
    // A new name for every kitty, as it won't start on a socket file a crashed
    // one left behind.
    property string socket: ""

    function startTerminal() {
        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        const g = root.terminalGeometry
        root.socket = runtimeDir + "/purpura-quake-" + Date.now() + ".sock"
        root.appliedGeometry = root.geometryArgs()
        terminal.command = [
            "kitten", "panel",
            "--app-id=quakeconsole",
            "--edge=none",
            "--layer=overlay",
            "--focus-policy=on-demand",
            "--output-name=" + root.screenName,
            "--columns=" + g.width + "px",
            "--lines=" + g.height + "px",
            "--margin-left=" + g.x,
            "--margin-top=" + g.y,
            "--listen-on=unix:" + root.socket,
            "-o", "allow_remote_control=socket-only",
            "-o", "background_opacity=0",
            "-o", "window_margin_width=0",
            "-o", "single_window_margin_width=0",
            // A prompt nobody can see would leave it hanging.
            "-o", "confirm_os_window_close=0",
            // Tells fish's greeting to skip fastfetch.
            "-o", "env=PURPURA_QUAKE_CONSOLE=1"
        ]
        terminal.running = true
    }

    Process {
        id: terminal

        // Not onExited, which doesn't fire if it never managed to start.
        onRunningChanged: {
            if (terminal.running) return
            root.terminalShown = false
            root.controlQueue = []
            root.controlRetries = 0
            if (root.open) root.closeConsole()
        }
    }

    // A kitty left over from a shell that was killed outright can't be
    // reached any more, so it's stopped by name. The pattern needs kitty at
    // the start of the command line, so it can't hit a program that merely
    // mentions the flag.
    Process {
        command: ["pkill", "-f", "--", "^[^ ]*kitty[^ ]* .*--app-id=quakeconsole( |$)"]
        running: true
    }

    // kitty can't change outputs, so a new primary screen means a new kitty.
    onScreenNameChanged: if (terminal.running) terminal.running = false

    // ---------------- remote control ----------------
    // One command at a time, in order.
    property var controlQueue: []
    property int controlRetries: 0

    function control(args) {
        root.controlQueue.push(args)
        root.runControl()
    }

    function runControl() {
        if (controlProcess.running || root.controlQueue.length === 0) return
        controlProcess.command = ["kitten", "@", "--to", "unix:" + root.socket].concat(root.controlQueue[0])
        controlProcess.running = true
    }

    Process {
        id: controlProcess

        // kitty's socket isn't there yet if it's only just been started, as
        // when the console is closed again straight away.
        onExited: (exitCode) => {
            if (exitCode !== 0 && terminal.running && root.controlRetries < 20) {
                root.controlRetries++
                controlRetryTimer.start()
                return
            }
            root.controlRetries = 0
            root.controlQueue.shift()
            root.runControl()
        }
    }

    Timer {
        id: controlRetryTimer
        interval: 150
        onTriggered: root.runControl()
    }

    // ---------------- resizing a running kitty ----------------
    property var appliedGeometry: []

    function geometryArgs() {
        const g = root.terminalGeometry
        return ["columns=" + g.width + "px", "lines=" + g.height + "px", "margin-left=" + g.x, "margin-top=" + g.y]
    }

    function applyGeometry() {
        const args = root.geometryArgs()
        if (args.join() === root.appliedGeometry.join()) return
        root.appliedGeometry = args
        root.control(["resize-os-window", "--match=all", "--action=os-panel", "--incremental"].concat(args))
    }

    // A hidden kitty catches up when it's next shown.
    onTerminalGeometryChanged: if (root.terminalShown) resizeTimer.restart()

    Timer {
        id: resizeTimer
        interval: 100
        onTriggered: if (root.terminalShown) root.applyGeometry()
    }

    // ---------------- autokill ----------------
    // After a check found a command still running, look again each minute
    // rather than after another full delay.
    property bool autokillRechecking: false

    onOpenChanged: root.autokillRechecking = false

    Timer {
        interval: (root.autokillRechecking ? 1 : root.autokillMinutes) * 60000
        running: root.autokillEnabled && terminal.running && !root.open
        repeat: true
        onTriggered: idleCheck.running = true
    }

    // At a prompt, the only foreground process is the shell itself.
    function hasForegroundCommand(osWindows) {
        for (const osWindow of osWindows) {
            for (const tab of osWindow.tabs) {
                for (const window of tab.windows) {
                    if (window.foreground_processes.some(p => p.pid !== window.pid)) return true
                }
            }
        }
        return false
    }

    Process {
        id: idleCheck
        command: ["kitten", "@", "--to", "unix:" + root.socket, "ls"]

        stdout: StdioCollector {
            onStreamFinished: {
                // Stay on the safe side if kitty's answer can't be read.
                let busy = true
                try {
                    busy = root.hasForegroundCommand(JSON.parse(text))
                } catch (e) {
                    busy = true
                }
                if (busy) root.autokillRechecking = true
                else if (!root.open) terminal.running = false
            }
        }
    }

    // ---------------- triggers ----------------
    IpcHandler {
        target: "quakeconsole"

        function toggle(): void { root.toggle() }
        function show(): void { root.openConsole() }
        function hide(): void { root.closeConsole() }
    }

    GlobalShortcut {
        name: "quakeconsole"
        onPressed: root.toggle()
    }
}

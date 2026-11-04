import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../Config.js" as Config

// Dropdown console: a panel grows downward from under the bar, linearly, and a
// terminal appears in the space that opens up.
//
// The panel is a surface of its own rather than the bar getting taller. When a
// layer surface changes size, Hyprland draws its old buffer stretched to the
// new size until a new one arrives, which showed the bar blown up to the
// console's height on opening and squashed on closing. This surface never
// resizes. It doesn't map or unmap with the console either, as Hyprland fades
// a surface in when it maps: it stays up whenever the bar does, with nothing
// drawn and no clicks taken while the console is closed.
//
// kitty's surface can't be clipped to the panel either, so it's only up while
// the panel covers all the text on it: it appears as soon as the growing panel
// reaches the last line of text, and goes just before the shrinking panel does.
// A full screen of text therefore can't show until the panel is fully open. The
// layer rule for "dropdownconsole" in hyprland.lua turns off Hyprland's fades on
// it, which would otherwise leave its text fading outside the shrinking panel.
//
// Wayland can't embed another program's surface, so the terminal is really a
// `kitten panel`, kitty's own layer-shell surface, placed exactly over the
// panel with a transparent background so the panel's colour shows through.
// It's on the overlay layer because the panel is on top: a surface above the
// panel keeps its text at full brightness.
//
// kitty starts the first time the console opens. After that, closing only
// hides it, through kitty's remote control socket, so whatever's in it stays.
// It's a single Process, and a shell reload stops it, so there's only ever one.
// Should it end any other way (`exit`, a crash, the close window bind in
// hyprland.lua), the panel disappears with it rather than sliding away, and the
// next open starts a new one.
//
// While the console is closed, a hidden kitty with nothing running in its
// foreground gets stopped once the autokill delay has passed. One that's
// still running a command keeps being checked instead of being killed.
//
// Like NightLight.qml, this owns its settings file (dropdownconsolesettings.json), and
// ShellSettings.qml's Dropdown Console category is a view onto this object.
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
    function setFontSize(value) { root.update({ fontSize: root.clamped(value, root.minFontSize, root.maxFontSize) }) }
    function setAutokillEnabled(on) { root.update({ autokill: !!on }) }
    function setAutokillMinutes(value) { root.update({ autokillMinutes: Math.max(1, Math.round(value)) }) }
    function setAutokillNotification(on) { root.update({ autokillNotification: !!on }) }

    readonly property int minWidthPercent: 25
    readonly property int minHeightPercent: 20
    readonly property int widthPercent: root.clamped(Number(root.store.widthPercent) || 100, root.minWidthPercent, 100)
    readonly property int heightPercent: root.clamped(Number(root.store.heightPercent) || 40, root.minHeightPercent, 100)

    readonly property int minFontSize: 8
    readonly property int maxFontSize: 24
    // In pts: one of kitty's own 2pt zoom steps under kitty.conf's 16.
    readonly property int fontSize: root.clamped(Number(root.store.fontSize) || 14, root.minFontSize, root.maxFontSize)

    readonly property bool autokillEnabled: root.store.autokill !== false
    readonly property int autokillMinutes: Math.max(1, Math.round(Number(root.store.autokillMinutes)) || 30)
    readonly property bool autokillNotification: root.store.autokillNotification !== false

    // Not watched: this is the only writer.
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/dropdownconsolesettings.json"
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

    // The terminal fills the console inside its side and bottom borders, less
    // some padding. The bar's own bottom border is the separator on top of it.
    //
    // The padding is done here because kitty adds its own to the size it's
    // given, so a surface with padding of its own would come out larger than
    // asked for and run past the console's edge. It also adds 1px either way,
    // which this padding has room for.
    readonly property int terminalPadding: Config.scaled(11, root.uiScale)
    readonly property var terminalGeometry: ({
        x: root.edgeLeft + root.consoleOffset + root.borderWidth + root.terminalPadding,
        y: root.edgeTop + root.barHeight + root.terminalPadding,
        width: root.consoleWidth - (root.borderWidth + root.terminalPadding) * 2,
        height: root.consoleHeight - root.borderWidth - root.terminalPadding * 2
    })

    // ---------------- the panel ----------------
    PanelWindow {
        visible: !!root.screen && !root.barHidden
        screen: root.screen

        WlrLayershell.namespace: "dropdownconsolepanel"

        // Covers all the console could take up, so that the size sliders don't
        // resize it. -1 so the margins count from the screen's edges rather
        // than from the bar's reserved space.
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        margins {
            top: root.edgeTop + root.barHeight
            left: root.edgeLeft
            right: root.edgeRight
            bottom: root.edgeBottom
        }
        exclusiveZone: -1
        color: "transparent"

        // Only what's drawn takes clicks.
        mask: Region { item: panelBody }

        // The bar's bottom border is the separator on top of this, so this
        // border's top edge is left clipped off.
        Item {
            id: panelBody

            visible: root.expansion > 0
            x: root.consoleOffset
            width: root.consoleWidth
            height: Math.round(root.consoleHeight * root.expansion)
            clip: true

            Rectangle {
                y: -border.width
                width: parent.width
                height: parent.height + border.width
                color: Config.fillcolor
                border.width: root.borderWidth
                border.color: Config.fgcolor
            }
        }
    }

    // ---------------- opening and closing ----------------
    // Whether the console is open or on its way there.
    property bool open: false
    // How far the panel has grown, from 0 to 1.
    property real expansion: 0
    readonly property int panelHeight: Math.round(root.consoleHeight * root.expansion)
    // Whether kitty's surface is meant to be up.
    property bool terminalShown: false

    readonly property int animationMs: 300
    // kitty's surface name, which Hyprland reports when it goes away.
    readonly property string terminalNamespace: "dropdownconsole"
    // Roughly how long kitty takes to go after being asked, between kitten
    // starting up and kitty getting to it. It's asked this much ahead of the
    // shrinking panel, as going early doesn't show but going late does.
    readonly property int hideLatencyMs: 30
    readonly property real hideLeadHeight: root.consoleHeight * root.hideLatencyMs / root.animationMs

    function toggle() {
        if (root.open) root.closeConsole()
        else root.openConsole()
    }

    function openConsole() {
        if (root.barHidden || !root.screen) return
        root.open = true
        hideTimer.stop()
        if (!terminal.running) {
            // Nothing's on a new kitty yet that could get ahead of the panel.
            root.terminalShown = true
            root.startTerminal()
        } else if (!root.terminalShown) {
            root.measureText()
        }
        root.animateTo(1)
    }

    // The panel doesn't move until textMeasured() has said what kitty needs.
    function closeConsole() {
        if (!root.open) return
        root.open = false
        expandAnimation.stop()
        if (root.terminalShown) root.measureText()
        else root.animateTo(0)
    }

    function animateTo(value) {
        expandAnimation.stop()
        const distance = Math.abs(value - root.expansion)
        if (distance === 0) {
            root.updateTerminal()
            return
        }
        expandAnimation.to = value
        expandAnimation.duration = distance * root.animationMs
        expandAnimation.start()
    }

    function panelAtText() {
        return root.panelHeight - root.hideLeadHeight <= root.requiredHeight
    }

    function updateTerminal() {
        if (root.open) {
            if (!root.terminalShown && root.panelHeight >= root.requiredHeight) root.showTerminal()
        } else if (root.terminalShown && root.panelAtText()) {
            root.hideTerminal()
        }
    }

    function showTerminal() {
        root.terminalShown = true
        root.applyGeometry()
        root.applyFontSize()
        root.control(["resize-os-window", "--match=all", "--action=show"])
    }

    function hideTerminal() {
        root.terminalShown = false
        root.control(["resize-os-window", "--match=all", "--action=hide"])
    }

    function textMeasured() {
        measureTimer.stop()
        if (root.open) {
            root.updateTerminal()
        } else if (root.terminalShown && root.panelAtText()) {
            // The text already reaches the panel's edge, so the panel waits.
            root.hideTerminal()
            hideTimer.restart()
        } else {
            root.animateTo(0)
        }
    }

    onExpansionChanged: root.updateTerminal()

    NumberAnimation {
        id: expandAnimation
        target: root
        property: "expansion"
        easing.type: Easing.Linear
        onFinished: root.updateTerminal()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "closelayer" && event.data === root.terminalNamespace && hideTimer.running) {
                hideTimer.stop()
                root.animateTo(0)
            }
        }
    }

    // While this runs, the panel is waiting for kitty to go. Should Hyprland
    // never say it has, the panel closes anyway.
    Timer {
        id: hideTimer
        interval: 500
        onTriggered: root.animateTo(0)
    }

    // The panel's gone with the bar, so kitty can't stay for it.
    onBarHiddenChanged: {
        if (!root.barHidden || !root.open) return
        root.open = false
        if (root.terminalShown) root.hideTerminal()
        root.animateTo(0)
    }

    // ---------------- how much of the panel kitty's text needs ----------------
    // In the panel's pixels. -1 until it's known, which counts as all of it.
    property int textHeight: -1
    readonly property int requiredHeight: root.textHeight < 0 ? root.consoleHeight : root.textHeight

    function measureText() {
        root.textHeight = -1
        measureTimer.restart()
        measureProcess.running = true
    }

    // With wrap markers, every line of the screen ends in \r, even a blank one.
    function textHeightFrom(text) {
        const lines = text.split("\r")
        const lineCount = lines.length - 1
        if (lineCount < 1) return -1
        let last = lineCount - 1
        while (last >= 0 && lines[last].trim() === "") last--
        // One line extra, as kitty centres its grid when it doesn't quite fit.
        const covered = Math.min(lineCount, last + 2)
        return Math.min(root.consoleHeight,
            root.terminalPadding + Math.ceil(root.terminalGeometry.height * covered / lineCount))
    }

    Process {
        id: measureProcess
        // The window showing in its active tab. Left to itself kitty would go by
        // which of its windows has focus, which a hidden one doesn't.
        command: ["kitten", "@", "--to", "unix:" + root.socket, "get-text",
            "--match=state:active and state:parent_active", "--add-wrap-markers"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.textHeight = root.textHeightFrom(text)
                root.textMeasured()
            }
        }
    }

    // A kitty that doesn't answer in time shouldn't hold the panel up.
    Timer {
        id: measureTimer
        interval: 150
        onTriggered: root.textMeasured()
    }

    // ---------------- the terminal ----------------
    // A new name for every kitty, as it won't start on a socket file a crashed
    // one left behind.
    property string socket: ""

    function startTerminal() {
        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        const g = root.terminalGeometry
        root.socket = runtimeDir + "/purpura-dropdown-console-" + Date.now() + ".sock"
        root.appliedGeometry = root.geometryArgs()
        root.appliedFontSize = root.fontSize
        terminal.command = [
            "kitten", "panel",
            "--app-id=dropdownconsole",
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
            "-o", "font_size=" + root.fontSize,
            // kitty_mod is ctrl in kitty.conf, which makes this copy and nothing
            // else, so a stuck program could never be interrupted.
            "-o", "map=ctrl+c copy_or_interrupt",
            "-o", "window_margin_width=0",
            "-o", "single_window_margin_width=0",
            "-o", "window_padding_width=0",
            "-o", "single_window_padding_width=0",
            // A prompt nobody can see would leave it hanging.
            "-o", "confirm_os_window_close=0",
            // Tells fish's greeting to skip fastfetch.
            "-o", "env=PURPURA_DROPDOWN_CONSOLE=1"
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
            hideTimer.stop()
            expandAnimation.stop()
            root.open = false
            root.expansion = 0
        }
    }

    // A kitty left over from a shell that was killed outright can't be
    // reached any more, so it's stopped by name. The pattern needs kitty at
    // the start of the command line, so it can't hit a program that merely
    // mentions the flag.
    Process {
        command: ["pkill", "-f", "--", "^[^ ]*kitty[^ ]* .*--app-id=dropdownconsole( |$)"]
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

    // ---------------- changing a running kitty ----------------
    property var appliedGeometry: []
    property int appliedFontSize: 0

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

    function applyFontSize() {
        if (root.fontSize === root.appliedFontSize) return
        root.appliedFontSize = root.fontSize
        root.control(["set-font-size", "--all", String(root.fontSize)])
    }

    // A hidden kitty catches up when it's next shown.
    onTerminalGeometryChanged: if (root.terminalShown) changeTimer.restart()
    onFontSizeChanged: if (root.terminalShown) changeTimer.restart()

    Timer {
        id: changeTimer
        interval: 100
        onTriggered: {
            if (!root.terminalShown) return
            root.applyGeometry()
            root.applyFontSize()
        }
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

    function autokill() {
        const minutes = root.autokillMinutes
        terminal.running = false
        if (!root.autokillNotification) return
        Quickshell.execDetached(["notify-send", "-i", "clock", "Console terminated",
            minutes + (minutes === 1 ? " minute of inactivity has passed" : " minutes of inactivity have passed")])
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
                else if (!root.open) root.autokill()
            }
        }
    }

    // ---------------- triggers ----------------
    IpcHandler {
        target: "dropdownconsole"

        function toggle(): void { root.toggle() }
        function show(): void { root.openConsole() }
        function hide(): void { root.closeConsole() }
    }

    GlobalShortcut {
        name: "dropdownconsole"
        onPressed: root.toggle()
    }
}

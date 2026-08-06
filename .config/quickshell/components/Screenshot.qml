import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "../Config.js" as Config

// Custom interactive screenshot picker - META + Print opens it (bound via
// hyprland.lua's `hl.bind(mainMod .. " + Print", hl.dsp.global("quickshell:screenshot"))`).
// Freezes every connected screen into a temp PNG first (grim -o <name>),
// so the picker is always selecting against a static snapshot rather
// than a live-updating desktop, then dims everything and offers three
// capture modes:
//   - hover a window + right-click: captures that window
//   - left-click-drag: captures the dragged region
//   - Enter: captures the whole monitor the mouse is currently on
// Escape cancels. Region/window use `grim -g ... - | wl-copy` against
// the EXACT geometry this overlay already computed for its own on-screen
// highlight - never a second, independently re-derived guess at "which
// window" (the way handing capture off to hyprshot's own picking logic
// would risk disagreeing with what was actually highlighted). Monitor
// capture skips grim entirely and just wl-copies the frozen backdrop PNG
// straight off disk, since that's already exactly the right image.
Scope {
    id: root

    property bool active: false
    property bool opening: false

    property var monitors: []   // parsed hyprctl monitors -j
    property var clients: []    // parsed hyprctl clients -j, filtered to mapped + on-screen + on the active workspace of their monitor

    property real mouseGlobalX: 0
    property real mouseGlobalY: 0
    property var hoveredClient: null

    property bool dragging: false
    property string dragScreenName: ""
    property real dragStartX: 0
    property real dragStartY: 0
    property real dragCurX: 0
    property real dragCurY: 0

    readonly property real dragRectX: Math.min(root.dragStartX, root.dragCurX)
    readonly property real dragRectY: Math.min(root.dragStartY, root.dragCurY)
    readonly property real dragRectW: Math.abs(root.dragCurX - root.dragStartX)
    readonly property real dragRectH: Math.abs(root.dragCurY - root.dragStartY)

    function monitorByName(name) {
        for (const m of root.monitors) {
            if (m.name === name) return m
        }
        return null
    }

    function clientArea(c) {
        return c.size[0] * c.size[1]
    }

    // Smallest-area match wins on overlap (no real stacking-order field
    // in hyprctl's own JSON to hit-test against) - a reasonable
    // approximation for the common case of a small floating window
    // sitting on top of a larger tile beneath it.
    function clientAt(gx, gy) {
        let best = null
        for (const c of root.clients) {
            const x = c.at[0], y = c.at[1]
            const w = c.size[0], h = c.size[1]
            if (gx >= x && gx < x + w && gy >= y && gy < y + h) {
                if (!best || root.clientArea(c) < root.clientArea(best)) best = c
            }
        }
        return best
    }

    function monitorAt(gx, gy) {
        for (const m of root.monitors) {
            if (gx >= m.x && gx < m.x + m.width && gy >= m.y && gy < m.y + m.height) return m
        }
        return null
    }

    IpcHandler {
        target: "screenshot"
        function toggle(): void { root.active ? root.cancel() : root.begin() }
        function show(): void { root.begin() }
        function hide(): void { root.cancel() }
    }

    GlobalShortcut {
        name: "screenshot"
        onPressed: root.begin()
    }

    function begin() {
        if (root.active || root.opening) return
        root.opening = true
        root.hoveredClient = null
        root.dragging = false

        const names = Quickshell.screens.map(s => s.name)
        freezeProcess.command = ["bash", "-c", 'for name in "$@"; do grim -o "$name" "/tmp/quickshell-screenshot-freeze-$name.png"; done', "screenshot-freeze", ...names]
        freezeProcess.running = true
    }

    // Chained: freeze all screens -> read monitor geometry -> read
    // window list (which needs monitor geometry to know each monitor's
    // currently-active workspace) -> only then actually show the
    // overlay, so it never appears before its backdrop image and window
    // list both genuinely exist.
    Process {
        id: freezeProcess
        onExited: (exitCode, exitStatus) => monitorsProcess.running = true
    }

    Process {
        id: monitorsProcess
        command: ["hyprctl", "monitors", "-j"]

        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsCollector.text)
                } catch (e) {
                    root.monitors = []
                }
                clientsProcess.running = true
            }
        }
    }

    Process {
        id: clientsProcess
        command: ["hyprctl", "clients", "-j"]

        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                let parsed = []
                try {
                    parsed = JSON.parse(clientsCollector.text)
                } catch (e) {
                    parsed = []
                }

                const monById = {}
                for (const m of root.monitors) monById[m.id] = m

                // Only windows that are actually mapped, not hidden, and
                // on the workspace CURRENTLY SHOWING on their monitor -
                // hyprctl clients lists every window on every workspace,
                // including ones nowhere near visible right now.
                root.clients = parsed.filter(c => {
                    if (!c.mapped || c.hidden) return false
                    const mon = monById[c.monitor]
                    if (!mon) return false
                    return c.workspace && mon.activeWorkspace && c.workspace.id === mon.activeWorkspace.id
                })

                root.opening = false
                root.active = true
            }
        }
    }

    function cancel() {
        root.active = false
        root.opening = false
        root.hoveredClient = null
        root.dragging = false
        cleanupProcess.running = true
    }

    Process {
        id: cleanupProcess
        command: ["bash", "-c", "rm -f /tmp/quickshell-screenshot-freeze-*.png"]
    }

    Process {
        // Command set fresh per capture by the functions below - a
        // single reused Process, since only one capture ever happens per
        // picker session (any of them closes it immediately). Cleanup
        // (temp files + state reset) waits for this to actually exit
        // rather than firing right after it's started, so it can never
        // race a capture that's reading one of those same temp files
        // (see captureMonitorUnderMouse).
        id: captureProcess
        onExited: (exitCode, exitStatus) => {
            root.opening = false
            root.hoveredClient = null
            root.dragging = false
            cleanupProcess.running = true
        }
    }

    // Setting root.active = false only requests the overlay's layer
    // surfaces unmap - that's an async round-trip to the compositor, not
    // something that's actually happened by the time this same JS tick
    // returns. Running grim immediately after raced that unmap and
    // grabbed the dim/instruction bar still on screen. Hiding first,
    // then waiting a beat before actually invoking grim, gives the
    // compositor time to genuinely drop the overlay from the frame grim
    // reads. Only the region/window paths need this - they're the only
    // ones asking grim for a fresh live frame at all.
    property var pendingCaptureCommand: null

    Timer {
        id: captureDelay
        interval: 100
        repeat: false
        onTriggered: {
            if (root.pendingCaptureCommand) {
                captureProcess.command = root.pendingCaptureCommand
                captureProcess.running = true
                root.pendingCaptureCommand = null
            }
        }
    }

    function startLiveCapture(command) {
        root.pendingCaptureCommand = command
        root.active = false
        captureDelay.start()
    }

    function captureRegion(x, y, w, h) {
        const geom = Math.round(x) + "," + Math.round(y) + " " + Math.round(w) + "x" + Math.round(h)
        root.startLiveCapture(["bash", "-c", 'grim -g "$1" - | wl-copy && notify-send "Screenshot" "Screenshot copied to clipboard"', "screenshot-region", geom])
    }

    function captureClient(client) {
        root.captureRegion(client.at[0], client.at[1], client.size[0], client.size[1])
    }

    function captureMonitorUnderMouse() {
        const mon = root.monitorAt(root.mouseGlobalX, root.mouseGlobalY)
        if (mon) {
            // Enter grabs the WHOLE monitor - exactly the frame begin()
            // already froze to disk before this overlay ever existed, so
            // there's nothing to hide or re-capture live: hand that
            // exact file to wl-copy directly. No compositor round-trip,
            // no unmap race, no delay needed for this path at all.
            root.active = false
            captureProcess.command = ["bash", "-c", 'wl-copy < "$1" && notify-send "Screenshot" "Screenshot copied to clipboard"', "screenshot-monitor", "/tmp/quickshell-screenshot-freeze-" + mon.name + ".png"]
            captureProcess.running = true
        } else {
            root.cancel()
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlayWin

            property var modelData
            screen: modelData

            visible: root.active

            // Arbitrary but consistent - matches Lock/PowerMenu's own
            // "only one screen ever holds exclusive focus" convention,
            // just picking screens[0] rather than a user-configured
            // primaryMonitor (this picker has no such setting).
            readonly property bool isPrimary: modelData.name === (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
            readonly property var thisMonitor: root.monitorByName(modelData.name)
            readonly property real monX: thisMonitor ? thisMonitor.x : 0
            readonly property real monY: thisMonitor ? thisMonitor.y : 0

            WlrLayershell.namespace: "screenshot"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: overlayWin.isPrimary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            // The frozen backdrop - source only ever toggles between ""
            // and a real path (never the same non-empty path reused for
            // different underlying file content), so it always reloads
            // fresh rather than needing a cache-busting trick.
            Image {
                anchors.fill: parent
                source: root.active ? ("file:///tmp/quickshell-screenshot-freeze-" + modelData.name + ".png") : ""
                asynchronous: true
                cache: false
                fillMode: Image.Stretch
            }

            // A drag in progress punches its own hole (the region being
            // selected undims exactly like a hovered window does);
            // otherwise a hovered window on THIS screen punches one.
            readonly property bool dragHoleHere: root.dragging && root.dragScreenName === modelData.name &&
                root.dragRectW > 0 && root.dragRectH > 0
            readonly property bool hoverHoleHere: !root.dragging && root.hoveredClient !== null &&
                root.hoveredClient.at[0] >= monX && root.hoveredClient.at[0] < monX + width &&
                root.hoveredClient.at[1] >= monY && root.hoveredClient.at[1] < monY + height
            readonly property bool hasHoleHere: dragHoleHere || hoverHoleHere

            readonly property real holeX: dragHoleHere ? (root.dragRectX - monX) : (hoverHoleHere ? root.hoveredClient.at[0] - monX : 0)
            readonly property real holeY: dragHoleHere ? (root.dragRectY - monY) : (hoverHoleHere ? root.hoveredClient.at[1] - monY : 0)
            readonly property real holeW: dragHoleHere ? root.dragRectW : (hoverHoleHere ? root.hoveredClient.size[0] : 0)
            readonly property real holeH: dragHoleHere ? root.dragRectH : (hoverHoleHere ? root.hoveredClient.size[1] : 0)

            // Dim everything (full cover) unless a window on THIS screen
            // is currently hovered, in which case four strips frame a
            // clear "hole" over it instead of one full-cover rectangle.
            Rectangle {
                visible: !overlayWin.hasHoleHere
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
            }

            Rectangle {
                visible: overlayWin.hasHoleHere
                x: 0
                y: 0
                width: parent.width
                height: Math.max(0, overlayWin.holeY)
                color: Qt.rgba(0, 0, 0, 0.55)
            }

            Rectangle {
                visible: overlayWin.hasHoleHere
                x: 0
                y: overlayWin.holeY + overlayWin.holeH
                width: parent.width
                height: Math.max(0, parent.height - (overlayWin.holeY + overlayWin.holeH))
                color: Qt.rgba(0, 0, 0, 0.55)
            }

            Rectangle {
                visible: overlayWin.hasHoleHere
                x: 0
                y: overlayWin.holeY
                width: Math.max(0, overlayWin.holeX)
                height: overlayWin.holeH
                color: Qt.rgba(0, 0, 0, 0.55)
            }

            Rectangle {
                visible: overlayWin.hasHoleHere
                x: overlayWin.holeX + overlayWin.holeW
                y: overlayWin.holeY
                width: Math.max(0, parent.width - (overlayWin.holeX + overlayWin.holeW))
                height: overlayWin.holeH
                color: Qt.rgba(0, 0, 0, 0.55)
            }

            // Marching-ants border around the hovered window.
            Canvas {
                id: hoverAnts
                anchors.fill: parent

                property real rx: overlayWin.holeX
                property real ry: overlayWin.holeY
                property real rw: overlayWin.holeW
                property real rh: overlayWin.holeH
                property bool show: overlayWin.hoverHoleHere
                property real dashPhase: 0

                visible: show

                onRxChanged: requestPaint()
                onRyChanged: requestPaint()
                onRwChanged: requestPaint()
                onRhChanged: requestPaint()
                onShowChanged: requestPaint()
                onDashPhaseChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (!show || rw <= 0 || rh <= 0) return
                    ctx.setLineDash([6, 4])
                    ctx.lineDashOffset = -dashPhase
                    ctx.lineWidth = 2
                    ctx.strokeStyle = Config.fgcolorlight
                    ctx.strokeRect(rx + 1, ry + 1, rw - 2, rh - 2)
                }

                NumberAnimation on dashPhase {
                    from: 0
                    to: 10
                    duration: 500
                    loops: Animation.Infinite
                    running: hoverAnts.visible
                }
            }

            // Marching-ants border around the in-progress drag
            // selection - only ever drawn on the screen the drag
            // actually started on.
            Canvas {
                id: dragAnts
                anchors.fill: parent

                property real rx: root.dragRectX - overlayWin.monX
                property real ry: root.dragRectY - overlayWin.monY
                property real rw: root.dragRectW
                property real rh: root.dragRectH
                property bool show: root.dragging && root.dragScreenName === modelData.name && rw > 0 && rh > 0
                property real dashPhase: 0

                visible: show

                onRxChanged: requestPaint()
                onRyChanged: requestPaint()
                onRwChanged: requestPaint()
                onRhChanged: requestPaint()
                onShowChanged: requestPaint()
                onDashPhaseChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (!show || rw <= 0 || rh <= 0) return
                    ctx.setLineDash([6, 4])
                    ctx.lineDashOffset = -dashPhase
                    ctx.lineWidth = 2
                    ctx.strokeStyle = Config.fgcolorlight
                    ctx.strokeRect(rx + 1, ry + 1, rw - 2, rh - 2)
                }

                NumberAnimation on dashPhase {
                    from: 0
                    to: 10
                    duration: 500
                    loops: Animation.Infinite
                    running: dragAnts.visible
                }
            }

            // Top instruction bar - LMB/RMB spelled out rather than an
            // icon, since there's no standard Unicode glyph that
            // distinguishes a left-click from a right-click the way a
            // single generic mouse emoji can't.
            Rectangle {
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 20
                }
                width: instructionText.implicitWidth + 24
                height: instructionText.implicitHeight + 16
                color: Config.fillcolor
                border.width: 2
                border.color: Config.fgcolor

                Text {
                    id: instructionText
                    anchors.centerIn: parent
                    text: "[LMB] Region  -  [RMB] Window  -  [ESC] Cancel  -  [ENTER] Monitor"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: 14
                    font.bold: true
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onPositionChanged: (mouse) => {
                    const gx = overlayWin.monX + mouse.x
                    const gy = overlayWin.monY + mouse.y
                    root.mouseGlobalX = gx
                    root.mouseGlobalY = gy

                    if (root.dragging) {
                        root.dragCurX = gx
                        root.dragCurY = gy
                    } else {
                        root.hoveredClient = root.clientAt(gx, gy)
                    }
                }

                onPressed: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        const gx = overlayWin.monX + mouse.x
                        const gy = overlayWin.monY + mouse.y
                        root.dragging = true
                        root.dragScreenName = modelData.name
                        root.dragStartX = gx
                        root.dragStartY = gy
                        root.dragCurX = gx
                        root.dragCurY = gy
                        root.hoveredClient = null
                    }
                }

                onReleased: (mouse) => {
                    if (mouse.button === Qt.LeftButton && root.dragging) {
                        root.dragging = false
                        // Ignore a near-zero-size drag (i.e. effectively
                        // just a plain click) instead of capturing a
                        // useless 0x0-ish region.
                        if (root.dragRectW > 2 && root.dragRectH > 2) {
                            root.captureRegion(root.dragRectX, root.dragRectY, root.dragRectW, root.dragRectH)
                        }
                    }
                }

                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton && root.hoveredClient) {
                        root.captureClient(root.hoveredClient)
                    }
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: overlayWin.isPrimary

                Keys.onEscapePressed: root.cancel()
                Keys.onReturnPressed: root.captureMonitorUnderMouse()
                Keys.onEnterPressed: root.captureMonitorUnderMouse()

                Component.onCompleted: {
                    if (overlayWin.isPrimary) forceActiveFocus()
                }
            }
        }
    }
}

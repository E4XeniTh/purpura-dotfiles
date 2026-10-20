import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "../Config.js" as Config

// Custom interactive screenshot picker - META + X opens it (bound via
// hyprland.lua's `hl.bind(mainMod .. " + X", hl.dsp.global("quickshell:screenshot"))`).
// Freezes every connected screen into a temp PNG first (grim -o <name>,
// plus one plain `grim` of the whole layout), so the picker is always
// selecting against a static snapshot rather than a live-updating
// desktop, then dims everything and offers four capture modes:
//   - hover a window (or the bar) + right-click: captures that surface
//   - left-click-drag: captures the dragged region
//   - Enter: captures the whole monitor the mouse is currently on
//   - Ctrl+Enter: captures every monitor combined into one image
// Escape cancels.
//
// Every mode captures FROM THOSE FROZEN FILES, never from the live screen:
// monitor/all-monitors copy a frozen file as-is, region/window crop one
// (helpers/screenshot-crop.sh, ImageMagick) to the exact geometry this
// overlay computed for its own on-screen highlight. The frozen frames are
// written before the overlay ever exists, so its dim, selection border and
// instruction bar can't end up in a capture no matter how long the
// compositor takes to unmap or fade it out. Capturing live after hiding
// the overlay (the previous approach) raced exactly that, and no delay or
// poll could reliably win it.
Scope {
    id: root

    property bool active: false
    property bool opening: false
    // Set the moment a capture or cancel starts - blanks the overlay while
    // it's still mapped, see close().
    property bool contentHidden: false

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

    function freezePath(name) {
        return "/tmp/quickshell-screenshot-freeze-" + name + ".png"
    }

    function monitorByName(name) {
        for (const m of root.monitors) {
            if (m.name === name) return m
        }
        return null
    }

    // hyprctl's monitor width/height are the physical mode, before scale
    // and rotation - everything else here (window positions, the cursor,
    // the overlay windows themselves) is in logical layout units.
    function logicalRect(m) {
        const rotated = (m.transform % 2) === 1
        return {
            x: m.x,
            y: m.y,
            w: (rotated ? m.height : m.width) / m.scale,
            h: (rotated ? m.width : m.height) / m.scale
        }
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
            const r = root.logicalRect(m)
            if (gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h) return m
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
        // Also waits out the previous session entirely: its capture may
        // still be reading the frozen files this would overwrite, and its
        // cleanup would delete the new ones.
        if (root.active || root.opening || closeTimer.running || captureProcess.running || cleanupProcess.running) return
        root.opening = true
        root.contentHidden = false
        root.hoveredClient = null
        root.dragging = false

        const names = Quickshell.screens.map(s => s.name)
        freezeProcess.command = ["bash", "-c", 'for name in "$@"; do grim -o "$name" "/tmp/quickshell-screenshot-freeze-$name.png"; done; grim "/tmp/quickshell-screenshot-freeze-all.png"', "screenshot-freeze", ...names]
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

                layersProcess.running = true
            }
        }
    }

    // The bar (namespace "bar", see Bar.qml) is a layer-shell surface,
    // not a toplevel window, so it never shows up in `hyprctl clients
    // -j` at all - this is the only way to find it. Folded straight
    // into root.clients as a plain {at, size} entry so every existing
    // hover/hole/capture codepath (which only ever reads those two
    // fields) treats it exactly like any other selectable window, no
    // special-casing needed anywhere else.
    Process {
        id: layersProcess
        command: ["hyprctl", "layers", "-j"]

        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                let parsed = {}
                try {
                    parsed = JSON.parse(layersCollector.text)
                } catch (e) {
                    parsed = {}
                }

                const barEntries = []
                for (const monName in parsed) {
                    const mon = root.monitorByName(monName)
                    if (!mon) continue
                    const levels = (parsed[monName] && parsed[monName].levels) || {}
                    for (const levelKey in levels) {
                        for (const layer of levels[levelKey]) {
                            if (layer.namespace === "bar") {
                                barEntries.push({
                                    at: [mon.x + layer.x, mon.y + layer.y],
                                    size: [layer.w, layer.h]
                                })
                            }
                        }
                    }
                }

                root.clients = root.clients.concat(barEntries)

                // Cancelled while still freezing - don't pop the overlay
                // up anyway, just drop the files that freeze wrote.
                if (!root.opening) {
                    cleanupProcess.running = true
                    return
                }
                root.opening = false
                root.active = true
            }
        }
    }

    function cancel() {
        root.opening = false
        if (root.active) root.close()
        cleanupProcess.running = true
    }

    // Blanks the overlay first and only unmaps it a few frames later.
    // Hyprland's layer close animation fades out whatever the surface last
    // showed, so unmapping straight away left a fading dim/selection frame
    // on screen - which a quick META + X right after could freeze into the
    // next screenshot. Captures themselves never read the live screen, so
    // nothing waits on this.
    function close() {
        root.contentHidden = true
        root.hoveredClient = null
        root.dragging = false
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 60
        repeat: false
        onTriggered: root.active = false
    }

    Process {
        id: cleanupProcess
        command: ["bash", "-c", "rm -f /tmp/quickshell-screenshot-freeze-*.png"]
    }

    // Single reused Process - only one capture ever happens per picker
    // session (starting one closes the picker). Cleanup waits for it to
    // actually exit, since every capture reads one of the frozen files.
    Process {
        id: captureProcess
        onExited: (exitCode, exitStatus) => cleanupProcess.running = true
    }

    function startCapture(command) {
        if (root.contentHidden || captureProcess.running) return
        captureProcess.command = command
        captureProcess.running = true
        root.close()
    }

    function copyFrozen(name) {
        root.startCapture(["bash", "-c", 'wl-copy --type image/png < "$1" && notify-send "Screenshot copied to clipboard."', "screenshot-copy", root.freezePath(name)])
    }

    // x/y/w/h/lw/lh: crop rect and the frame's full extent, in logical
    // units relative to the frame's top-left. The helper maps them to
    // pixels from the frame's real size.
    function cropFrozen(name, x, y, w, h, lw, lh) {
        root.startCapture(["bash", Quickshell.shellDir + "/helpers/screenshot-crop.sh", root.freezePath(name)].concat([x, y, w, h, lw, lh].map(String)))
    }

    // Prefers the one monitor that fully contains the rect: its own frozen
    // frame is at that monitor's native resolution, whereas grim's combined
    // frame is rendered at the highest scale of any monitor (a crop from a
    // lower-scale monitor would come out upscaled). Anything spanning
    // monitors or hanging past the layout's edge comes from the combined
    // frame instead, which the helper clamps to what was actually captured.
    function captureRect(x, y, w, h) {
        if (root.monitors.length === 0) {
            root.cancel()
            return
        }

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (const m of root.monitors) {
            const r = root.logicalRect(m)
            // 1px of slack: with fractional scaling a monitor's logical
            // size isn't a whole number, while window geometry is.
            if (x >= r.x - 1 && y >= r.y - 1 && x + w <= r.x + r.w + 1 && y + h <= r.y + r.h + 1) {
                root.cropFrozen(m.name, x - r.x, y - r.y, w, h, r.w, r.h)
                return
            }
            minX = Math.min(minX, r.x)
            minY = Math.min(minY, r.y)
            maxX = Math.max(maxX, r.x + r.w)
            maxY = Math.max(maxY, r.y + r.h)
        }
        root.cropFrozen("all", x - minX, y - minY, w, h, maxX - minX, maxY - minY)
    }

    // A drag keeps reporting the pointer past its own screen's edge, but
    // the selection is only ever drawn on that one screen - capture
    // exactly the part that was visibly selected.
    function captureRegion(x, y, w, h) {
        const m = root.monitorByName(root.dragScreenName)
        if (m) {
            const r = root.logicalRect(m)
            const x1 = Math.min(x + w, r.x + r.w)
            const y1 = Math.min(y + h, r.y + r.h)
            x = Math.max(x, r.x)
            y = Math.max(y, r.y)
            w = x1 - x
            h = y1 - y
        }
        if (w < 1 || h < 1) return
        root.captureRect(x, y, w, h)
    }

    function captureClient(client) {
        root.captureRect(client.at[0], client.at[1], client.size[0], client.size[1])
    }

    // Enter needs "whichever monitor the mouse is over RIGHT NOW" - going
    // through hyprctl's own live cursor tracking instead of this overlay's
    // own root.mouseGlobalX/Y (each screen's own MouseArea only updates
    // that from ITS OWN pointer events, and evidently doesn't reliably
    // keep up across every screen at once here) so this is always
    // correct regardless of that.
    Process {
        id: cursorPosProcess
        command: ["hyprctl", "cursorpos"]

        stdout: StdioCollector {
            id: cursorPosCollector
            onStreamFinished: {
                const parts = cursorPosCollector.text.trim().split(",")
                const gx = parseFloat(parts[0])
                const gy = parseFloat(parts[1])
                const mon = (isNaN(gx) || isNaN(gy)) ? null : root.monitorAt(gx, gy)
                if (mon) {
                    root.copyFrozen(mon.name)
                } else {
                    root.cancel()
                }
            }
        }
    }

    function captureMonitorUnderMouse() {
        if (root.contentHidden || cursorPosProcess.running) return
        cursorPosProcess.running = true
    }

    function captureAllMonitors() {
        root.copyFrozen("all")
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlayWin

            property var modelData
            screen: modelData

            visible: root.active

            readonly property var thisMonitor: root.monitorByName(modelData.name)
            readonly property real monX: thisMonitor ? thisMonitor.x : 0
            readonly property real monY: thisMonitor ? thisMonitor.y : 0

            WlrLayershell.namespace: "screenshot"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            // Unlike Lock/PowerMenu (pick exactly one screen, done),
            // this picker is mouse-driven across the whole multi-monitor
            // layout, so every screen's surface needs to be a genuinely
            // equal, independently interactive target - pinning
            // keyboard-interactivity to a single "primary" screen
            // (Exclusive there, None everywhere else) turned out to
            // leave every OTHER screen's surface unable to receive real
            // pointer button events at all, not just keyboard input:
            // left/right click only worked on that one screen. OnDemand
            // on every screen lets Hyprland grant each surface real
            // interactivity as the user actually engages with it,
            // whichever monitor that happens to be.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

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

            // Same root.mouseGlobalX/Y window-hover already relies on,
            // just checked against the hint's own resolved rect instead
            // of a client/monitor rect.
            readonly property real localMouseX: root.mouseGlobalX - monX
            readonly property real localMouseY: root.mouseGlobalY - monY
            readonly property bool hintHoveredHere: instructionBar &&
                localMouseX >= instructionBar.x && localMouseX < instructionBar.x + instructionBar.width &&
                localMouseY >= instructionBar.y && localMouseY < instructionBar.y + instructionBar.height

            // Everything this overlay paints - hidden as a whole by
            // close() before the window itself unmaps.
            Item {
                anchors.fill: parent
                visible: !root.contentHidden

                // The frozen backdrop - source only ever toggles between ""
                // and a real path (never the same non-empty path reused for
                // different underlying file content), so it always reloads
                // fresh rather than needing a cache-busting trick.
                Image {
                    anchors.fill: parent
                    source: root.active ? ("file://" + root.freezePath(modelData.name)) : ""
                    asynchronous: true
                    cache: false
                    fillMode: Image.Stretch
                }

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
                // single generic mouse emoji can't. Fades out (opacity, not
                // visible) while dragging or while the mouse is over it, so
                // it never blocks the view of whatever's underneath. Hover
                // is a plain rect-contains-point check against
                // root.mouseGlobalX/Y - the same state window-hover already
                // uses successfully - rather than a second, independent
                // HoverHandler, which never actually detected anything here
                // (most likely shadowed by the full-fill MouseArea below,
                // which sits on top of this Rectangle in stacking order).
                Rectangle {
                    id: instructionBar
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
                    opacity: (root.dragging || overlayWin.hintHoveredHere) ? 0 : 1

                    Text {
                        id: instructionText
                        anchors.centerIn: parent
                        text: "[LMB] Region  -  [RMB] Window  -  [ENTER] Monitor" +
                            (Quickshell.screens.length > 1 ? "  -  [CTRL+ENTER] All Monitors" : "") + "  -  [ESC] Cancel"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: 14
                        font.bold: true
                    }
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
                focus: true

                Keys.onEscapePressed: root.cancel()
                Keys.onReturnPressed: (event) => {
                    if (event.modifiers & Qt.ControlModifier) {
                        root.captureAllMonitors()
                    } else {
                        root.captureMonitorUnderMouse()
                    }
                }
                Keys.onEnterPressed: (event) => {
                    if (event.modifiers & Qt.ControlModifier) {
                        root.captureAllMonitors()
                    } else {
                        root.captureMonitorUnderMouse()
                    }
                }

                // Every screen requests focus for its own FocusScope -
                // with OnDemand keyboard-interactivity (see above) the
                // compositor is the one actually arbitrating which
                // surface's keyboard events go where, so there's no
                // longer a single "the primary one always wins" case to
                // special-case here.
                Component.onCompleted: forceActiveFocus()
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../Config.js" as Config

// Brief "META + D toggles Dashboard" reminder, shown on whichever
// monitor's active window just entered GENUINE internal fullscreen
// (META+F11) - the bar (and its dashboard-opening clock button) sits
// behind a fullscreen window, so this is the one nudge that it's still
// reachable via keybind.
//
// There's no dedicated reactive "fullscreen" property on Quickshell's
// Hyprland toplevel type (HyprlandToplevel only exposes title/
// activated/urgent/workspace/monitor as live bindable properties - its
// lastIpcObject is a one-shot snapshot, not something that updates on
// its own), so this taps the same raw IPC event stream WorkspaceOsd.qml
// already listens to, filtered down to Hyprland's own documented
// "fullscreen>>0/1" event. That event alone isn't trustworthy enough to
// gate showing on directly, though - reported live as also firing for
// META+W's plain floating toggle, nothing to do with fullscreen at
// all - so every "fullscreen>>1" is treated as just a prompt to go
// re-check the real state via `hyprctl activewindow -j`'s
// fullscreenClient field (see fullscreenCheckProcess below), the same
// 0=none/1=maximized/2=fullscreen/3=both bitmask this repo's own
// fullscreen-tearing window rule in hyprland.lua already relies on -
// only a genuine 2 (real fullscreen, not maximized) actually shows the
// hint.
Scope {
    id: root

    // Fed in from shell.qml - watched below so the hint disappears the
    // instant Dashboard actually opens instead of leaving it sitting on
    // screen for however long was left on hideTimer, e.g. someone
    // opening Dashboard well before the 2s auto-hide would otherwise
    // fire.
    property var dashboard: null

    property string hintMonitorName: ""
    property int showToken: 0
    property int hideToken: 0

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "fullscreen" || event.data !== "1") return
            fullscreenCheckProcess.running = true
        }
    }

    Process {
        id: fullscreenCheckProcess
        command: ["hyprctl", "activewindow", "-j"]

        stdout: StdioCollector {
            id: fullscreenCheckCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(fullscreenCheckCollector.text)
                } catch (e) {
                    parsed = null
                }
                if (!parsed || parsed.fullscreenClient !== 2) return

                const mon = Hyprland.activeToplevel && Hyprland.activeToplevel.monitor
                if (!mon) return
                root.hintMonitorName = mon.name
                root.showToken++
            }
        }
    }

    Connections {
        target: root.dashboard
        function onOpenChanged() {
            if (root.dashboard.open) root.hideToken++
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: hintWindow

            property var modelData
            screen: modelData

            // Same reference-resolution scaling formula as every other
            // OSD/panel in this shell.
            readonly property real uiScale: Math.max(0.6, Math.min(1.8, modelData.width * 0.42 / 800))

            property bool shouldShow: false

            Connections {
                target: root
                function onShowTokenChanged() {
                    if (root.hintMonitorName !== modelData.name) return
                    hintWindow.shouldShow = true
                    hideTimer.restart()
                }
                function onHideTokenChanged() {
                    hintWindow.shouldShow = false
                    hideTimer.stop()
                }
            }

            Timer {
                id: hideTimer
                interval: 2000
                repeat: false
                onTriggered: hintWindow.shouldShow = false
            }

            visible: hintWindow.shouldShow

            WlrLayershell.namespace: "fullscreen-hint-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Top-anchored only (no left/right) - centers horizontally
            // the same way VolumeOsd/WorkspaceOsd do with no explicit
            // horizontal anchor of their own. Margin/height match
            // Bar.qml exactly, so this sits flush in the bar's own
            // spot instead of floating lower on the screen.
            anchors.top: true
            margins.top: Config.scaled(10, hintWindow.uiScale)
            exclusiveZone: 0
            color: "transparent"

            // Purely informational - never wants mouse input, same
            // reasoning as WorkspaceOsd's own click-through mask.
            mask: Region {}

            implicitWidth: hintText.implicitWidth + Config.scaled(32, hintWindow.uiScale)
            implicitHeight: Config.scaled(Config.barheight, hintWindow.uiScale)

            Rectangle {
                anchors.fill: parent
                color: Config.fillcolor
                border.width: 2
                border.color: Config.fgcolor
                radius: 0

                Text {
                    id: hintText
                    anchors.centerIn: parent
                    text: "[META + D] Toggle Dashboard"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(26, hintWindow.uiScale)
                    font.bold: true
                }
            }
        }
    }
}

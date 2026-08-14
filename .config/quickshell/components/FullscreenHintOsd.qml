import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Config.js" as Config

// Brief "META + D toggles Dashboard" reminder, shown on whichever
// monitor's active window just entered fullscreen - the bar (and its
// dashboard-opening clock button) sits behind a fullscreen window, so
// this is the one nudge that it's still reachable via keybind.
//
// There's no dedicated reactive "fullscreen" property on Quickshell's
// Hyprland toplevel type (HyprlandToplevel only exposes title/
// activated/urgent/workspace/monitor as live bindable properties - its
// lastIpcObject is a one-shot snapshot, not something that updates on
// its own), so this taps the same raw IPC event stream WorkspaceOsd.qml
// already listens to, filtered down to Hyprland's own documented
// "fullscreen>>0/1" event instead.
Scope {
    id: root

    property string hintMonitorName: ""
    property int showToken: 0

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "fullscreen" || event.data !== "1") return
            const mon = Hyprland.activeToplevel && Hyprland.activeToplevel.monitor
            if (!mon) return
            root.hintMonitorName = mon.name
            root.showToken++
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
            }

            Timer {
                id: hideTimer
                interval: 4000
                repeat: false
                onTriggered: hintWindow.shouldShow = false
            }

            visible: hintWindow.shouldShow

            WlrLayershell.namespace: "fullscreen-hint-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Top-anchored only (no left/right) - centers horizontally
            // the same way VolumeOsd/WorkspaceOsd do with no explicit
            // horizontal anchor of their own.
            anchors.top: true
            margins.top: Config.scaled(20, hintWindow.uiScale)
            exclusiveZone: 0
            color: "transparent"

            // Purely informational - never wants mouse input, same
            // reasoning as WorkspaceOsd's own click-through mask.
            mask: Region {}

            implicitWidth: hintText.implicitWidth + Config.scaled(32, hintWindow.uiScale)
            implicitHeight: hintText.implicitHeight + Config.scaled(16, hintWindow.uiScale)

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
                    font.pixelSize: Config.scaled(16, hintWindow.uiScale)
                    font.bold: true
                }
            }
        }
    }
}

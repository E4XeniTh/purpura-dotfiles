import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../common/HyprlandEvents.js" as HyprlandEvents

// Whether the focused window is in real fullscreen - the whole monitor
// (Hyprland's internal mode 2), not maximized - and which monitor it's on.
// The bar hides for it, and the dashboard, the notifications and the updater
// drop the bar's room while it's so. One check for all four (shell.qml hands
// this to each), rather than four of them, each running `hyprctl activewindow
// -j` at every event Hyprland sends.
//
// Asked of hyprctl rather than taken from an event's own data: Quickshell's
// toplevels say nothing of fullscreen, and "fullscreen>>1" also comes for a
// window being maximized. And asked at every event that can change it, not
// just "fullscreen": switching workspaces (or the focus) away from a
// fullscreen window brings no "fullscreen" event of its own - that window's
// flag hasn't changed, only which workspace is shown - so going by those alone
// left a fullscreen app counted on a workspace switched away from it. The
// events HyprlandEvents.js calls quiet never change it - a title changing,
// above all, which some apps do many times a second. An event that comes while
// a check is out has it asked again once that's back, so the last of a burst
// always counts.
Scope {
    id: root

    property bool activeIsFullscreen: false
    property string monitorName: ""

    // HyprlandEvents.quiet()'s memory of the focused window.
    readonly property var seen: ({})
    property bool again: false

    function check() {
        if (checkProcess.running) {
            root.again = true
            return
        }
        checkProcess.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (HyprlandEvents.quiet(event, root.seen)) return
            root.check()
        }
    }

    Process {
        id: checkProcess
        command: ["hyprctl", "activewindow", "-j"]

        onRunningChanged: {
            if (checkProcess.running || !root.again) return
            root.again = false
            Qt.callLater(root.check)
        }

        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(collector.text)
                } catch (e) {
                    parsed = null
                }
                const mon = Hyprland.activeToplevel && Hyprland.activeToplevel.monitor
                root.activeIsFullscreen = !!(parsed && parsed.fullscreenClient === 2 && mon)
                root.monitorName = (root.activeIsFullscreen && mon) ? mon.name : ""
            }
        }
    }

    // A shell started (or reloaded) over a fullscreen window counts it from the
    // start, not from the next event.
    Component.onCompleted: root.check()
}

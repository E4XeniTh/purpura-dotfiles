import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Hyprland's edge padding (general:gaps_out), the space windows keep from the
// screen's edges. The bar and whatever lines up with its ends use these
// instead of a size of their own, so their edges meet the windows' edges.
//
// In plain pixels, not put through Config.scaled: Hyprland's gaps don't follow
// the shell's UI Scale. Read again whenever Hyprland's config reloads.
Scope {
    id: root

    property int top: 10
    property int right: 10
    property int bottom: 10
    property int left: 10

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                gapsProcess.running = false
                gapsProcess.running = true
            }
        }
    }

    Process {
        id: gapsProcess
        command: ["hyprctl", "getoption", "general:gaps_out", "-j"]
        running: true

        // Reported as a "custom" string of top, right, bottom and left.
        stdout: StdioCollector {
            onStreamFinished: {
                let sides = []
                try {
                    sides = String(JSON.parse(text).custom).trim().split(/\s+/).map(Number)
                } catch (e) {
                    return
                }
                if (sides.length !== 4 || sides.some(isNaN)) return
                root.top = sides[0]
                root.right = sides[1]
                root.bottom = sides[2]
                root.left = sides[3]
            }
        }
    }
}

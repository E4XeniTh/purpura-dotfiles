import QtQuick
import Quickshell
import Quickshell.Io
import "../../Config.js" as Config

// Audio visualizer. The `cava` CLI's own raw/ascii output mode kept
// producing frozen bars (see git history), so this now runs
// helpers/cava_bridge - a small compiled helper (same pattern as
// helpers/auth.c) that links directly against libcavacore, the analysis
// engine cava itself is built on, and prints the same semicolon-separated
// per-frame format the old CLI-based approach did. Build it the same way
// as the lock screen's auth helper - see helpers/Makefile.
// Parsed into a fixed set of bar levels and drawn as flat fgcolor bars
// growing up from the bottom.
Item {
    id: root

    property real uiScale: 1.0
    readonly property int barCount: 25
    property var levels: []

    Component.onCompleted: {
        const initial = []
        for (let i = 0; i < root.barCount; i++) {
            initial.push(0)
        }
        root.levels = initial
    }

    Process {
        running: true
        command: [Quickshell.env("HOME") + "/.config/quickshell/helpers/cava_bridge"]

        stdout: SplitParser {
            onRead: (line) => {
                // Read whatever count actually comes in rather than
                // requiring an exact match to barCount - a mismatch
                // (wrong config picked up, stereo vs mono, etc.) used to
                // mean every single frame got silently dropped and the
                // bars froze at their initial levels forever. levels[i]
                // falling back to 0 below handles a short/long read fine.
                const parts = line.split(";").filter(p => p.length > 0)
                    .map(p => Math.max(0, Math.min(100, parseInt(p, 10) || 0)) / 100)
                if (parts.length > 0) {
                    root.levels = parts
                }
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: Config.scaled(4, root.uiScale)

        Repeater {
            model: root.barCount

            delegate: Rectangle {
                id: bar

                required property int index

                anchors.bottom: parent.bottom
                width: (parent.width - (root.barCount - 1) * parent.spacing) / root.barCount
                height: Math.max(1, parent.height * (root.levels[index] || 0))
                color: Config.fgcolor

                Behavior on height {
                    NumberAnimation { duration: 60 }
                }
            }
        }
    }
}

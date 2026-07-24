import QtQuick
import Quickshell
import Quickshell.Io
import "../../Config.js" as Config

// Audio visualizer: cava in raw/ascii output mode, using the dedicated
// config at .config/quickshell/cava/config (bars=25, method=raw/ascii) -
// passed explicitly via -p rather than relying on cava's default
// ~/.config/cava/config, so this doesn't fight whatever the user has set
// up for cava in an actual terminal. Parsed into a fixed set of bar
// levels and drawn as flat fgcolor bars growing up from the bottom.
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
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava/config"]

        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.split(";").filter(p => p.length > 0)
                if (parts.length === root.barCount) {
                    root.levels = parts.map(p => Math.max(0, Math.min(100, parseInt(p, 10))) / 100)
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

import QtQuick
import Quickshell
import Quickshell.Io

// Reads Hyprland's col.active_border color at startup and pushes it into
// Theme.fgcolor. Loaded via Loader{source:...} from shell.qml rather than
// instantiated directly - Theme.qml is a singleton and can't be isolated
// the same way, so this keeps a wrong guess here from being able to take
// the whole shell down with it; worst case Theme just keeps its fallback.
//
// One-shot read at startup, not a live watch - re-run `qs` after changing
// hyprland.conf's colors to pick up a new one.
Item {
    id: root

    Process {
        id: colorProcess

        command: ["grep", "-m1", "col.active_border", Quickshell.env("HOME") + "/.config/hypr/hyprland.conf"]
        running: true

        stdout: SplitParser {
            onRead: (line) => {
                const match = line.match(/rgba?\(([0-9a-fA-F]{6})[0-9a-fA-F]{0,2}\)/)
                if (match) {
                    Theme.fgcolor = "#" + match[1]
                }
            }
        }
    }
}

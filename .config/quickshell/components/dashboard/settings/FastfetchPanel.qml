import QtQuick
import Quickshell.Io
import "../"
import "../../../Config.js" as Config

// System info panel, opened by clicking the avatar. Reuses the same
// SettingsPanel "garage door" width-then-height reveal as Audio/Bluetooth.
// Runs the user's own fastfetch config (~/.config/fastfetch/config.jsonc)
// with the logo disabled - fastfetch's kitty-icat image logo needs an
// actual terminal graphics protocol, which a QML Text can't render, but
// the module output (user/host/distro/cpu/etc.) is plain text and works
// fine here. ANSI color codes are stripped since this panel uses a single
// flat Config.fgcolor for everything, like the rest of the dashboard.
SettingsPanel {
    id: root

    namespaceName: "fastfetchSettings"

    property var rawLines: []

    // Re-runs every time the panel opens (cheap, and picks up anything
    // that's changed since - uptime, etc.), same idea as Bluetooth's
    // scan-only-while-open.
    Process {
        running: root.active
        command: ["fastfetch", "--logo", "none"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.rawLines = text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\n")
            }
        }
    }

    Text {
        width: root.panelWidth

        topPadding: Config.scaled(16, root.uiScale)
        bottomPadding: Config.scaled(16, root.uiScale)
        leftPadding: Config.scaled(16, root.uiScale)
        rightPadding: Config.scaled(16, root.uiScale)

        text: root.rawLines.join("\n")
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(13, root.uiScale)
        wrapMode: Text.NoWrap
    }
}

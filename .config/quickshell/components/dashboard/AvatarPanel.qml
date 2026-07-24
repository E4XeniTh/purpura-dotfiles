import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "../../Config.js" as Config

// Avatar image that, on click, "opens like a garage door" - grows
// straight down in place (no separate popup window) to reveal a compact,
// hand-written fastfetch-style readout: the DISTRO..RAM slice of the
// user's own ~/.config/fastfetch/config.jsonc, using the same key labels.
// This is NOT the real fastfetch binary - its kitty-icat image logo needs
// an actual terminal graphics protocol a QML Text can't render, and only
// this one slice of the config is wanted here anyway - so the handful of
// fields are gathered directly (os-release, uname, /proc, /sys, lspci).
//
// squareSize is the closed (avatar-only) size; maxRevealExtra is how much
// taller this is allowed to grow when open, supplied by the caller so it
// can shrink whatever filler space is available by the exact same
// amount - see Dashboard.qml's centerColumn, where the filler DashCard's
// height already reactively subtracts this panel's height.
Item {
    id: root

    property real uiScale: 1.0
    property real squareSize: 100
    property real maxRevealExtra: 0
    property bool open: false

    readonly property real revealExtra: open ? maxRevealExtra : 0

    width: squareSize
    height: squareSize + revealExtra

    Behavior on height {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // Static for the life of the process (kernel/cpu/gpu/mobo/ram don't
    // change at runtime) - gathered once instead of re-run every open.
    property string distro: "..."
    property string kernel: "..."
    property string de: ""
    property string shellName: ""
    property string mobo: "..."
    property string cpu: "..."
    property string gpu: "..."
    property string memTotal: "..."

    Component.onCompleted: {
        const shellPath = Quickshell.env("SHELL")
        root.shellName = shellPath.length > 0 ? shellPath.split("/").pop() : ""
    }

    Process {
        running: true

        // Every field goes through $(...) and is only ever emitted by
        // the final printf, so a single failing command (permission
        // denied on board_name, no lspci, etc.) can only leave its own
        // line blank - never shift every field after it out of place.
        command: ["bash", "-c",
            "distro=$(source /etc/os-release 2>/dev/null; echo \"$NAME\"); " +
            "kernel=$(uname -r); " +
            "de=\"$XDG_CURRENT_DESKTOP\"; " +
            "mobo=$(cat /sys/class/dmi/id/board_name 2>/dev/null); " +
            "cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//'); " +
            "gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller' | head -n1 | cut -d: -f3- | sed 's/^ *//'); " +
            "mem=$(awk '/MemTotal/ { printf \"%.2f GiB\", $2/1024/1024 }' /proc/meminfo 2>/dev/null); " +
            "printf '%s\\n' \"$distro\" \"$kernel\" \"$de\" \"$mobo\" \"$cpu\" \"$gpu\" \"$mem\""
        ]

        stdout: SplitParser {
            property int lineIndex: 0

            onRead: (line) => {
                switch (lineIndex) {
                    case 0: root.distro = line.length > 0 ? line : "Unknown"; break
                    case 1: root.kernel = line; break
                    case 2: root.de = line; break
                    case 3: root.mobo = line.length > 0 ? line : "Unknown"; break
                    case 4: root.cpu = line.length > 0 ? line : "Unknown"; break
                    case 5: root.gpu = line.length > 0 ? line : "Unknown"; break
                    case 6: root.memTotal = line; break
                }
                lineIndex++
            }
        }
    }

    // Rows mirror ~/.config/fastfetch/config.jsonc's own key labels
    // verbatim, DISTRO through RAM - WM and BOOTMGR are hardcoded here
    // the same way that config hardcodes them (custom/format, not
    // detected), since this is one specific known machine/setup.
    readonly property var rows: [
        { key: "╭─  DISTRO   ", value: root.distro },
        { key: "│  󰐦 BOOTMGR  ", value: "rEFInd" },
        { key: "│   KERNEL   ", value: root.kernel },
        { key: "│  󰇄 DE       ", value: root.de },
        { key: "│   WM       ", value: "Hyprland" },
        { key: "│   TERM     ", value: Quickshell.env("TERM") || "-" },
        { key: "╰─  SHELL    ", value: root.shellName },
        { key: "╭─ 󰘚 MOBO     ", value: root.mobo },
        { key: "│   CPU      ", value: root.cpu },
        { key: "│  󰢮 GPU      ", value: root.gpu },
        { key: "╰─  RAM      ", value: root.memTotal }
    ]

    DashCard {
        uiScale: root.uiScale
        anchors.fill: parent
        clip: true

        Image {
            id: avatarImage
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 2
            }
            height: root.squareSize - 4

            source: "file://" + Quickshell.env("HOME") + "/.face"
            fillMode: Image.PreserveAspectCrop
            clip: true
        }

        Column {
            anchors {
                top: avatarImage.bottom
                left: parent.left
                right: parent.right
                margins: Config.scaled(6, root.uiScale)
            }

            Repeater {
                model: root.rows

                delegate: Text {
                    required property var modelData

                    width: parent.width
                    text: modelData.key + modelData.value
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(10, root.uiScale)
                    elide: Text.ElideRight
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.open = !root.open
    }
}

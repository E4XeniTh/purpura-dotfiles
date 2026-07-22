import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import QtQuick
import "../"
import "../../Config.js" as Config

// Dashboard dropdown, toggled from the avatar button in Bar.qml. Uses the
// same two-phase stretch-then-drop animation as Tray.qml's context menu.
// dashBox is fully opaque; each section inside sits in its own
// Config.fgcolor card.
//
// Sizing rule: dashWidth/columnHeight scale with the screen, and every
// section within is a fraction of *available* space (container size minus
// its own padding/spacing), so fractions on the same axis always sum to
// 1.0 with no leftover/overflow. Small fixed-purpose elements (icon sizes,
// border widths, small button/font sizes) are kept as plain pixel values
// on purpose - scaling those by screen size tends to look wrong long
// before it looks "adaptive".
Scope {
    id: root

    property bool open: false
    property var screen: null

    // Set from shell.qml, so the power/lock buttons below can call these
    // directly instead of round-tripping through `qs ipc call` to talk to
    // another component in the very same process.
    property var powerMenu: null
    property var lockScreen: null

    function close() {
        open = false
        screen = null
    }

    function toggle(screen_) {
        if (open && screen === screen_) {
            close()
        } else {
            open = true
            screen = screen_
        }
    }

    IpcHandler {
        target: "dashboard"

        // A keybind/IPC call carries no click position, so there's no
        // "which screen was clicked" the way there is from Bar.qml's
        // clock button - this just always targets the primary screen.
        function toggle(): void { root.toggle(Quickshell.screens[0]) }
        function show(): void {
            root.open = true
            root.screen = Quickshell.screens[0]
        }
        function hide(): void { root.close() }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dashWindow

            property var modelData
            screen: modelData

            // Screen-relative base size. ~0.42/0.43 reproduces the 800x460
            // this was tuned at on a 1920x1080 screen, just no longer fixed.
            property real dashWidth: modelData.width * 0.42
            property real columnHeight: modelData.height * 0.43

            visible: root.open && root.screen === modelData

            WlrLayershell.namespace: "dashboard"
            WlrLayershell.layer: WlrLayer.Overlay

            exclusiveZone: 0

            // Anchoring only the top edge (no left/right) lets the
            // compositor center the window on that axis natively, instead
            // of us computing screen-width math.
            anchors {
                top: true
            }

            margins {
                // Bar's own top margin (10) + height (48) - border width
                // (2), so this window's top edge lands on the bar's bottom
                // border instead of leaving a gap or a seam.
                top: 4
            }

            implicitWidth: dashWidth
            implicitHeight: Math.max(dashContent.height, 1)

            color: "transparent"

            Rectangle {
                id: dashBox

                anchors.horizontalCenter: parent.horizontalCenter

                width: 0
                height: 4

                // Fully opaque - each section below sits on top of this in
                // its own Config.fgcolor card.
                color: Config.fillcolor

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: dashBox

                            width: dashWidth
                            height: 2
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: dashBox

                            width: dashWidth
                            height: Math.max(dashContent.height, 1)
                        }
                    }

                ]

                transitions: [

                    Transition {

                        NumberAnimation {

                            properties: "width,height"

                            duration: 300

                            easing.type: Easing.OutCubic

                        }

                    }

                ]

                Item {
                    id: contentMask

                    anchors.fill: parent
                    clip: true

                    Row {
                        id: dashContent

                        width: dashWidth

                        topPadding: 16
                        bottomPadding: 16
                        leftPadding: 16
                        rightPadding: 16
                        spacing: 16

                        // Space actually left for the 3 columns once outer
                        // padding and the 2 inter-column gaps are removed.
                        // Column width fractions below sum to 1.0 against
                        // this, not against the raw dashWidth.
                        readonly property real availableWidth: width - leftPadding - rightPadding - 2 * spacing

                        // ---------------- LEFT COLUMN ----------------
                        Column {
                            id: leftColumn

                            width: dashContent.availableWidth * 0.35
                            height: columnHeight
                            spacing: 10

                            // top left: large numerical clock
                            Rectangle {
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.2
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor

                                Clock {
                                    anchors.centerIn: parent
                                    font.family: Config.fontfamily
                                    font.pixelSize: parent.height * 0.75
                                    color: Config.fgcolor
                                }
                            }

                            // middle left: current weather (wttr.in, no API
                            // key needed - refreshes every 15 min)

                            Rectangle {
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.3
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor

                                Weather {
                                    anchors.fill: parent
                                }
                            }

                            // bottom left: calendar
                            Rectangle {
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.5
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor

                                Calendar {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    anchors.topMargin: 20
                                }
                            }
                        }

                        // --------------- CENTER COLUMN ----------------
                        Column {
                            id: centerColumn

                            width: dashContent.availableWidth * 0.30
                            height: columnHeight
                            spacing: 10
                            // Square, but never taller than its share of
                            // the column's height budget.

                            // top center: 5 placeholder buttons (volume,
                            // network, bluetooth, two spares)
                            Rectangle {
                                id: greetingtext
                                width: parent.width
                                height: 32
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor

                                property string hostname: ""

                                // One-shot, not periodic - the machine's
                                // hostname doesn't change at runtime.
                                Process {
                                    running: true
                                    command: ["hostname"]

                                    stdout: SplitParser {
                                        onRead: (line) => {
                                            if (line.trim().length > 0) {
                                                greetingtext.hostname = line.trim()
                                            }
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent

                                    text: Quickshell.env("USER") + "@" + (greetingtext.hostname.length > 0 ? greetingtext.hostname : "...")

                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: 16

                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                id: avatarbox
                                width: parent.width
                                height: parent.width
                                color: "transparent"

                                Rectangle {
                                    anchors.centerIn: parent

                                    width: parent.width
                                    height: parent.height
                                    color: Config.fillcolor
                                    border.width: 2
                                    border.color: Config.fgcolor

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2

                                        source: "file://" + Quickshell.env("HOME") + "/.face"
                                        fillMode: Image.PreserveAspectCrop
                                        clip: true
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: {
                                    columnHeight -
                                    greetingtext.height -
                                    avatarbox.height -
                                    powerrow.height -
                                    systemicons.height -
                                    (parent.spacing * 4)
                                }
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor
                            }

                            Rectangle {
                                id: powerrow
                                width: parent.width
                                height: 48
                                color: "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: powerrow.width / 11

                                    Rectangle {
                                        width: powerrow.width / 2.2
                                        height: 48
                                        color: mouseAreaPower.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                        border.width: 2
                                        border.color: Config.fgcolor

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 36
                                            source: Quickshell.iconPath("system-shutdown-symbolic")
                                        }

                                        MouseArea {
                                            id: mouseAreaPower
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.close()
                                                if (root.powerMenu) {
                                                    root.powerMenu.open = true
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: powerrow.width / 2.2
                                        height: 48
                                        color: mouseAreaLock.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                        border.width: 2
                                        border.color: Config.fgcolor

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 36
                                            source: Quickshell.iconPath("system-lock-screen-symbolic")
                                        }

                                        MouseArea {
                                            id: mouseAreaLock
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.close()
                                                if (root.lockScreen) {
                                                    root.lockScreen.locked = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Item {}

                            Rectangle {
                                id: systemicons
                                width: parent.width
                                height: 32
                                color: "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Repeater {
                                        model: ["audio-volume-high-symbolic", "network-wireless-symbolic", "network-bluetooth", "battery-100-symbolic", "", ""]

                                        delegate: Rectangle {
                                            required property string modelData

                                            width: 32
                                            height: 32
                                            color: Config.fillcolor
                                            border.width: 2
                                            border.color: Config.fgcolor

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: 20
                                                visible: modelData.length > 0
                                                source: modelData.length > 0 ? Quickshell.iconPath(modelData) : ""
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---------------- RIGHT COLUMN ----------------
                        // Now playing (2/3) + an empty 1/3 reserved for
                        // future content.
                        Column {
                            id: rightColumn

                            width: dashContent.availableWidth * 0.35
                            height: columnHeight
                            spacing: 10

                            // Now playing + cava. Loaded lazily by path
                            // (not instantiated directly) so a wrong
                            // MPRIS/cava API guess only blanks this card
                            // instead of breaking the whole shell - verify
                            // this one live.
                            Rectangle {
                                width: parent.width
                                height: (columnHeight - parent.spacing) * (2 / 3)
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor

                                Loader {
                                    anchors.fill: parent
                                    anchors.margins: 12

                                    source: "NowPlaying.qml"
                                }
                            }

                            // Reserved for future use.
                            Rectangle {
                                width: parent.width
                                height: (columnHeight - parent.spacing) * (1 / 3)
                                color: Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.width: 2
                    border.color: Config.fgcolor

                    radius: 0

                    z: 10
                }
            }

            onVisibleChanged: {
                if (visible) {
                    dashBox.width = 0
                    dashBox.height = 4

                    dashBox.state = "horizontal"
                    dashOpenTimer.start()
                }
            }

            Timer {
                id: dashOpenTimer

                // Must match the transition's duration above, so phase 1
                // (width) fully finishes before phase 2 (height) starts.
                interval: 300
                repeat: false

                onTriggered: {
                    dashBox.state = "open"
                }
            }
        }
    }
}

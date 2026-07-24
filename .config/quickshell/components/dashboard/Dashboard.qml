import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import QtQuick
import "../"
import "settings"
import "../../Config.js" as Config

// Dashboard dropdown, toggled from the avatar button in Bar.qml. Uses the
// same two-phase stretch-then-drop animation as Tray.qml's context menu.
// dashBox is fully opaque; each section inside sits in its own DashCard.
//
// Sizing rule: dashWidth/columnHeight scale with the screen, and every
// section within is a fraction of *available* space (container size minus
// its own padding/spacing), so fractions on the same axis always sum to
// 1.0 with no leftover/overflow. Everything else (fonts, icons, borders,
// spacing) scales with uiScale, computed against the 800px-wide reference
// this layout was tuned at on a 1920x1080 screen - see dashWindow below.
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

            // Everything sized in plain pixels below (fonts, icons,
            // borders, spacing) is written at its 800px-reference value
            // and multiplied by this. Clamped so a tiny or huge monitor
            // doesn't make text illegibly small or comically large.
            property real uiScale: Math.max(0.6, Math.min(1.8, dashWidth / 800))

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
                // its own DashCard.
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

                        topPadding: Config.scaled(16, dashWindow.uiScale)
                        bottomPadding: Config.scaled(16, dashWindow.uiScale)
                        leftPadding: Config.scaled(16, dashWindow.uiScale)
                        rightPadding: Config.scaled(16, dashWindow.uiScale)
                        spacing: Config.scaled(16, dashWindow.uiScale)

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
                            spacing: Config.scaled(10, dashWindow.uiScale)

                            // top left: large numerical clock
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.2

                                Clock {
                                    anchors.centerIn: parent
                                    font.family: Config.fontfamily
                                    font.pixelSize: parent.height * 0.75
                                    color: Config.fgcolor
                                }
                            }

                            // middle left: current weather (wttr.in, no API
                            // key needed - refreshes every 15 min)
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.3

                                Weather {
                                    anchors.fill: parent
                                    uiScale: dashWindow.uiScale
                                }
                            }

                            // bottom left: calendar
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.5

                                Calendar {
                                    anchors.fill: parent
                                    anchors.margins: Config.scaled(8, dashWindow.uiScale)
                                    anchors.topMargin: Config.scaled(20, dashWindow.uiScale)
                                    uiScale: dashWindow.uiScale
                                }
                            }
                        }

                        // --------------- CENTER COLUMN ----------------
                        Column {
                            id: centerColumn

                            width: dashContent.availableWidth * 0.30
                            height: columnHeight
                            spacing: Config.scaled(10, dashWindow.uiScale)
                            // Square, but never taller than its share of
                            // the column's height budget.

                            // top center: hostname/user greeting
                            DashCard {
                                id: greetingtext
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: Config.scaled(32, dashWindow.uiScale)

                                property string hostname: ""

                                // One-shot, not periodic - the machine's
                                // hostname doesn't change at runtime.
                                Process {
                                    running: true
                                    command: ["hostnamectl", "hostname"]

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
                                    font.pixelSize: Config.scaled(16, dashWindow.uiScale)

                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                id: avatarbox
                                width: parent.width
                                height: parent.width
                                color: "transparent"

                                DashCard {
                                    uiScale: dashWindow.uiScale
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2

                                        source: "file://" + Quickshell.env("HOME") + "/.face"
                                        fillMode: Image.PreserveAspectCrop
                                        clip: true
                                    }
                                }
                            }

                            // Empty filler - absorbs whatever height the
                            // fixed-size siblings above/below don't use.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: columnHeight - greetingtext.height - avatarbox.height - powerrow.height - systemicons.height - parent.spacing * 4
                            }

                            Rectangle {
                                id: powerrow
                                width: parent.width
                                height: Config.scaled(48, dashWindow.uiScale)
                                color: "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: powerrow.width / 11

                                    DashCard {
                                        uiScale: dashWindow.uiScale
                                        width: powerrow.width / 2.2
                                        height: powerrow.height
                                        color: mouseAreaPower.containsMouse ? Config.fgcolorhover : Config.fillcolor

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: Config.scaled(36, dashWindow.uiScale)
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

                                    DashCard {
                                        uiScale: dashWindow.uiScale
                                        width: powerrow.width / 2.2
                                        height: powerrow.height
                                        color: mouseAreaLock.containsMouse ? Config.fgcolorhover : Config.fillcolor

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: Config.scaled(36, dashWindow.uiScale)
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
                                height: Config.scaled(32, dashWindow.uiScale)
                                color: "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Config.scaled(6, dashWindow.uiScale)

                                    Repeater {
                                        model: ["audio-volume-high-symbolic", "network-wireless-symbolic", "network-bluetooth", "battery-100-symbolic", "", ""]

                                        delegate: DashCard {
                                            required property string modelData
                                            required property int index
                                            uiScale: dashWindow.uiScale

                                            width: systemicons.height
                                            height: systemicons.height
                                            color: iconMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: Config.scaled(20, dashWindow.uiScale)
                                                visible: modelData.length > 0
                                                source: modelData.length > 0 ? Quickshell.iconPath(modelData) : ""
                                            }

                                            // Only the audio icon (index 0) opens anything so far -
                                            // the rest are reserved for the same settings-button
                                            // treatment later, but all of them hover-highlight
                                            // already.
                                            MouseArea {
                                                id: iconMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    if (index === 0) {
                                                        soundSettings.toggle()
                                                    }
                                                }
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
                            spacing: Config.scaled(10, dashWindow.uiScale)

                            // Now playing + cava. Loaded lazily by path
                            // (not instantiated directly) so a wrong
                            // MPRIS/cava API guess only blanks this card
                            // instead of breaking the whole shell - verify
                            // this one live.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - parent.spacing) * (2 / 3)

                                Loader {
                                    id: nowPlayingLoader
                                    anchors.fill: parent
                                    anchors.margins: Config.scaled(12, dashWindow.uiScale)

                                    source: "NowPlaying.qml"
                                }

                                // A one-time onLoaded assignment freezes at whatever
                                // uiScale happened to be when the Loader finished (which
                                // can be before dashWindow.uiScale settles to its final
                                // value) - a live Binding keeps it tracking afterwards.
                                Binding {
                                    target: nowPlayingLoader.item
                                    property: "uiScale"
                                    value: dashWindow.uiScale
                                    when: nowPlayingLoader.item !== null
                                }
                            }

                            // Reserved for future use.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - parent.spacing) * (1 / 3)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.width: Config.scaled(2, dashWindow.uiScale)
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
                } else {
                    soundSettings.close()
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

            // Sound settings, opened from the audio icon above. Anchored
            // directly below dashBox's own border (same width, same
            // screen) so it reads as an extension of the dashboard rather
            // than an unrelated popup.
            SoundSettings {
                id: soundSettings

                screen: dashWindow.screen
                panelWidth: dashWidth
                uiScale: dashWindow.uiScale
                anchorTop: dashWindow.margins.top + dashWindow.height + Config.scaled(8, dashWindow.uiScale)
            }
        }
    }
}

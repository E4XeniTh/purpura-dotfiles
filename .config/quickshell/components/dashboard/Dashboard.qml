import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import "../"
import "../powermenu"
import "../lockscreen"

// Dashboard dropdown, toggled from the avatar button in Bar.qml. Uses the
// same two-phase stretch-then-drop animation as TrayMenu.qml. dashBox is
// fully opaque; each section inside sits in its own Theme.fgcolor card.
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

            visible: DashboardState.open && DashboardState.screen === modelData

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
                // its own Theme.fgcolor card.
                color: Theme.fillcolor

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
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor

                                Clock {
                                    anchors.centerIn: parent
                                    font.family: "monospace"
                                    font.pixelSize: parent.height * 0.75
                                    color: Theme.fgcolor
                                }
                            }

                            // middle left: current weather (wttr.in, no API
                            // key needed - refreshes every 15 min)
                            Rectangle {
                                id: weatherBox

                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.3
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor

                                property string conditionText: "Loading..."
                                property string tempText: ""

                                // Freedesktop's weather-*-symbolic set doesn't
                                // have a one-to-one entry for every wttr.in
                                // condition string, so this is a coarse
                                // keyword match rather than a precise table -
                                // good enough for a small bar widget icon.
                                function iconForCondition(condition) {
                                    const c = condition.toLowerCase()
                                    if (c.includes("thunder")) return "weather-storm-symbolic"
                                    if (c.includes("snow") || c.includes("sleet") || c.includes("ice")) return "weather-snow-symbolic"
                                    if (c.includes("rain") || c.includes("drizzle") || c.includes("shower")) return "weather-showers-symbolic"
                                    if (c.includes("fog") || c.includes("mist") || c.includes("haze")) return "weather-fog-symbolic"
                                    if (c.includes("overcast")) return "weather-overcast-symbolic"
                                    if (c.includes("cloud")) return "weather-few-clouds-symbolic"
                                    return "weather-clear-symbolic"
                                }

                                // "|" is a literal delimiter (not whitespace)
                                // since the condition text itself contains
                                // spaces ("Partly cloudy").
                                Process {
                                    id: weatherProcess

                                    command: ["curl", "-s", "-A", "curl", "https://wttr.in/?format=%C|%t"]

                                    stdout: SplitParser {
                                        onRead: (line) => {
                                            const trimmed = line.trim()
                                            if (trimmed.length === 0) {
                                                return
                                            }
                                            const parts = trimmed.split("|")
                                            weatherBox.conditionText = parts[0]
                                            weatherBox.tempText = parts.length > 1 ? parts[1] : ""
                                        }
                                    }

                                    onExited: (exitCode) => {
                                        if (exitCode !== 0) {
                                            weatherBox.conditionText = "Weather unavailable"
                                            weatherBox.tempText = ""
                                        }
                                    }
                                }

                                Timer {
                                    interval: 15 * 60 * 1000
                                    running: true
                                    repeat: true
                                    triggeredOnStart: true

                                    onTriggered: {
                                        // Force a real false->true transition.
                                        // Re-assigning `true` while it's
                                        // already true (left over from the
                                        // last run) is a no-op in QML, so
                                        // this is what actually makes it
                                        // re-fetch on every interval.
                                        weatherProcess.running = false
                                        weatherProcess.running = true
                                    }
                                }

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 20

                                    IconImage {
                                        id: weatherIconImage
                                        anchors {
                                            left: parent.left
                                            verticalCenter: parent.verticalCenter
                                        }
                                        implicitSize: 84
                                        source: Quickshell.iconPath(weatherBox.iconForCondition(weatherBox.conditionText))
                                    }

                                    // Symbolic icons are a plain alpha-masked
                                    // shape, so ColorOverlay can tint them
                                    // cleanly to the theme color - this
                                    // paints over weatherIconImage, which is
                                    // why it's declared after it.
                                    ColorOverlay {
                                        anchors.fill: weatherIconImage
                                        source: weatherIconImage
                                        color: Theme.fgcolor
                                    }

                                    Column {
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }

                                        width: parent.width - weatherIconImage.width - 12
                                        spacing: 0

                                        Text {
                                            width: parent.width
                                            text: weatherBox.conditionText
                                            color: Theme.fgcolor
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            horizontalAlignment: Text.AlignRight
                                            verticalAlignment: Text.AlignBottom
                                            elide: Text.ElideLeft
                                        }

                                        Text {
                                            width: parent.width
                                            text: weatherBox.tempText
                                            color: Theme.fgcolor
                                            font.family: "monospace"
                                            font.pixelSize: 36
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                            }

                            // bottom left: calendar
                            Rectangle {
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.5
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor

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
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor
                                Text {
                                    anchors.centerIn: parent

                                    text: "fayelia@factory"
                                    // or simply:
                                    // text: "hostname@username"

                                    color: Theme.fgcolor
                                    font.family: "monospace"
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
                                    color: Theme.fillcolor
                                    border.width: 2
                                    border.color: Theme.fgcolor

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
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor
                            }

                            Rectangle {
                                id: powerrow
                                width: parent.width
                                height: 48
                                color: Theme.fillcolor

                                Row {
                                    anchors.centerIn: parent
                                    spacing: powerrow.width / 11

                                    Rectangle {
                                        width: powerrow.width / 2.2
                                        height: 48
                                        color: mouseAreaPower.containsMouse ? Theme.fgcolorhover : "transparent"
                                        border.width: 2
                                        border.color: Theme.fgcolor

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
                                                DashboardState.close()
                                                PowerMenuState.open = true
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: powerrow.width / 2.2
                                        height: 48
                                        color: mouseAreaLock.containsMouse ? Theme.fgcolorhover : "transparent"
                                        border.width: 2
                                        border.color: Theme.fgcolor

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
                                                DashboardState.close()
                                                LockScreenState.locked = true
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
                                color: Theme.fillcolor

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Repeater {
                                        model: ["audio-volume-high-symbolic", "network-wireless-symbolic", "network-bluetooth", "battery-100-symbolic", "", ""]

                                        delegate: Rectangle {
                                            required property string modelData

                                            width: 32
                                            height: 32
                                            color: Theme.fillcolor
                                            border.width: 2
                                            border.color: Theme.fgcolor

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
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor

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
                                color: Theme.fillcolor
                                border.width: 2
                                border.color: Theme.fgcolor
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.width: 2
                    border.color: Theme.fgcolor

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

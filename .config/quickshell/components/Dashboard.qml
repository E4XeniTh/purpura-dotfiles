import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// Dashboard dropdown, toggled from the avatar button in Bar.qml. Uses the
// same two-phase stretch-then-drop animation as TrayMenu.qml. dashBox is
// fully opaque; each section inside sits in its own Theme.fgcolor card.
Scope {
    id: root

    readonly property int dashWidth: 800
    readonly property int columnHeight: 460

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dashWindow

            property var modelData
            screen: modelData

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
                top: 56
            }

            implicitWidth: root.dashWidth
            implicitHeight: Math.max(dashContent.height, 1)

            color: "transparent"

            Rectangle {
                id: dashBox

                anchors.horizontalCenter: parent.horizontalCenter

                width: 0
                height: 4

                // Fully opaque - each section below sits on top of this in
                // its own Theme.fgcolor card.
                color: Qt.rgba(0, 0, 0, 1)

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: dashBox

                            width: root.dashWidth
                            height: 2
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: dashBox

                            width: root.dashWidth
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

                        width: root.dashWidth

                        topPadding: 16
                        bottomPadding: 16
                        leftPadding: 16
                        rightPadding: 16
                        spacing: 16

                        // ---------------- LEFT COLUMN ----------------
                        Column {
                            id: leftColumn

                            width: 260
                            height: root.columnHeight
                            spacing: 10

                            // top left, 1/5: large numerical clock
                            Rectangle {
                                width: parent.width
                                height: (root.columnHeight - 2 * parent.spacing) * 0.2
                                color: Theme.fgcolor

                                Clock {
                                    anchors.centerIn: parent
                                    font.pixelSize: 34
                                    color: "black"
                                }
                            }

                            // middle left, 1/5: current weather (wttr.in,
                            // no API key needed - refreshes every 15 min)
                            Rectangle {
                                id: weatherBox

                                width: parent.width
                                height: (root.columnHeight - 2 * parent.spacing) * 0.2
                                color: Theme.fgcolor

                                property string weatherText: "Loading..."

                                Timer {
                                    interval: 15 * 60 * 1000
                                    running: true
                                    repeat: true
                                    triggeredOnStart: true

                                    onTriggered: {
                                        const xhr = new XMLHttpRequest()
                                        xhr.onreadystatechange = () => {
                                            if (xhr.readyState === XMLHttpRequest.DONE) {
                                                weatherBox.weatherText = xhr.status === 200
                                                    ? xhr.responseText.trim()
                                                    : "Weather unavailable"
                                            }
                                        }
                                        xhr.open("GET", "https://wttr.in/?format=%C+%t")
                                        xhr.send()
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 16

                                    text: weatherBox.weatherText
                                    color: "black"
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            // bottom left, 3/5: calendar
                            Rectangle {
                                width: parent.width
                                height: (root.columnHeight - 2 * parent.spacing) * 0.6
                                color: Theme.fgcolor

                                Calendar {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                }
                            }
                        }

                        // --------------- CENTER COLUMN ----------------
                        Column {
                            id: centerColumn

                            width: 176
                            height: root.columnHeight
                            spacing: 10

                            // top center: 5 placeholder buttons (volume,
                            // network, bluetooth, two spares)
                            Rectangle {
                                width: parent.width
                                height: 70
                                color: Theme.fgcolor

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Repeater {
                                        model: ["audio-volume-high-symbolic", "network-wireless-symbolic", "bluetooth-symbolic", "", ""]

                                        delegate: Rectangle {
                                            required property string modelData

                                            width: 26
                                            height: 26
                                            color: "transparent"
                                            border.width: 1
                                            border.color: "black"

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: 15
                                                visible: modelData.length > 0
                                                source: modelData.length > 0 ? Quickshell.iconPath(modelData) : ""
                                            }
                                        }
                                    }
                                }
                            }

                            // middle center: avatar
                            Rectangle {
                                width: parent.width
                                height: root.columnHeight - 70 - 90 - 2 * parent.spacing
                                color: Theme.fgcolor

                                Rectangle {
                                    anchors.centerIn: parent

                                    width: 72
                                    height: 72
                                    color: "black"

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 3

                                        source: "file://" + Quickshell.env("HOME") + "/.face"
                                        fillMode: Image.PreserveAspectCrop
                                        clip: true
                                    }
                                }
                            }

                            // bottom center: power + lock
                            Rectangle {
                                width: parent.width
                                height: 90
                                color: Theme.fgcolor

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 16

                                    Rectangle {
                                        width: 48
                                        height: 48
                                        color: "black"
                                        border.width: 2
                                        border.color: Theme.fgcolordark

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 26
                                            source: Quickshell.iconPath("system-shutdown-symbolic")
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                DashboardState.close()
                                                PowerMenuState.open = true
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 48
                                        height: 48
                                        color: "black"
                                        border.width: 2
                                        border.color: Theme.fgcolordark

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 26
                                            source: Quickshell.iconPath("system-lock-screen-symbolic")
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                DashboardState.close()
                                                LockMenuState.locked = true
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---------------- RIGHT COLUMN ----------------
                        // Now playing + cava. Loaded lazily by path (not
                        // instantiated directly) so a wrong MPRIS/cava API
                        // guess only blanks this card instead of breaking
                        // the whole shell - verify this one live.
                        Rectangle {
                            width: 300
                            height: root.columnHeight
                            color: Theme.fgcolor

                            Loader {
                                anchors.fill: parent
                                anchors.margins: 12

                                source: "NowPlaying.qml"
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

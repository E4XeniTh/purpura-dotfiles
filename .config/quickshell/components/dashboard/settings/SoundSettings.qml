import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import "../../../Config.js" as Config

// Playback/recording device list + volume sliders, opened from Dashboard's
// audio icon. Instantiated inside dashWindow (see Dashboard.qml) so it can
// anchor directly below it on the same screen, using the same two-phase
// stretch-then-drop animation as Dashboard.qml/Tray.qml's context menu.
PanelWindow {
    id: root

    property bool open: false
    property real panelWidth: 800
    property real anchorTop: 0
    property real uiScale: 1.0

    function close() { root.open = false }
    function toggle() { root.open = !root.open }

    // All hardware (non-stream) audio nodes, split by direction. Bound via
    // PwObjectTracker below so .audio.volume/.muted are valid to use - see
    // Quickshell's Pipewire docs, audio properties are otherwise invalid.
    readonly property var playbackNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var recordingNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink)

    PwObjectTracker {
        objects: root.playbackNodes.concat(root.recordingNodes)
    }

    visible: root.open

    WlrLayershell.namespace: "soundSettings"
    WlrLayershell.layer: WlrLayer.Overlay

    exclusiveZone: 0

    anchors {
        top: true
    }

    margins {
        top: root.anchorTop
    }

    implicitWidth: root.panelWidth
    implicitHeight: Math.max(soundContent.height, 1)

    color: "transparent"

    Rectangle {
        id: soundBox

        anchors.horizontalCenter: parent.horizontalCenter

        width: 0
        height: 4

        color: Config.fillcolor

        states: [

            State {
                name: "horizontal"

                PropertyChanges {
                    target: soundBox

                    width: root.panelWidth
                    height: 2
                }
            },

            State {
                name: "open"

                PropertyChanges {
                    target: soundBox

                    width: root.panelWidth
                    height: Math.max(soundContent.height, 1)
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
            anchors.fill: parent
            clip: true

            Column {
                id: soundContent

                width: root.panelWidth

                topPadding: Config.scaled(16, root.uiScale)
                bottomPadding: Config.scaled(16, root.uiScale)
                leftPadding: Config.scaled(16, root.uiScale)
                rightPadding: Config.scaled(16, root.uiScale)
                spacing: Config.scaled(10, root.uiScale)

                readonly property real contentWidth: width - leftPadding - rightPadding
                readonly property real columnWidth: (contentWidth - columnsRow.spacing) / 2
                readonly property real cardHeight: Config.scaled(64, root.uiScale)

                // Hint that right-click (anywhere on a device card below)
                // is what selects it as the primary device - not otherwise
                // discoverable. A plain Item, not a Row/Column, since the
                // icon+overlay pair inside needs its own anchors and
                // positioners fight children that set their own anchors.
                Item {
                    width: soundContent.contentWidth
                    height: Config.scaled(14, root.uiScale)

                    Item {
                        id: selectHintIconBox
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.scaled(12, root.uiScale)
                        height: Config.scaled(12, root.uiScale)

                        IconImage {
                            id: selectHintIcon
                            anchors.fill: parent
                            source: Quickshell.iconPath("input-mouse-click-right-symbolic")
                        }

                        ColorOverlay {
                            anchors.fill: selectHintIcon
                            source: selectHintIcon
                            color: Config.fgcolordark
                        }
                    }

                    Text {
                        anchors {
                            left: selectHintIconBox.right
                            leftMargin: Config.scaled(4, root.uiScale)
                            verticalCenter: parent.verticalCenter
                        }
                        text: "Select"
                        color: Config.fgcolordark
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(10, root.uiScale)
                    }
                }

                Row {
                    id: columnsRow
                    width: soundContent.contentWidth
                    spacing: Config.scaled(16, root.uiScale)

                    Column {
                        width: soundContent.columnWidth
                        spacing: Config.scaled(10, root.uiScale)

                        Text {
                            text: "Playback"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, root.uiScale)
                            font.bold: true
                        }

                        Repeater {
                            model: ScriptModel { values: root.playbackNodes }

                            delegate: DeviceCard {
                                required property var modelData

                                width: soundContent.columnWidth
                                height: soundContent.cardHeight
                                uiScale: root.uiScale
                                device: modelData
                                isPrimary: Boolean(Pipewire.defaultAudioSink) && modelData.id === Pipewire.defaultAudioSink.id
                                onSelected: Pipewire.preferredDefaultAudioSink = modelData
                            }
                        }
                    }

                    Column {
                        width: soundContent.columnWidth
                        spacing: Config.scaled(10, root.uiScale)

                        Text {
                            text: "Recording"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, root.uiScale)
                            font.bold: true
                        }

                        Repeater {
                            model: ScriptModel { values: root.recordingNodes }

                            delegate: DeviceCard {
                                required property var modelData

                                width: soundContent.columnWidth
                                height: soundContent.cardHeight
                                uiScale: root.uiScale
                                device: modelData
                                isPrimary: Boolean(Pipewire.defaultAudioSource) && modelData.id === Pipewire.defaultAudioSource.id
                                onSelected: Pipewire.preferredDefaultAudioSource = modelData
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent

            color: "transparent"

            border.width: Config.scaled(2, root.uiScale)
            border.color: Config.fgcolor

            radius: 0

            z: 10
        }
    }

    onVisibleChanged: {
        if (visible) {
            soundBox.width = 0
            soundBox.height = 4

            soundBox.state = "horizontal"
            soundOpenTimer.start()
        }
    }

    Timer {
        id: soundOpenTimer

        // Must match the transition's duration above, so phase 1 (width)
        // fully finishes before phase 2 (height) starts.
        interval: 300
        repeat: false

        onTriggered: {
            soundBox.state = "open"
        }
    }
}

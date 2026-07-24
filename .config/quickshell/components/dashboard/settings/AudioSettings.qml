import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// Playback/recording device list + volume sliders, opened from Dashboard's
// audio icon. Instantiated inside dashWindow (see Dashboard.qml), which
// also drives `active` through its settings-panel coordinator so this
// closes seamlessly if another panel (weather, bluetooth, ...) opens.
SettingsPanel {
    id: root

    namespaceName: "audioSettings"

    // All hardware (non-stream) audio nodes, split by direction. Bound via
    // PwObjectTracker below so .audio.volume/.muted are valid to use - see
    // Quickshell's Pipewire docs, audio properties are otherwise invalid.
    readonly property var playbackNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var recordingNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink)

    PwObjectTracker {
        objects: root.playbackNodes.concat(root.recordingNodes)
    }

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
        readonly property real cardHeight: Config.scaled(76, root.uiScale)

        // Hint that right-click (anywhere on a device card below) is what
        // selects it as the primary device - not otherwise discoverable.
        // A plain Item, not a Row/Column, since the icon+overlay pair
        // inside needs its own anchors and positioners fight children
        // that set their own anchors.
        Item {
            width: soundContent.contentWidth
            height: Config.scaled(14, root.uiScale)

            Item {
                id: selectHintIconBox
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: Config.scaled(18, root.uiScale)
                height: Config.scaled(18, root.uiScale)

                IconImage {
                    id: selectHintIcon
                    anchors.fill: parent
                    source: Quickshell.iconPath("input-mouse-click-right-symbolic")
                }

                ColorOverlay {
                    anchors.fill: selectHintIcon
                    source: selectHintIcon
                    color: Config.fgcolor
                }
            }

            Text {
                anchors {
                    right: selectHintIconBox.right
                    rightMargin: Config.scaled(24, root.uiScale)
                    verticalCenter: parent.verticalCenter
                }
                text: "Select"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
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

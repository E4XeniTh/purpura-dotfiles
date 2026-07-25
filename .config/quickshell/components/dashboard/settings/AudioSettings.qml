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

    // preferredDefaultAudioSink/Source is only a hint to Pipewire/
    // WirePlumber - defaultAudioSink/Source (what the border color used
    // to read directly) is whatever WirePlumber's own policy actually
    // decides, and in practice it doesn't reliably emit a change at all
    // once quickshell's already running (confirmed live: VolumeOsd.qml,
    // the only other place that reads defaultAudioSink, kept following
    // the old device until quickshell was restarted). Tracking the last
    // id clicked instead makes the highlight follow the click
    // unconditionally, only falling back to the real Pipewire state
    // before anything's been clicked this session.
    //
    // Fed in from Dashboard.qml (root.audioSelectedSinkId/-SourceId
    // there) rather than owned here - this instance is local to one
    // screen's dashWindow, but VolumeOsd.qml (instantiated separately in
    // shell.qml) needs the same "last explicitly selected" value too, so
    // it has to be a single value shared outside any one screen's
    // instance - see Dashboard.qml for the same reasoning already
    // applied to identifying/primaryMonitor.
    property var selectedSinkId: null
    property var selectedSourceId: null
    signal sinkSelected(var id)
    signal sourceSelected(var id)

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
                        isPrimary: root.selectedSinkId !== null
                            ? modelData.id === root.selectedSinkId
                            : Boolean(Pipewire.defaultAudioSink) && modelData.id === Pipewire.defaultAudioSink.id
                        onSelected: {
                            Pipewire.preferredDefaultAudioSink = modelData
                            root.sinkSelected(modelData.id)
                        }
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
                        isPrimary: root.selectedSourceId !== null
                            ? modelData.id === root.selectedSourceId
                            : Boolean(Pipewire.defaultAudioSource) && modelData.id === Pipewire.defaultAudioSource.id
                        onSelected: {
                            Pipewire.preferredDefaultAudioSource = modelData
                            root.sourceSelected(modelData.id)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: hintseparator
            width: soundContent.contentWidth
            border.width: 2
            border.color: Config.fgcolor
            height: 2
        }

        // ---------------- hint row: right-click to set default, scroll to adjust volume ----------------
        Row {
            width: soundContent.contentWidth
            spacing: Config.scaled(16, root.uiScale)

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-right-symbolic")
                label: "Set as Default"
            }

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-middle-symbolic")
                label: "Quick change volume"
            }
        }
    }
}

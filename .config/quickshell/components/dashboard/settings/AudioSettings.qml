import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// Playback/recording device list + volume sliders, plus a per-application
// volume mixer strip along the bottom - one tab of SettingsScreen.qml's
// fullscreen tabbed panel (see there for the tab bar/coordinator).
// Embeddable Item instead of a standalone SettingsPanel popup: panelWidth/
// uiScale/active are plain properties fed in from the tab host instead of
// coming from a PanelWindow.
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false

    // Sized by whatever container SettingsScreen.qml gives this tab
    // (panelWidth/uiScale above just carry the same numbers through for
    // Config.scaled() calls) - not self-measured from content anymore,
    // so the lists below can stretch to fill it and the hint row stays
    // pinned to the true bottom instead of trailing right behind however
    // tall they happen to be.
    anchors.fill: parent

    // All hardware (non-stream) audio nodes, split by direction. Bound via
    // PwObjectTracker below so .audio.volume/.muted are valid to use - see
    // Quickshell's Pipewire docs, audio properties are otherwise invalid.
    readonly property var playbackNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var recordingNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink)

    // Per-application audio streams (one per app actually emitting sound,
    // e.g. a browser tab or a music player) for the Volume Mixer strip
    // below - isStream true means "likely a program, not hardware" per
    // Quickshell's own Pipewire docs, and isSink false is what
    // distinguishes a PLAYBACK stream (this node outputs audio onward to
    // a real sink) from a RECORDING stream (isSink true - this node
    // instead accepts audio from a real source, e.g. a voice-chat app's
    // mic capture) - same isStream/isSink pairing playbackNodes/
    // recordingNodes above already rely on for hardware, just the
    // opposite isSink value once isStream flips true, since what flows
    // "into" vs "out of" a stream node is the mirror image of a hardware
    // node's own direction.
    readonly property var playbackStreamNodes: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)

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
        objects: root.playbackNodes.concat(root.recordingNodes).concat(root.playbackStreamNodes)
    }

    Item {
        id: soundContent

        anchors {
            fill: parent
            margins: Config.scaled(16, root.uiScale)
        }

        readonly property real columnWidth: (width - columnsRow.spacing) / 2
        readonly property real cardHeight: Config.scaled(76, root.uiScale)
        // Fixed, not fillHeight - a horizontal row of cards only ever
        // needs enough height for one row regardless of how many apps are
        // playing audio, unlike the playback/recording lists above it
        // (which can genuinely have many devices stacked vertically and
        // benefit from soaking up whatever extra room is available).
        readonly property real mixerSectionHeight: Config.scaled(360, root.uiScale)
        readonly property real mixerCardWidth: Config.scaled(110, root.uiScale)

        // Fills everything above the mixer divider - both device lists
        // stretch to use whatever's left instead of capping at a fixed
        // height, so the mixer strip always sits at the true bottom of
        // the tab (just above the hint row) regardless of how many
        // playback/recording devices exist.
        RowLayout {
            id: columnsRow

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: mixerDivider.top
                bottomMargin: Config.scaled(10, root.uiScale)
            }
            spacing: Config.scaled(16, root.uiScale)

            ColumnLayout {
                Layout.preferredWidth: soundContent.columnWidth
                Layout.fillHeight: true
                spacing: Config.scaled(10, root.uiScale)

                Text {
                    text: "Playback"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Config.scaled(10, root.uiScale)
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: root.playbackNodes }

                    delegate: DeviceCard {
                        required property var modelData

                        width: ListView.view.width
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

            ColumnLayout {
                Layout.preferredWidth: soundContent.columnWidth
                Layout.fillHeight: true
                spacing: Config.scaled(10, root.uiScale)

                Text {
                    text: "Recording"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Config.scaled(10, root.uiScale)
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: root.recordingNodes }

                    delegate: DeviceCard {
                        required property var modelData

                        width: ListView.view.width
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

        // ---------------- divider above the mixer ----------------
        Rectangle {
            id: mixerDivider
            anchors {
                left: parent.left
                right: parent.right
                bottom: mixerSection.top
                bottomMargin: Config.scaled(10, root.uiScale)
            }
            height: Config.scaled(2, root.uiScale)
            color: Config.fgcolor
        }

        // ---------------- bottom: per-application volume mixer ----------------
        // One MixerCard per PipeWire playback stream (root.playbackStreamNodes),
        // left-to-right in a horizontal ListView - see MixerCard.qml's own
        // top comment for how its vertical slider is built out of the
        // ordinary horizontal DeviceSlider.
        ColumnLayout {
            id: mixerSection

            anchors {
                left: parent.left
                right: parent.right
                bottom: hintseparator.top
                bottomMargin: Config.scaled(10, root.uiScale)
            }
            height: soundContent.mixerSectionHeight
            spacing: Config.scaled(8, root.uiScale)

            Text {
                // Explicit AlignTop, not just "first child" - without a
                // sibling that always fills the remaining height (see the
                // wrapper Item below), this drifted down toward the
                // vertical middle of mixerSection whenever the empty-state
                // Text was its only other visible sibling (nothing left to
                // stack against, so the two short Texts alone don't span
                // mixerSection's own fixed height the way heading+ListView
                // do when there are cards to show).
                Layout.alignment: Qt.AlignTop
                text: "Volume Mixer"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
            }

            // Always present and always Layout.fillHeight (unlike the
            // ListView/empty-state Text it now wraps, which still toggle
            // visible on root.playbackStreamNodes.length) - this is what
            // keeps the heading pinned to the top and gives the empty-state
            // message a real, full-height parent to center itself in,
            // rather than the two of them being the only two ColumnLayout
            // children and getting centered as a short pair instead.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    visible: root.playbackStreamNodes.length === 0
                    text: "No applications playing audio right now."
                    color: Config.fgcolordark
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, root.uiScale)
                }

                ListView {
                    anchors.fill: parent
                    visible: root.playbackStreamNodes.length > 0
                    clip: true
                    orientation: ListView.Horizontal
                    spacing: Config.scaled(10, root.uiScale)
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: root.playbackStreamNodes }

                    delegate: MixerCard {
                        required property var modelData

                        width: soundContent.mixerCardWidth
                        height: ListView.view.height
                        uiScale: root.uiScale
                        stream: modelData
                    }
                }
            }
        }

        Rectangle {
            id: hintseparator
            anchors {
                left: parent.left
                right: parent.right
                bottom: hintRow.top
                bottomMargin: Config.scaled(10, root.uiScale)
            }
            border.width: 2
            border.color: Config.fgcolor
            height: 2
        }

        // ---------------- hint row: right-click to set default, scroll to adjust volume ----------------
        Row {
            id: hintRow
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
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

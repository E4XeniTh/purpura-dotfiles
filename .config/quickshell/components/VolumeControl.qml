import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Bar widget: mute icon + a horizontal "digital"/segmented volume bar
// (a row of lit/unlit blocks, like a level meter, instead of a
// continuous slider track) - click or drag anywhere on the segmented
// area to set volume directly, scroll anywhere on the widget to nudge
// it, click the icon to toggle mute. Same sink-selection precedence
// VolumeOsd.qml uses (Dashboard's explicitly-picked sink overrides
// Pipewire's own defaultAudioSink, which doesn't reliably emit a
// change once quickshell is already running) - fed in from Bar.qml the
// same way root.dashboard already is.
Rectangle {
    id: root

    property real uiScale: 1.0
    property var dashboard: null

    readonly property var activeSink: (root.dashboard && root.dashboard.audioSelectedSinkId !== null)
        ? (Pipewire.nodes.values.find(n => n.audio && !n.isStream && n.isSink && n.id === root.dashboard.audioSelectedSinkId) ?? Pipewire.defaultAudioSink)
        : Pipewire.defaultAudioSink

    // Bind the node so its volume/muted actually update reactively -
    // same requirement VolumeOsd.qml documents for this same service.
    PwObjectTracker {
        objects: [ root.activeSink ]
    }

    readonly property bool muted: (root.activeSink && root.activeSink.audio) ? root.activeSink.audio.muted : false
    readonly property real volume: (root.activeSink && root.activeSink.audio) ? root.activeSink.audio.volume : 0

    // Segment count/size deliberately fixed (not content-driven) so
    // segmentsBox below can be sized directly from these instead of
    // measuring the Row it contains - anchoring that Row to fill a box
    // whose own size came *from* the Row would be a binding cycle.
    readonly property int segmentCount: 18
    readonly property real segmentWidth: Config.scaled(4, root.uiScale)
    readonly property real segmentSpacing: Config.scaled(2, root.uiScale)
    readonly property real segmentAreaWidth: root.segmentCount * root.segmentWidth + (root.segmentCount - 1) * root.segmentSpacing
    readonly property real segmentAreaHeight: Config.scaled(16, root.uiScale)

    // Volume always shown as-is regardless of mute - only the icon
    // reflects muted, same as any standard volume control - so
    // unmuting doesn't look like the level was reset to zero.
    readonly property int litSegments: Math.round(Math.max(0, Math.min(1, root.volume)) * root.segmentCount)

    function setVolumeFromX(mx) {
        if (!root.activeSink || !root.activeSink.audio) return
        root.activeSink.audio.volume = Math.max(0, Math.min(1, mx / root.segmentAreaWidth))
    }

    color: "transparent"
    border.width: Config.scaled(2, root.uiScale)
    border.color: Config.fgcolor
    radius: 0

    implicitHeight: Config.scaled(34, root.uiScale)
    implicitWidth: content.implicitWidth + Config.scaled(20, root.uiScale)

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Config.scaled(8, root.uiScale)

        Item {
            width: Config.scaled(20, root.uiScale)
            height: Config.scaled(20, root.uiScale)
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
                id: volIcon
                anchors.fill: parent
                source: Quickshell.iconPath(root.muted || root.volume <= 0
                    ? "audio-volume-muted-symbolic"
                    : (root.volume < 0.5 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic"))
            }

            ColorOverlay {
                anchors.fill: volIcon
                source: volIcon
                color: iconArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
            }

            MouseArea {
                id: iconArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (root.activeSink && root.activeSink.audio) {
                        root.activeSink.audio.muted = !root.activeSink.audio.muted
                    }
                }
            }
        }

        Item {
            id: segmentsBox
            width: root.segmentAreaWidth
            height: root.segmentAreaHeight
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.fill: parent
                spacing: root.segmentSpacing

                Repeater {
                    model: root.segmentCount

                    Rectangle {
                        required property int index
                        width: root.segmentWidth
                        height: segmentsBox.height
                        radius: 0
                        color: index < root.litSegments ? dragArea.containsMouse ? Config.fgcolorlight : Config.fgcolor : Config.fgcolordark
                    }
                }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onPressed: (mouse) => root.setVolumeFromX(mouse.x)
                onPositionChanged: (mouse) => {
                    if (pressed) root.setVolumeFromX(mouse.x)
                }
            }
        }
    }

    // Scroll anywhere on the widget (icon or bar) as a volume shortcut,
    // same convention DeviceCard.qml uses - acceptedButtons: NoButton so
    // this MouseArea only ever intercepts wheel events, never clicks
    // meant for iconArea/dragArea underneath it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            if (!root.activeSink || !root.activeSink.audio) return
            const step = 0.02
            const delta = wheel.angleDelta.y > 0 ? step : -step
            root.activeSink.audio.volume = Math.max(0, Math.min(1, root.activeSink.audio.volume + delta))
        }
    }
}

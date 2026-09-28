import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One playing-audio application's volume/mute control, for AudioSettings.qml's
// "Volume Mixer" strip - same DashCard/DeviceSlider building blocks
// DeviceCard.qml uses for a hardware device, just turned 90 degrees: label on
// top, a vertical slider filling the middle, mute button pinned to the
// bottom. Cards sit left-to-right in a horizontal ListView (see
// AudioSettings.qml), one per PipeWire playback stream.
//
// The vertical slider is DeviceSlider itself, unmodified, wrapped in an Item
// with its width/height swapped and rotation: -90 applied - not a separate
// vertical slider component. Qt Quick transforms a rotated item's own mouse
// coordinates back into its local, unrotated space automatically, so
// DeviceSlider's existing horizontal drag math (mouse.x over its own width)
// keeps working exactly as it already does for every horizontal use of it
// elsewhere, it just LOOKS vertical here. -90 (not +90) specifically maps
// local +x (higher value, normally rightward) to screen-up - confirmed by
// the standard 2D rotation matrix, not confirmed live (no way to run
// Quickshell/Hyprland from here) - if the fill ever visually goes the wrong
// way (louder = lower fill), flip this to +90 first.
DashCard {
    id: root

    required property var stream
    property real uiScale: 1.0

    readonly property bool muted: root.stream.audio ? root.stream.audio.muted : false

    // application.name is the human-readable label PipeWire clients are
    // expected to set ("Firefox", "Spotify", ...) - properties is a plain
    // key/value object of the node's raw PipeWire properties, always
    // populated (unlike .audio, this doesn't need PwObjectTracker to be
    // valid). Falls back down the same nickname -> description -> name
    // chain DeviceCard.qml uses for a hardware device, for the rare stream
    // that doesn't set it.
    readonly property string label: {
        const appName = root.stream.properties ? root.stream.properties["application.name"] : ""
        if (appName && appName.length > 0) return appName
        if (root.stream.nickname && root.stream.nickname.length > 0) return root.stream.nickname
        if (root.stream.description && root.stream.description.length > 0) return root.stream.description
        return root.stream.name
    }

    border.color: Config.fgcolordark

    ColumnLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(8, root.uiScale)

        Text {
            Layout.fillWidth: true
            text: root.label
            color: Config.fgcolor
            font.bold: true
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(12, root.uiScale)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // Vertical slider - see this file's own top comment for the
        // rotated-DeviceSlider technique.
        Item {
            id: sliderBox
            Layout.fillWidth: true
            Layout.fillHeight: true

            DeviceSlider {
                anchors.centerIn: parent
                // Swapped: this item is rotated -90 below, so its own
                // pre-rotation width is the slider's on-screen LENGTH
                // (sliderBox's height) and its own height is the
                // on-screen THICKNESS (sliderBox's width) - DeviceSlider's
                // internal track/head are sized off uiScale regardless
                // (see its own trackHeight/headSize), so this thickness is
                // just the bounding box they center within, not a stretch.
                width: sliderBox.height
                height: sliderBox.width
                rotation: -90

                uiScale: root.uiScale
                muted: root.muted
                value: root.stream.audio ? root.stream.audio.volume : 0
                onMoved: (v) => {
                    if (root.stream.audio) {
                        root.stream.audio.volume = v
                    }
                }
            }
        }

        // Mute button, bottom of card - same IconImage/ColorOverlay/
        // MouseArea trio as DeviceCard.qml's own mute icon.
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Config.scaled(28, root.uiScale)
            Layout.preferredHeight: Config.scaled(28, root.uiScale)

            IconImage {
                id: muteIcon
                anchors.fill: parent
                source: Quickshell.iconPath(root.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic")
            }

            ColorOverlay {
                anchors.fill: muteIcon
                source: muteIcon
                color: muteMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
            }

            MouseArea {
                id: muteMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (root.stream.audio) {
                        root.stream.audio.muted = !root.stream.audio.muted
                    }
                }
            }
        }
    }

    // Scroll anywhere on the card as a shortcut for dragging the slider,
    // same convenience (and same "wheel isn't gated by acceptedButtons"
    // reasoning) as DeviceCard.qml's own card-level MouseArea - accepting
    // only a button this card has no click behavior for (RightButton) so
    // left clicks still fall through to the mute button/slider underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton

        onWheel: (wheel) => {
            if (root.stream.audio) {
                const step = 0.02
                const delta = wheel.angleDelta.y > 0 ? step : -step
                root.stream.audio.volume = Math.max(0, Math.min(1, root.stream.audio.volume + delta))
            }
        }
    }
}

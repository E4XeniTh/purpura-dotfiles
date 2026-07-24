import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One playback/recording device: name + mute button + volume slider inside
// a DashCard. Right-clicking anywhere on the card - including over the
// name, the mute icon, or the slider - selects it as the primary device.
// Left click is reserved for the mute icon/slider: this card's own
// MouseArea only accepts the right button, so left-button presses it
// doesn't accept fall through to whichever of those sits underneath.
DashCard {
    id: root

    required property var device
    property bool isPrimary: false
    property real uiScale: 1.0

    signal selected()

    readonly property bool muted: root.device.audio ? root.device.audio.muted : false

    border.color: isPrimary ? Config.fgcolor : Config.fgcolordark

    Column {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(8, root.uiScale)

        Text {
            width: parent.width
            // nickname is generally more human-readable than description,
            // which is generally more human-readable than the raw name -
            // fall back down that chain as each one turns out empty.
            text: root.device.nickname.length > 0 ? root.device.nickname
                : root.device.description.length > 0 ? root.device.description
                : root.device.name
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            elide: Text.ElideRight
        }

        RowLayout {
            width: parent.width
            spacing: Config.scaled(8, root.uiScale)

            // Fixed-size box, not a direct RowLayout child with its own
            // anchors - IconImage/ColorOverlay need anchors.fill, and a
            // layout fights children that also try to set their own
            // geometry, same reasoning as the hint icon in SoundSettings.
            Item {
                Layout.preferredWidth: Config.scaled(18, root.uiScale)
                Layout.preferredHeight: Config.scaled(18, root.uiScale)

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
                        if (root.device.audio) {
                            root.device.audio.muted = !root.device.audio.muted
                        }
                    }
                }
            }

            DeviceSlider {
                Layout.fillWidth: true
                uiScale: root.uiScale
                muted: root.muted
                value: root.device.audio ? root.device.audio.volume : 0
                onMoved: (v) => {
                    if (root.device.audio) {
                        root.device.audio.volume = v
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.selected()
    }
}

import QtQuick
import "../"
import "../../../Config.js" as Config

// One playback/recording device: name + volume slider inside a DashCard.
// Right-clicking anywhere on the card - including over the name or the
// slider - selects it as the primary device. Left click is reserved for
// the slider: this card's own MouseArea only accepts the right button, so
// left-button presses it doesn't accept fall through to the slider's own
// MouseArea underneath instead of being consumed here.
DashCard {
    id: root

    required property var device
    property bool isPrimary: false
    property real uiScale: 1.0

    signal selected()

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

        DeviceSlider {
            width: parent.width
            uiScale: root.uiScale
            value: root.device.audio ? root.device.audio.volume : 0
            onMoved: (v) => {
                if (root.device.audio) {
                    root.device.audio.volume = v
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

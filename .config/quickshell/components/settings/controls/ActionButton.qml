import QtQuick
import "../../../Config.js" as Config
import "../../common"

// A bordered text button, the Display tab's Apply/Set Default look: `lit`
// for one that's on, `danger` for one that forgets or removes something, and
// dark and unclickable while disabled (Item's own `enabled`).
DashCard {
    id: root

    property string text: ""
    property bool lit: false
    property bool danger: false

    signal clicked()

    implicitWidth: Math.max(Config.scaled(72, root.uiScale), Math.ceil(label.implicitWidth) + Config.scaled(24, root.uiScale))
    implicitHeight: Config.scaled(32, root.uiScale)
    color: buttonMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
    border.color: !root.enabled ? Config.fgcolordark
        : root.danger ? Config.fgcolorred
        : root.lit ? Config.fgcolorlight
        : Config.fgcolor

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.border.color
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(13, root.uiScale)
        font.bold: root.lit
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}

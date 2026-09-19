import QtQuick
import "../../Config.js" as Config

// "└ TEXT ┘" bracket-wrapped stat tag - SystemMonitor.qml's own small
// stat readouts (temp, percent, used/total) all use this, right-aligned
// under each section's usage bar. A separate reusable file rather than
// repeating the same three Text elements inline at every call site -
// this Quickshell's QML engine rejects the inline `component Name: Item
// {}` declaration syntax outright at boot (see PowerMenu.qml's own
// comment on its Repeater for the same limitation), so a real file is
// the only way to share this without duplicating it eight times over.
Row {
    id: root

    property real uiScale: 1.0
    property string text: ""

    spacing: Config.scaled(4, root.uiScale)

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "└"
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(10, root.uiScale)
        font.bold: true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(11, root.uiScale)
        font.bold: true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "┘"
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(10, root.uiScale)
        font.bold: true
    }
}

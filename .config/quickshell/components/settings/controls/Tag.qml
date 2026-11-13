import QtQuick
import "../../../Config.js" as Config

// A small "[Label]" beside a name in a settings list: [Primary] on the
// primary monitor, [Default] on the default audio devices.
Text {
    id: root

    property real uiScale: 1.0
    property string label: ""

    text: "[" + root.label + "]"
    color: Config.fgcolorlight
    font.family: Config.fontfamily
    font.pixelSize: Config.scaled(11, root.uiScale)
    font.bold: true
}

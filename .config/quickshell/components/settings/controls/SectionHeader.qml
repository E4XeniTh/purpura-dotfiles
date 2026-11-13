import QtQuick
import QtQuick.Layouts
import "../../../Config.js" as Config

// A settings section's title over a line, like the Power category's
// "Lockscreen" - or, with no text, just the line.
ColumnLayout {
    id: root

    property real uiScale: 1.0
    property string text: ""

    Layout.fillWidth: true
    Layout.topMargin: Config.scaled(14, root.uiScale)
    spacing: Config.scaled(4, root.uiScale)

    Text {
        visible: root.text.length > 0
        text: root.text
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(16, root.uiScale)
        font.bold: true
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Config.scaled(2, root.uiScale)
        color: Config.fgcolor
    }
}

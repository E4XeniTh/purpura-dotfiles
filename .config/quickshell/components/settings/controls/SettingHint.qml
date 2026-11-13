import QtQuick
import QtQuick.Layouts
import "../../../Config.js" as Config

// The small, dim line under a setting saying what it does - lined up with
// a checkbox's label, or (indented: false) with a slider or box above it.
Text {
    id: root

    property real uiScale: 1.0
    property bool indented: true

    Layout.fillWidth: true
    Layout.leftMargin: root.indented ? Config.scaled(28, root.uiScale) : 0
    wrapMode: Text.WordWrap
    color: Config.fgcolorhint
    font.family: Config.fontfamily
    font.pixelSize: Config.scaled(12, root.uiScale)
}

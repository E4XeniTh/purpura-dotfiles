import QtQuick
import "../../Config.js" as Config

// The bordered Config.fillcolor rectangle repeated throughout Dashboard.qml
// for every section/button. bgColor is overridable for the few buttons that
// react to hover.
Rectangle {
    property real uiScale: 1.0
    property color bgColor: Config.fillcolor

    color: bgColor
    border.width: Config.scaled(2, uiScale)
    border.color: Config.fgcolor
}

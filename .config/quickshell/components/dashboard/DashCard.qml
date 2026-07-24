import QtQuick
import "../../Config.js" as Config

Rectangle {
    property real uiScale: 1.0

    color: Config.fillcolor
    border.width: Config.scaled(2, uiScale)
    border.color: Config.fgcolor
}

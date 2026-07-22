import QtQuick
import "../Config.js" as Config

Text {
    id: root

    text: Qt.formatDateTime(new Date(), "hh:mm")

    font.pixelSize: 22
    color: Config.fgcolor

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.text = Qt.formatDateTime(new Date(), "hh:mm")
    }
}

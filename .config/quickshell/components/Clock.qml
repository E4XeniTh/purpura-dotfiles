import QtQuick

Text {
    id: root

    text: Qt.formatDateTime(new Date(), "hh:mm")

    font.pixelSize: 18
    color: Theme.fgcolor

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.text = Qt.formatDateTime(new Date(), "hh:mm")
    }
}

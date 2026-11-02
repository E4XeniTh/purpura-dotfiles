import QtQuick
import "../Config.js" as Config

Text {
    id: root

    // Fed in by Bar.qml (the per-screen Config.uiScale); Dashboard.qml
    // sets its own font.pixelSize instead.
    property real uiScale: 1.0

    text: Qt.formatDateTime(new Date(), "hh:mm")

    font.pixelSize: Config.scaled(22, root.uiScale)
    color: Config.fgcolor

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.text = Qt.formatDateTime(new Date(), "hh:mm")
    }
}

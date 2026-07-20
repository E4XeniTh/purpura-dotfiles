import QtQuick
import Quickshell
import Quickshell.Widgets
import "../"

// Large icon-only button used inside PowerMenu.qml.
Item {
    id: root

    signal activated()

    property string icon: ""

    width: 150
    height: 150

    Rectangle {
        anchors.fill: parent

        radius: 0
        color: mouseArea.containsMouse ? Theme.fgcolorhover : "transparent"

        border.width: 2
        border.color: Theme.fgcolor

        IconImage {
            anchors.centerIn: parent
            implicitSize: 88
            source: Quickshell.iconPath(root.icon)
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true

        onClicked: root.activated()
    }
}

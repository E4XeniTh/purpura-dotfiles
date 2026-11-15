import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config

// A waiting power action (PowerTimer.qml): its icon and the time left, in
// red. Small and bare under the dashboard (Dashboard.qml draws the box
// around it); large, framed and with an X that cancels it in the power menu.
Rectangle {
    id: root

    property var timer: null
    property real uiScale: 1.0
    // At 1920x1080, scaled by uiScale like everything else.
    property real iconSize: 44
    property real fontSize: 34
    property bool framed: false
    property bool closable: false

    readonly property real pad: Config.scaled(root.framed ? 18 : 14, root.uiScale)
    readonly property real closeSize: Config.scaled(20, root.uiScale)

    implicitWidth: countdown.implicitWidth + 2 * root.pad + (root.closable ? root.closeSize + root.pad / 2 : 0)
    implicitHeight: countdown.implicitHeight + 2 * root.pad

    color: root.framed ? Config.fillcolor : "transparent"
    border.width: root.framed ? Config.scaled(2, root.uiScale) : 0
    border.color: Config.fgcolorred

    Row {
        id: countdown
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.closable ? undefined : parent.horizontalCenter
        x: root.pad
        spacing: Config.scaled(12, root.uiScale)

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: icon.width
            height: icon.height

            IconImage {
                id: icon
                implicitSize: Config.scaled(root.iconSize, root.uiScale)
                source: root.timer && root.timer.action ? Quickshell.iconPath(root.timer.action.icon) : ""
            }

            ColorOverlay {
                anchors.fill: icon
                source: icon
                color: Config.fgcolorred
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.timer ? root.timer.remaining() : ""
            color: Config.fgcolorred
            font.family: Config.fontfamily
            font.bold: true
            font.pixelSize: Config.scaled(root.fontSize, root.uiScale)
        }
    }

    // Cancels the waiting action.
    Item {
        visible: root.closable
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Config.scaled(6, root.uiScale)
        width: root.closeSize
        height: root.closeSize

        Rectangle {
            anchors.fill: parent
            color: closeMouse.containsMouse ? Config.fgcolorhover : "transparent"
        }

        IconImage {
            id: closeIcon
            anchors.centerIn: parent
            implicitSize: root.closeSize * 0.8
            source: Quickshell.iconPath("window-close-symbolic")
        }

        ColorOverlay {
            anchors.fill: closeIcon
            source: closeIcon
            color: Config.fgcolorred
        }

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (root.timer) root.timer.cancel()
        }
    }
}

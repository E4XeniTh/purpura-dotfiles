import QtQuick
import "../../../Config.js" as Config

// Flat "box-headed" volume slider: a filled track with a small square handle
// riding at the current value, instead of a rounded Qt-style groove/thumb.
// Controlled component - value is driven externally, user input only emits
// moved() so the caller decides what (if anything) to do with it.
Item {
    id: root

    property real uiScale: 1.0
    property real value: 0.0 // 0.0 - 1.0

    signal moved(real newValue)

    implicitHeight: Config.scaled(18, uiScale)

    readonly property real trackHeight: Config.scaled(8, uiScale)
    readonly property real headSize: Config.scaled(14, uiScale)
    readonly property real clampedValue: Math.max(0, Math.min(1, value))

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackHeight
        color: Config.fgcolordark

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * root.clampedValue
            color: Config.fgcolor
        }
    }

    Rectangle {
        width: root.headSize
        height: root.headSize
        anchors.verticalCenter: track.verticalCenter
        x: Math.max(0, Math.min(root.width - width, root.width * root.clampedValue - width / 2))
        color: Config.fgcolor
        border.width: Config.scaled(1, root.uiScale)
        border.color: Config.fgcolordark
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        function updateFromMouse(mx) {
            root.moved(Math.max(0, Math.min(1, mx / root.width)))
        }

        onPressed: (mouse) => updateFromMouse(mouse.x)
        onPositionChanged: (mouse) => {
            if (pressed) {
                updateFromMouse(mouse.x)
            }
        }
    }
}

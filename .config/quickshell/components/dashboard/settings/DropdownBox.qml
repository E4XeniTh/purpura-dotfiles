import QtQuick
import "../../../Config.js" as Config

// Small inline dropdown in the settings' own look: a bordered box showing
// the current option and an arrow, opening a list of the options straight
// underneath it. The list overlays whatever is below rather than pushing
// the layout down. Controlled: picking an option only emits activated();
// the caller sets currentIndex.
Item {
    id: root

    property real uiScale: 1.0
    property var options: []
    property int currentIndex: 0
    property bool open: false

    signal activated(int index)

    readonly property real borderWidth: Config.scaled(2, root.uiScale)
    readonly property real rowHeight: Config.scaled(28, root.uiScale)

    implicitWidth: Config.scaled(100, root.uiScale)
    implicitHeight: root.rowHeight

    // Above later siblings while open, so the list isn't drawn under them.
    z: root.open ? 100 : 0

    onVisibleChanged: if (!visible) root.open = false

    Rectangle {
        anchors.fill: parent
        color: boxMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
        border.width: root.borderWidth
        border.color: root.open ? Config.fgcolorlight : Config.fgcolor

        Text {
            anchors {
                left: parent.left
                leftMargin: Config.scaled(8, root.uiScale)
                verticalCenter: parent.verticalCenter
            }
            text: root.options[root.currentIndex] || ""
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }

        // Drawn rather than a glyph, so it can't fall back to a missing
        // character in the shell font.
        Canvas {
            id: arrow
            anchors {
                right: parent.right
                rightMargin: Config.scaled(8, root.uiScale)
                verticalCenter: parent.verticalCenter
            }
            width: Config.scaled(10, root.uiScale)
            height: Config.scaled(6, root.uiScale)

            readonly property bool pointsUp: root.open
            readonly property color fill: root.open ? Config.fgcolorlight : Config.fgcolor
            onPointsUpChanged: requestPaint()
            onFillChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = arrow.fill
                ctx.beginPath()
                if (arrow.pointsUp) {
                    ctx.moveTo(0, height)
                    ctx.lineTo(width, height)
                    ctx.lineTo(width / 2, 0)
                } else {
                    ctx.moveTo(0, 0)
                    ctx.lineTo(width, 0)
                    ctx.lineTo(width / 2, height)
                }
                ctx.closePath()
                ctx.fill()
            }
        }

        MouseArea {
            id: boxMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.open = !root.open
        }
    }

    // Negative spacing overlaps neighbouring borders, so the box and its
    // options read as one column of single 2px lines.
    Column {
        visible: root.open
        y: root.height - root.borderWidth
        width: root.width
        spacing: -root.borderWidth

        Repeater {
            model: root.options

            Rectangle {
                id: option

                required property var modelData
                required property int index

                width: root.width
                height: root.rowHeight
                color: optionMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                border.width: root.borderWidth
                border.color: option.index === root.currentIndex ? Config.fgcolorlight : Config.fgcolor
                // The highlighted option's border sits over its neighbours'.
                z: option.index === root.currentIndex ? 1 : 0

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: Config.scaled(8, root.uiScale)
                        verticalCenter: parent.verticalCenter
                    }
                    text: option.modelData
                    color: option.border.color
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(13, root.uiScale)
                    font.bold: true
                }

                MouseArea {
                    id: optionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.open = false
                        root.activated(option.index)
                    }
                }
            }
        }
    }
}

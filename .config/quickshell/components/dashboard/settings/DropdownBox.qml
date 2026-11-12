import QtQuick
import "../../../Config.js" as Config

// Small inline dropdown in the settings' own look: a bordered box showing
// the current option and an arrow, opening a list of the options straight
// underneath it, or above it if it wouldn't fit below. If it fits neither way
// it's held against the window's bottom edge, so every option stays reachable.
// Controlled: picking an option only emits activated(); the caller sets
// currentIndex.
//
// The open list floats over the layout instead of taking up space in it, so
// opening moves nothing. It's parented to the window's root rather than to
// this item, because a z only counts among siblings: anything later in the
// layout would still sit on top of a list hanging off this item, and take
// its clicks. While it's open, a click anywhere else only closes it.
//
// maxVisibleRows caps how tall the open list gets: past that it scrolls,
// opening with the current option in view. 0 shows every option at once.
Item {
    id: root

    property real uiScale: 1.0
    property var options: []
    property int currentIndex: 0
    property bool open: false
    property int maxVisibleRows: 0

    signal activated(int index)

    readonly property real borderWidth: Config.scaled(2, root.uiScale)
    readonly property real rowHeight: Config.scaled(28, root.uiScale)

    // Options overlap the box and each other by one border, so the column
    // reads as single 2px lines.
    readonly property real listHeight: root.options.length * (root.rowHeight - root.borderWidth) + root.borderWidth
    readonly property real shownListHeight: (root.maxVisibleRows > 0 && root.options.length > root.maxVisibleRows)
        ? root.maxVisibleRows * (root.rowHeight - root.borderWidth) + root.borderWidth
        : root.listHeight

    implicitWidth: Config.scaled(100, root.uiScale)
    implicitHeight: root.rowHeight

    onVisibleChanged: if (!visible) root.open = false

    // Placed once on opening: nothing can move the box while the overlay is
    // taking every click.
    onOpenChanged: {
        if (!root.open) return
        const box = root.mapToItem(overlay, 0, 0)
        const below = box.y + root.rowHeight - root.borderWidth
        const above = box.y + root.borderWidth - root.shownListHeight
        list.x = box.x
        if (below + root.shownListHeight <= overlay.height) list.y = below
        else if (above >= 0) list.y = above
        else list.y = Math.max(0, overlay.height - root.shownListHeight)
        const centred = root.currentIndex * (root.rowHeight - root.borderWidth) - (root.shownListHeight - root.rowHeight) / 2
        list.contentY = Math.max(0, Math.min(root.listHeight - root.shownListHeight, centred))
    }

    Rectangle {
        anchors.fill: parent
        color: boxMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
        border.width: root.borderWidth
        border.color: root.open ? Config.fgcolorlight : Config.fgcolor

        Text {
            anchors {
                left: parent.left
                leftMargin: Config.scaled(8, root.uiScale)
                right: arrow.left
                rightMargin: Config.scaled(8, root.uiScale)
                verticalCenter: parent.verticalCenter
            }
            elide: Text.ElideRight
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

    Item {
        id: overlay

        parent: root.Window.contentItem
        anchors.fill: parent
        visible: root.open
        z: 1

        MouseArea {
            anchors.fill: parent
            // Also keeps what's underneath from lighting up as if clickable.
            hoverEnabled: true
            onClicked: root.open = false
        }

        // The options' own fill is see-through, which would let the controls
        // the list covers show through it.
        Rectangle {
            x: list.x
            y: list.y
            width: root.width
            height: root.shownListHeight
            color: "#000000"
        }

        Flickable {
            id: list

            width: root.width
            height: root.shownListHeight
            contentWidth: root.width
            contentHeight: root.listHeight
            clip: true
            interactive: root.listHeight > root.shownListHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
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
                                right: parent.right
                                rightMargin: Config.scaled(8, root.uiScale)
                                verticalCenter: parent.verticalCenter
                            }
                            elide: Text.ElideRight
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

        // Where a scrolling list is: a thin bar down its right edge, sized
        // and placed by how much of the list is in view.
        Rectangle {
            visible: list.interactive
            x: list.x + root.width - width - root.borderWidth
            y: list.y + list.contentY / root.listHeight * root.shownListHeight
            width: Config.scaled(3, root.uiScale)
            height: root.shownListHeight * root.shownListHeight / root.listHeight
            color: Config.fgcolorlight
        }
    }
}

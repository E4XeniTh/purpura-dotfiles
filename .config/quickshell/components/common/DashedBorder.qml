import QtQuick

// A dashed outline round its parent - a reserved workspace's box in the
// workspace widget and OSD - drawn as short bars along each edge, as a
// Rectangle's own border can't be dashed. Each edge starts and ends on a
// dash, with the gaps between spread evenly, so every corner is drawn.
Item {
    id: root

    property color color: "white"
    property real thickness: 2
    property real dash: 6
    property real gap: 4

    anchors.fill: parent

    // How many dashes go along an edge that long: one at each end at least.
    function count(length) {
        if (!(length > root.dash)) return 1
        return Math.max(2, Math.round((length - root.dash) / (root.dash + root.gap)) + 1)
    }

    // Where the i-th of n dashes along that edge starts.
    function start(i, n, length) {
        return n > 1 ? i * (length - root.dash) / (n - 1) : 0
    }

    readonly property int across: root.count(root.width)
    readonly property int down: root.count(root.height)

    // Top and bottom.
    Repeater {
        model: root.across * 2

        Rectangle {
            required property int index

            x: Math.round(root.start(index % root.across, root.across, root.width))
            y: index < root.across ? 0 : root.height - root.thickness
            width: Math.min(root.dash, root.width)
            height: root.thickness
            color: root.color
        }
    }

    // Left and right.
    Repeater {
        model: root.down * 2

        Rectangle {
            required property int index

            x: index < root.down ? 0 : root.width - root.thickness
            y: Math.round(root.start(index % root.down, root.down, root.height))
            width: root.thickness
            height: Math.min(root.dash, root.height)
            color: root.color
        }
    }
}

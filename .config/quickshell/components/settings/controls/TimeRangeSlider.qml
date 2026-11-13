import QtQuick
import "../../../Config.js" as Config

// Two-handle time-of-day slider for a nightly window (night light's
// schedule), styled like DeviceSlider. The axis runs noon to noon, so an
// evening-to-morning window is one unbroken stretch: the left handle is
// the start, the right one the end, and they can't cross. Pressing
// anywhere grabs the nearer handle.
//
// Controlled like DeviceSlider: a drag only moves the preview here;
// committed(start, end) fires on release, both as minutes since midnight.
Item {
    id: root

    property real uiScale: 1.0
    property int startMinutes: 21 * 60
    property int endMinutes: 7 * 60
    property int stepMinutes: 15

    signal committed(int startMinutes, int endMinutes)

    readonly property int axisOrigin: 12 * 60

    function toAxis(minutes) {
        return (minutes - root.axisOrigin + 1440) % 1440
    }

    function fromAxis(axis) {
        return (axis + root.axisOrigin) % 1440
    }

    function format(minutes) {
        const h = Math.floor(minutes / 60)
        const m = minutes % 60
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }

    readonly property int boundStartAxis: root.toAxis(root.startMinutes)
    // An end at or before the start on this axis (noon, or a window saved
    // across noon by hand) reads as the far end instead.
    readonly property int boundEndAxis: {
        const e = root.toAxis(root.endMinutes)
        return e <= root.boundStartAxis ? 1440 : e
    }

    property bool dragging: false
    property int grabbed: 0 // 1 = start handle, 2 = end handle
    property int dragStartAxis: 0
    property int dragEndAxis: 0

    readonly property int startAxis: root.dragging ? root.dragStartAxis : root.boundStartAxis
    readonly property int endAxis: root.dragging ? root.dragEndAxis : root.boundEndAxis

    // Live values while dragging, for a label next to the slider.
    readonly property int previewStart: root.fromAxis(root.startAxis)
    readonly property int previewEnd: root.fromAxis(root.endAxis)
    readonly property int previewLength: root.endAxis - root.startAxis

    readonly property real trackHeight: Config.scaled(12, uiScale)
    readonly property real headSize: Config.scaled(18, uiScale)
    readonly property real labelGap: Config.scaled(4, uiScale)
    readonly property real span: Math.max(1, root.width - root.headSize)

    implicitHeight: root.headSize + root.labelGap + tickLabelMetrics.height

    // Handles stay fully inside the slider: an axis position maps to a
    // handle CENTRE between headSize/2 and width - headSize/2.
    function px(axis) {
        return root.headSize / 2 + axis / 1440 * root.span
    }

    function axisAt(x) {
        const raw = (x - root.headSize / 2) / root.span * 1440
        const snapped = Math.round(raw / root.stepMinutes) * root.stepMinutes
        return Math.max(0, Math.min(1440, snapped))
    }

    Rectangle {
        id: track
        x: 0
        y: (root.headSize - root.trackHeight) / 2
        width: root.width
        height: root.trackHeight
        color: Config.fgcolordark
    }

    Rectangle {
        x: root.px(root.startAxis)
        y: track.y
        width: Math.max(0, root.px(root.endAxis) - x)
        height: track.height
        color: Config.fgcolor
    }

    Rectangle {
        width: root.headSize
        height: root.headSize
        x: root.px(root.startAxis) - width / 2
        color: root.dragging && root.grabbed === 1 ? Config.fgcolorlight : Config.fgcolor
        border.width: Config.scaled(1, root.uiScale)
        border.color: Config.fgcolordark
    }

    Rectangle {
        width: root.headSize
        height: root.headSize
        x: root.px(root.endAxis) - width / 2
        color: root.dragging && root.grabbed === 2 ? Config.fgcolorlight : Config.fgcolor
        border.width: Config.scaled(1, root.uiScale)
        border.color: Config.fgcolordark
    }

    TextMetrics {
        id: tickLabelMetrics
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(11, root.uiScale)
        text: "00:00"
    }

    // Every six hours along the axis, kept inside the slider's own width
    // at both ends.
    Repeater {
        model: [0, 360, 720, 1080, 1440]

        Text {
            required property int modelData
            y: root.headSize + root.labelGap
            x: Math.max(0, Math.min(root.width - width, root.px(modelData) - width / 2))
            text: root.format(root.fromAxis(modelData))
            color: Config.fgcolorhint
            font: tickLabelMetrics.font
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        function moveGrabbed(axis) {
            if (root.grabbed === 1) {
                root.dragStartAxis = Math.max(0, Math.min(axis, root.dragEndAxis - root.stepMinutes))
            } else {
                root.dragEndAxis = Math.min(1440, Math.max(axis, root.dragStartAxis + root.stepMinutes))
            }
        }

        onPressed: (mouse) => {
            const axis = root.axisAt(mouse.x)
            root.dragStartAxis = root.boundStartAxis
            root.dragEndAxis = root.boundEndAxis
            const toStart = Math.abs(axis - root.dragStartAxis)
            const toEnd = Math.abs(axis - root.dragEndAxis)
            // Handles sitting on top of each other: go by which side of
            // them the press landed.
            root.grabbed = toStart < toEnd ? 1 : toEnd < toStart ? 2 : (axis < root.dragStartAxis ? 1 : 2)
            root.dragging = true
            moveGrabbed(axis)
        }

        onPositionChanged: (mouse) => {
            if (pressed) moveGrabbed(root.axisAt(mouse.x))
        }

        // Commit before dropping the preview, so the bound values are
        // already the new ones when it stops overriding them - otherwise
        // the handles flick back to the old spot for a frame.
        onReleased: {
            root.committed(root.fromAxis(root.dragStartAxis), root.fromAxis(root.dragEndAxis))
            root.dragging = false
        }

        onCanceled: root.dragging = false
    }
}

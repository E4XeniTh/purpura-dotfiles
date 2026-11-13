import QtQuick
import "../../../Config.js" as Config

// Display settings' arrangement view: every monitor drawn to scale at its
// position in Hyprland's layout (logical pixels - a monitor's mode divided
// by its scale, turned on its side when rotated). Click one to pick it;
// drag it to move it; right-click to enable or disable it and double-click
// to make it primary, as on the monitor list's cards. A dragged monitor snaps to the other monitors' edges
// when it gets close, and the new position goes out through moved() once
// it's let go.
//
// Purely a view onto `monitors`, an array the caller builds:
//   { name, x, y, w, h,              logical layout rectangle
//     enabled, primary, selected,    how it's drawn
//     warn,                          overlaps another enabled monitor
//     lines: [string, ...] }         shown under the name
//
// One MouseArea over the whole view does the hit-testing rather than one per
// monitor: the caller rebuilds `monitors` whenever anything changes, mid-drag
// included, and the drag mustn't depend on any one delegate surviving that.
Item {
    id: root

    property real uiScale: 1.0
    property var monitors: []
    property bool interactive: true
    property string emptyText: ""

    signal picked(string name)
    signal moved(string name, real x, real y)
    signal toggleEnabled(string name)
    signal makePrimary(string name)

    clip: true

    // Delegates are keyed by name, so they survive `monitors` being rebuilt
    // and can animate from where they were.
    property var names: []
    function syncNames() {
        const next = root.monitors.map(m => m.name)
        if (next.join("\n") !== root.names.join("\n")) root.names = next
    }
    onMonitorsChanged: root.syncNames()
    Component.onCompleted: root.syncNames()

    readonly property var byName: {
        const map = {}
        for (const m of root.monitors) map[m.name] = m
        return map
    }

    // ---------------- fitting the layout into the view ----------------
    readonly property real padding: Config.scaled(18, root.uiScale)

    readonly property var bounds: {
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (const m of root.monitors) {
            if (!(m.w > 0 && m.h > 0)) continue
            minX = Math.min(minX, m.x)
            minY = Math.min(minY, m.y)
            maxX = Math.max(maxX, m.x + m.w)
            maxY = Math.max(maxY, m.y + m.h)
        }
        if (minX === Infinity) return { x: 0, y: 0, w: 1920, h: 1080 }
        return { x: minX, y: minY, w: Math.max(1, maxX - minX), h: Math.max(1, maxY - minY) }
    }

    readonly property real fitScale: Math.max(0.0001, Math.min((root.width - 2 * root.padding) / root.bounds.w,
                                                               (root.height - 2 * root.padding) / root.bounds.h))
    readonly property real fitX: root.padding + (root.width - 2 * root.padding - root.bounds.w * root.fitScale) / 2 - root.bounds.x * root.fitScale
    readonly property real fitY: root.padding + (root.height - 2 * root.padding - root.bounds.h * root.fitScale) / 2 - root.bounds.y * root.fitScale

    // Held still for the length of a drag: refitting while the dragged
    // monitor stretches the bounds would slide everything out from under the
    // cursor.
    property bool dragging: false
    property real frozenScale: 1
    property real frozenX: 0
    property real frozenY: 0
    readonly property real viewScale: root.dragging ? root.frozenScale : root.fitScale
    readonly property real viewX: root.dragging ? root.frozenX : root.fitX
    readonly property real viewY: root.dragging ? root.frozenY : root.fitY

    // No animating into place while the view is first being sized.
    property bool settled: false
    Timer {
        interval: 150
        running: !root.settled && root.width > 0 && root.height > 0 && root.monitors.length > 0
        onTriggered: root.settled = true
    }

    // ---------------- dragging ----------------
    property string dragName: ""
    property real dragX: 0
    property real dragY: 0
    property real grabX: 0
    property real grabY: 0
    property string hoverName: ""

    function layoutX(px) { return (px - root.viewX) / root.viewScale }
    function layoutY(py) { return (py - root.viewY) / root.viewScale }

    // Topmost first - the same order the delegates stack in (see z below).
    function monitorAt(px, py) {
        const x = root.layoutX(px)
        const y = root.layoutY(py)
        const ranked = root.monitors.slice().sort((a, b) => root.stackOrder(b) - root.stackOrder(a))
        for (const m of ranked) {
            if (x >= m.x && x < m.x + m.w && y >= m.y && y < m.y + m.h) return m
        }
        return null
    }

    function stackOrder(m) {
        return m.selected ? 2 : (m.enabled ? 1 : 0)
    }

    // Each axis on its own: the dragged monitor's edges line up with another
    // monitor's facing edges (side by side) or matching edges (aligned)
    // whenever one is within a few pixels on screen.
    function snapped(name, x, y, w, h) {
        const reach = Config.scaled(12, root.uiScale) / root.viewScale
        let bestX = x, distX = reach
        let bestY = y, distY = reach
        for (const o of root.monitors) {
            if (o.name === name || !(o.w > 0 && o.h > 0)) continue
            for (const cx of [o.x + o.w, o.x - w, o.x, o.x + o.w - w]) {
                if (Math.abs(cx - x) < distX) { distX = Math.abs(cx - x); bestX = cx }
            }
            for (const cy of [o.y + o.h, o.y - h, o.y, o.y + o.h - h]) {
                if (Math.abs(cy - y) < distY) { distY = Math.abs(cy - y); bestY = cy }
            }
        }
        return { x: bestX, y: bestY }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 2 * root.padding
        visible: root.monitors.length === 0 && root.emptyText.length > 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.emptyText
        color: Config.fgcolordark
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(13, root.uiScale)
    }

    Repeater {
        model: root.names

        Rectangle {
            id: box

            required property string modelData
            readonly property var info: root.byName[box.modelData] || ({ x: 0, y: 0, w: 0, h: 0, lines: [] })
            readonly property bool held: root.dragging && root.dragName === box.modelData
            readonly property bool hovered: root.hoverName === box.modelData && root.interactive

            readonly property real fontSize: Math.max(Config.scaled(9, root.uiScale),
                                                      Math.min(Config.scaled(14, root.uiScale), box.height / 7))
            // Every bit of text goes by the monitor's state alone, like the
            // monitor list's cards: primary, enabled, disabled. Picking one
            // only lights up its background.
            readonly property color textColor: box.info.primary ? Config.fgcolorlight
                : (box.info.enabled ? Config.fgcolor : Config.fgcolorred)

            x: root.viewX + (box.held ? root.dragX : box.info.x) * root.viewScale
            y: root.viewY + (box.held ? root.dragY : box.info.y) * root.viewScale
            width: Math.max(0, box.info.w * root.viewScale)
            height: Math.max(0, box.info.h * root.viewScale)
            visible: box.info.w > 0 && box.info.h > 0
            z: root.stackOrder(box.info)
            clip: true

            color: (box.info.selected || box.hovered || box.held) ? Config.fgcolorhover : Config.fillcolor
            // The same border colors as the monitor list's cards
            // (MonitorCard.qml): primary, enabled, disabled - overlapping
            // another one shows red too.
            border.width: Config.scaled(2, root.uiScale)
            border.color: box.info.warn ? Config.fgcolorred
                : (box.info.primary ? Config.fgcolorlight
                : (box.info.enabled ? Config.fgcolor : Config.fgcolorred))

            Behavior on x { enabled: root.settled && !root.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: root.settled && !root.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: root.settled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: root.settled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Column {
                anchors.centerIn: parent
                width: parent.width - 2 * Config.scaled(6, root.uiScale)
                spacing: Config.scaled(2, root.uiScale)

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: box.modelData
                    color: box.textColor
                    font.family: Config.fontfamily
                    font.pixelSize: box.fontSize * 1.15
                    font.bold: true
                }

                Text {
                    width: parent.width
                    visible: !!box.info.primary
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: "PRIMARY"
                    color: box.textColor
                    font.family: Config.fontfamily
                    font.pixelSize: box.fontSize * 0.85
                    font.bold: true
                }

                Repeater {
                    model: box.info.lines || []

                    Text {
                        required property string modelData
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData
                        color: box.textColor
                        font.family: Config.fontfamily
                        font.pixelSize: box.fontSize
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.dragging ? Qt.ClosedHandCursor : (root.hoverName.length > 0 ? Qt.OpenHandCursor : Qt.ArrowCursor)

        property real pressX: 0
        property real pressY: 0

        // The right button only enables and disables (onClicked below) - it
        // neither picks nor drags.
        onPressed: (mouse) => {
            if (mouse.button !== Qt.LeftButton) return
            const m = root.monitorAt(mouse.x, mouse.y)
            pressX = mouse.x
            pressY = mouse.y
            root.dragName = m ? m.name : ""
            if (!m) return
            root.grabX = root.layoutX(mouse.x) - m.x
            root.grabY = root.layoutY(mouse.y) - m.y
            root.dragX = m.x
            root.dragY = m.y
            root.picked(m.name)
        }

        onPositionChanged: (mouse) => {
            if (!pressed) {
                const m = root.monitorAt(mouse.x, mouse.y)
                root.hoverName = m ? m.name : ""
                return
            }
            if (!(pressedButtons & Qt.LeftButton)) return
            const m = root.byName[root.dragName]
            if (!m) return
            // A plain click shouldn't nudge anything.
            if (!root.dragging) {
                if (Math.hypot(mouse.x - pressX, mouse.y - pressY) < Config.scaled(4, root.uiScale)) return
                root.frozenScale = root.fitScale
                root.frozenX = root.fitX
                root.frozenY = root.fitY
                root.dragging = true
            }
            const spot = root.snapped(m.name, root.layoutX(mouse.x) - root.grabX, root.layoutY(mouse.y) - root.grabY, m.w, m.h)
            root.dragX = spot.x
            root.dragY = spot.y
        }

        // Hand the new position over before dropping the preview, so the
        // monitor is already there when it stops following the drag instead
        // of flicking back to the old spot for a frame.
        onReleased: (mouse) => {
            if (mouse.button !== Qt.LeftButton) return
            if (root.dragging && root.dragName.length > 0) {
                root.moved(root.dragName, Math.round(root.dragX), Math.round(root.dragY))
            }
            root.dragging = false
            root.dragName = ""
        }

        onCanceled: {
            root.dragging = false
            root.dragName = ""
        }

        onClicked: (mouse) => {
            if (mouse.button !== Qt.RightButton) return
            const m = root.monitorAt(mouse.x, mouse.y)
            if (m) root.toggleEnabled(m.name)
        }

        // Left: primary. A quick second right-click is just another
        // enable/disable, as if they'd been slower.
        onDoubleClicked: (mouse) => {
            const m = root.monitorAt(mouse.x, mouse.y)
            if (!m) return
            if (mouse.button === Qt.LeftButton) root.makePrimary(m.name)
            else root.toggleEnabled(m.name)
        }

        onExited: if (!pressed) root.hoverName = ""
    }
}

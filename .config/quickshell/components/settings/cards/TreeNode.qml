import QtQuick
import "../../../Config.js" as Config
import "../ConnectionsLogic.js" as Logic

// One box of Settings > Connections' tree: a name over a smaller line saying
// what state it's in, the border coloured by that state - or, for something
// with a battery, drawn as a ring of segments lit up to its charge, red when
// it's low. Name and border share the state's colour; selecting it only
// lights the background.
//
// Left click selects it, middle click renames it in place (Enter keeps the
// name, Escape drops it), right click asks for its action - the page decides
// what each of those does.
Rectangle {
    id: root

    property real uiScale: 1.0
    property string title: ""
    property string subtitle: ""
    property color stateColor: Config.fgcolor
    property bool selected: false
    // Its charge, 0 - 1, or below 0 for no battery.
    property real battery: -1
    property bool charging: false
    property bool renaming: false

    signal clicked()
    signal renameRequested()
    signal actionRequested()
    signal renamed(string name)
    signal renameCancelled()

    readonly property bool hasBattery: root.battery >= 0
    readonly property real line: Config.scaled(2, root.uiScale)

    color: nodeMouse.containsMouse || root.selected ? Config.fgcolorhover : Config.fillcolor
    border.width: root.hasBattery ? 0 : root.line
    border.color: root.stateColor

    Canvas {
        id: ring

        readonly property int count: 20
        readonly property int lit: Logic.litSegments(root.battery, ring.count)
        readonly property color litColor: Logic.batteryLow(root.battery, root.charging) ? Config.fgcolorred : root.stateColor
        readonly property color dimColor: Config.fgcolordark

        anchors.fill: parent
        visible: root.hasBattery

        onLitChanged: requestPaint()
        onLitColorChanged: requestPaint()
        onDimColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.hasBattery) return
            const half = root.line / 2
            const segments = Logic.ringSegments(width - root.line, height - root.line, ring.count, root.line * 2)
            ctx.translate(half, half)
            ctx.lineWidth = root.line
            for (let i = 0; i < segments.length; i++) {
                const points = segments[i]
                ctx.strokeStyle = i < ring.lit ? ring.litColor : ring.dimColor
                ctx.beginPath()
                ctx.moveTo(points[0][0], points[0][1])
                for (let j = 1; j < points.length; j++) ctx.lineTo(points[j][0], points[j][1])
                ctx.stroke()
            }
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Config.scaled(10, root.uiScale)
            rightMargin: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(2, root.uiScale)

        Text {
            id: titleText
            width: parent.width
            visible: !root.renaming
            text: root.title
            textFormat: Text.PlainText
            color: root.stateColor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
            elide: Text.ElideRight
        }

        TextInput {
            id: renameInput
            width: parent.width
            visible: root.renaming
            color: Config.fgcolorlight
            selectionColor: Config.fgcolor
            selectedTextColor: "#000000"
            font: titleText.font
            selectByMouse: true
            clip: true

            onAccepted: root.renamed(renameInput.text)
            Keys.onEscapePressed: root.renameCancelled()
            // Clicking away keeps what was typed.
            onActiveFocusChanged: {
                if (!activeFocus && root.renaming) root.renamed(renameInput.text)
            }

            // Where the name goes once renaming starts.
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.bottom
                }
                height: Config.scaled(1, root.uiScale)
                color: Config.fgcolorlight
            }
        }

        Text {
            width: parent.width
            visible: root.subtitle.length > 0
            text: root.subtitle
            textFormat: Text.PlainText
            color: Config.fgcolorhint
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(11, root.uiScale)
            elide: Text.ElideRight
        }
    }

    onRenamingChanged: {
        if (!root.renaming) return
        renameInput.text = root.title
        renameInput.selectAll()
        renameInput.forceActiveFocus()
    }

    // Off while renaming, so clicks reach the text being edited.
    MouseArea {
        id: nodeMouse
        anchors.fill: parent
        enabled: !root.renaming
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) root.clicked()
            else if (mouse.button === Qt.MiddleButton) root.renameRequested()
            else root.actionRequested()
        }
    }
}

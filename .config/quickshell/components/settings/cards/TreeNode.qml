import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../../Config.js" as Config
import "../../common"
import "../ConnectionsLogic.js" as Logic

// One row of Settings > Connections' directory tree: a box with an icon and
// the name on the left and what state it's in on the right, border, icon and
// name in that state's colour - selecting it only lights the background.
// Something with a battery also has a segmented bar and its percentage just
// past the box's right edge, red when it's low and not charging.
//
// Left click selects it, middle click renames it in place (Enter keeps the
// name, Escape drops it), right click asks for its action - the page decides
// what each of those does.
Rectangle {
    id: root

    property real uiScale: 1.0
    property string title: ""
    property string subtitle: ""
    // Icon names to try, best first - the first the icon theme has is shown.
    property var icons: []
    // Still waiting for its first answer: "loading" and a spinning circle
    // at the right, in place of the subtitle.
    property bool loading: false
    property color stateColor: Config.fgcolor
    property bool selected: false
    // Its charge, 0 - 1, or below 0 for no battery.
    property real battery: -1
    property bool charging: false
    property bool renaming: false
    // How far past the box the battery bar starts, and how long it is.
    property real batteryGap: Config.scaled(12, root.uiScale)
    // The battery box's width, from the end of the line to the pane's edge.
    property real batteryBoxWidth: Config.scaled(320, root.uiScale)

    signal clicked()
    signal renameRequested()
    signal actionRequested()
    signal renamed(string name)
    signal renameCancelled()

    // Looked up again only when the names change, not every time the tree
    // is rebuilt around this row.
    readonly property string iconKey: (root.icons || []).join("|")
    readonly property string iconSource: {
        if (root.iconKey.length === 0) return ""
        for (const name of root.iconKey.split("|")) {
            const path = Quickshell.iconPath(name, true)
            if (path.length > 0) return path
        }
        return ""
    }

    readonly property bool hasBattery: root.battery >= 0

    color: nodeMouse.containsMouse || root.selected ? Config.fgcolorhover : Config.fillcolor
    border.width: Config.scaled(2, root.uiScale)
    border.color: root.stateColor

    RowLayout {
        anchors {
            fill: parent
            leftMargin: Config.scaled(10, root.uiScale)
            rightMargin: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(10, root.uiScale)

        // Fixed-size box, not a direct RowLayout child with its own anchors -
        // IconImage/ColorOverlay need anchors.fill. Kept when no icon's found,
        // so names still line up.
        Item {
            Layout.preferredWidth: Config.scaled(18, root.uiScale)
            Layout.preferredHeight: Config.scaled(18, root.uiScale)

            IconImage {
                id: nodeIcon
                anchors.fill: parent
                visible: root.iconSource.length > 0
                source: root.iconSource
            }

            ColorOverlay {
                anchors.fill: nodeIcon
                visible: nodeIcon.visible
                source: nodeIcon
                color: root.stateColor
            }
        }

        Text {
            id: titleText
            Layout.fillWidth: true
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
            Layout.fillWidth: true
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
            Layout.maximumWidth: root.width * 0.45
            visible: root.subtitle.length > 0 && !root.loading
            text: root.subtitle
            textFormat: Text.PlainText
            color: Config.fgcolorhint
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(11, root.uiScale)
            elide: Text.ElideRight
        }

        Text {
            visible: root.loading
            text: "loading"
            color: Config.fgcolorhint
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(11, root.uiScale)
        }

        Item {
            id: spinner

            Layout.preferredWidth: Config.scaled(14, root.uiScale)
            Layout.preferredHeight: Config.scaled(14, root.uiScale)
            visible: root.loading

            // Three quarters of a ring, turning.
            Canvas {
                id: spinnerArc

                readonly property color tint: root.stateColor

                anchors.fill: parent
                onTintChanged: requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const thickness = Config.scaled(2, root.uiScale)
                    ctx.lineWidth = thickness
                    ctx.strokeStyle = spinnerArc.tint
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, width / 2 - thickness, 0, Math.PI * 1.5)
                    ctx.stroke()
                }

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: spinner.visible
                }
            }
        }
    }

    // The charge, beside the box: its own box, bordered like this row and
    // joined to it by a line - an icon, the segmented bar, the percentage,
    // all in the row's own colour, or all red when it's low. While charging
    // (plugged in) a plug instead of the battery icon, and the bar lights one
    // more segment every 0.33 s to the end, then drops back to the charge,
    // over and over - nothing changes colour for it.
    readonly property bool batteryLow: Logic.batteryLow(root.battery, root.charging)
    readonly property color batteryColor: root.batteryLow ? Config.fgcolorred : root.stateColor
    // Everything in the battery box but the bar: padding, icon, gaps and a
    // percentage wide enough for "100%".
    readonly property real batteryFixedWidth: Config.scaled(90, root.uiScale)

    Rectangle {
        x: root.width
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasBattery
        width: root.batteryGap
        height: Config.scaled(2, root.uiScale)
        color: root.batteryColor
    }

    Rectangle {
        id: batteryBox

        x: root.width + root.batteryGap
        visible: root.hasBattery
        width: root.batteryBoxWidth
        height: root.height
        color: Config.fillcolor
        border.width: Config.scaled(2, root.uiScale)
        border.color: root.batteryColor

        // The charging sweep: one more segment lit every 0.33 s up to the
        // last, then straight back to the charge and on again - every step
        // the same length, the restart included.
        readonly property int chargeSegments: Math.round(Math.max(0, Math.min(1, root.battery)) * 20)
        property int sweepSegments: batteryBox.chargeSegments
        readonly property bool sweeping: root.hasBattery && root.charging && batteryBox.visible
        readonly property real shown: batteryBox.sweeping ? batteryBox.sweepSegments / 20 : Math.max(0, root.battery)

        onSweepingChanged: batteryBox.sweepSegments = batteryBox.chargeSegments

        Timer {
            interval: 330
            repeat: true
            running: batteryBox.sweeping
            onTriggered: batteryBox.sweepSegments = batteryBox.sweepSegments >= 20
                ? batteryBox.chargeSegments
                : batteryBox.sweepSegments + 1
        }

        Row {
            anchors {
                left: parent.left
                leftMargin: Config.scaled(8, root.uiScale)
                verticalCenter: parent.verticalCenter
            }
            spacing: Config.scaled(8, root.uiScale)

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.scaled(18, root.uiScale)
                height: Config.scaled(18, root.uiScale)

                IconImage {
                    id: batteryIcon
                    anchors.fill: parent
                    visible: !root.charging
                    source: Quickshell.iconPath(Config.batteryIconName(Math.max(0, root.battery) * 100, false),
                        "battery-good-symbolic")
                }

                ColorOverlay {
                    anchors.fill: batteryIcon
                    visible: batteryIcon.visible
                    source: batteryIcon
                    color: root.batteryColor
                }

                // Plugged in: a plug on its cable, drawn here - the icon
                // theme (Breeze) has none.
                Canvas {
                    id: plugIcon

                    readonly property color tint: root.batteryColor

                    anchors.fill: parent
                    visible: root.charging
                    onTintChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const u = width / 16
                        ctx.fillStyle = plugIcon.tint
                        // Prongs.
                        ctx.fillRect(5 * u, 1 * u, 2 * u, 4 * u)
                        ctx.fillRect(9 * u, 1 * u, 2 * u, 4 * u)
                        // Body, narrowing to the cable.
                        ctx.beginPath()
                        ctx.moveTo(3 * u, 5 * u)
                        ctx.lineTo(13 * u, 5 * u)
                        ctx.lineTo(13 * u, 9 * u)
                        ctx.lineTo(10 * u, 12 * u)
                        ctx.lineTo(6 * u, 12 * u)
                        ctx.lineTo(3 * u, 9 * u)
                        ctx.closePath()
                        ctx.fill()
                        // Cable.
                        ctx.fillRect(7 * u, 12 * u, 2 * u, 4 * u)
                    }
                }
            }

            DigitalBar {
                anchors.verticalCenter: parent.verticalCenter
                uiScale: root.uiScale
                targetWidth: Math.max(0, root.batteryBoxWidth - root.batteryFixedWidth)
                // 5% each.
                segmentCount: 20
                barHeight: Config.scaled(14, root.uiScale)
                value: batteryBox.shown
                litColor: root.batteryColor
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.scaled(40, root.uiScale)
                text: Math.round(Math.max(0, root.battery) * 100) + "%"
                color: root.batteryColor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                font.bold: true
            }
        }
    }

    // Once it's over the box gives up the keyboard - hidden, it would keep
    // it, and Escape would never reach Settings to close it.
    onRenamingChanged: {
        if (!root.renaming) {
            renameInput.focus = false
            return
        }
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

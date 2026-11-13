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
    property color stateColor: Config.fgcolor
    property bool selected: false
    // Its charge, 0 - 1, or below 0 for no battery.
    property real battery: -1
    property bool charging: false
    property bool renaming: false
    // How far past the box the battery bar starts, and how long it is.
    property real batteryGap: Config.scaled(12, root.uiScale)
    property real batteryBarWidth: Config.scaled(110, root.uiScale)

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
    readonly property color batteryColor: Logic.batteryLow(root.battery, root.charging) ? Config.fgcolorred
        : root.charging ? Config.fgcolorlight
        : Config.fgcolor

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
            visible: root.subtitle.length > 0
            text: root.subtitle
            textFormat: Text.PlainText
            color: Config.fgcolorhint
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(11, root.uiScale)
            elide: Text.ElideRight
        }
    }

    // The charge, beside the box.
    Row {
        x: root.width + root.batteryGap
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasBattery
        spacing: Config.scaled(8, root.uiScale)

        DigitalBar {
            anchors.verticalCenter: parent.verticalCenter
            uiScale: root.uiScale
            targetWidth: root.batteryBarWidth
            // 5% each.
            segmentCount: 20
            barHeight: Config.scaled(14, root.uiScale)
            value: Math.max(0, root.battery)
            litColor: root.batteryColor
        }

        // A fixed width that fits "100%", so the page can leave exactly that
        // much room after the bar (NetworkSettings.qml's batteryPercentRoom).
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

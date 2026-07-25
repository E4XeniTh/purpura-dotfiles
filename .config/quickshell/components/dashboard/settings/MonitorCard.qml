import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../"
import "../../../Config.js" as Config

// One monitor in ScreenSettings' left list. Left-click selects it (shows
// its config in the right-hand form); right-click toggles a pending
// activate/deactivate flag, reflected only in border color - nothing is
// actually enabled/disabled until Apply is pressed. Double-click marks it
// primary (fgcolorlight border, overriding the enabled/disabled color -
// see ScreenSettings.qml for what "primary" actually does).
DashCard {
    id: root

    required property string name
    required property bool pendingEnabled
    required property bool selected
    required property bool isPrimary
    property real uiScale: 1.0

    signal clicked()
    signal toggleEnabled()
    signal makePrimary()

    color: root.selected ? Config.fgcolorhover : Config.fillcolor
    border.color: root.isPrimary ? Config.fgcolorlight : (root.pendingEnabled ? Config.fgcolor : "red")

    RowLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(10, root.uiScale)

        Item {
            Layout.preferredWidth: Config.scaled(24, root.uiScale)
            Layout.preferredHeight: Config.scaled(24, root.uiScale)

            IconImage {
                id: monitorIcon
                anchors.fill: parent
                source: Quickshell.iconPath("video-display-symbolic")
            }

            ColorOverlay {
                anchors.fill: monitorIcon
                source: monitorIcon
                color: root.border.color
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.name
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(14, root.uiScale)
            font.bold: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                root.clicked()
            } else {
                root.toggleEnabled()
            }
        }
        // Qt still fires a plain clicked() for the first press/release
        // of a double-click before this - harmless here, it just also
        // selects the card, which makes sense alongside marking it
        // primary anyway.
        onDoubleClicked: root.makePrimary()
    }
}

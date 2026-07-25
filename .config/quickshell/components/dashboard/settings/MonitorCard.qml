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
//
// Below the icon/label row is a thin DDC/CI brightness slider (via
// ddcutil) - also staged, not live: dragging it only stores a pending
// value (brightnessEdited), actually sent to the monitor on Apply, same
// as everything else here.
DashCard {
    id: root

    required property string name
    required property bool pendingEnabled
    required property bool selected
    required property bool isPrimary
    required property real brightness // 0-100
    property real uiScale: 1.0

    signal clicked()
    signal toggleEnabled()
    signal makePrimary()
    signal brightnessEdited(real value)

    color: root.selected ? Config.fgcolorhover : Config.fillcolor
    border.color: root.isPrimary ? Config.fgcolorlight : (root.pendingEnabled ? Config.fgcolor : "red")

    ColumnLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(6, root.uiScale)

        RowLayout {
            id: headerRow

            Layout.fillWidth: true
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

            // Scoped to just this row (not the whole card) so it
            // doesn't steal drag input from the brightness slider below.
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
                // Qt still fires a plain clicked() for the first
                // press/release of a double-click before this -
                // harmless here, it just also selects the card, which
                // makes sense alongside marking it primary anyway.
                onDoubleClicked: root.makePrimary()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Config.scaled(1, root.uiScale)
            color: root.border.color
        }

        DeviceSlider {
            Layout.fillWidth: true
            // Thinner/smaller than the volume OSD's own slider - this
            // is a secondary control buried in a small list card.
            uiScale: root.uiScale * 0.6
            value: root.brightness / 100
            onMoved: (newValue) => root.brightnessEdited(Math.round(newValue * 100))
        }
    }
}

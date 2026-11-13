import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config

// Which input language is on, for a moment after the input language
// shortcut (META + -) - the same box, in the same place, as the volume and
// brightness OSDs. InputDevices.qml calls show().
Scope {
    id: root

    // Settings > General's global UI Scale (UiScale.qml), from shell.qml.
    property real shellScale: 1.0

    property string language: ""
    property bool shouldShowOsd: false

    function show(name) {
        root.language = name
        root.shouldShowOsd = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer

        interval: 1500
        onTriggered: root.shouldShowOsd = false
    }

    LazyLoader {
        active: root.shouldShowOsd

        PanelWindow {
            id: osdWindow

            readonly property real uiScale: Config.uiScale(osdWindow.screen, root.shellScale)

            anchors.bottom: true
            margins.bottom: screen.height / 8
            // Purely informational: clicks go straight through.
            mask: Region {}
            exclusiveZone: 0

            implicitWidth: Config.scaled(500, osdWindow.uiScale)
            implicitHeight: Config.scaled(84, osdWindow.uiScale)
            color: "transparent"

            Rectangle {
                anchors.fill: parent

                color: Config.fillcolor
                radius: 0
                border.width: Config.scaled(2, osdWindow.uiScale)
                border.color: Config.fgcolor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Config.scaled(20, osdWindow.uiScale)
                    spacing: Config.scaled(16, osdWindow.uiScale)

                    Item {
                        Layout.preferredWidth: Config.scaled(48, osdWindow.uiScale)
                        Layout.preferredHeight: Config.scaled(48, osdWindow.uiScale)

                        IconImage {
                            id: keyboardIcon
                            anchors.fill: parent
                            source: Quickshell.iconPath("input-keyboard-symbolic", "preferences-desktop-keyboard")
                        }

                        ColorOverlay {
                            anchors.fill: keyboardIcon
                            source: keyboardIcon
                            color: Config.fgcolor
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.language
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(24, osdWindow.uiScale)
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}

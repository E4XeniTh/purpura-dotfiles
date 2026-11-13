import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config

// Which input language is on, for a moment after the input language
// shortcut (META + -) - the same box as the volume and brightness OSDs,
// stacked with them by OsdHost.qml. InputDevices.qml calls show().
Scope {
    id: root

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

    // Its box - OsdHost.qml shows it, with the other OSDs, where Settings >
    // General > Shell > OSD says, and sets uiScale.
    property Component box: Rectangle {
        id: languageBox

        property real uiScale: 1.0
        // The border's own: the screen and shell scale without the OSD
        // size, so the size setting never changes it.
        property real borderScale: 1.0

        width: Config.scaled(500, languageBox.uiScale)
        height: Config.scaled(84, languageBox.uiScale)
        color: Config.fillcolor
        radius: 0
        border.width: Config.scaled(2, languageBox.borderScale)
        border.color: Config.fgcolor

        RowLayout {
            anchors.fill: parent
            anchors.margins: Config.scaled(20, languageBox.uiScale)
            spacing: Config.scaled(16, languageBox.uiScale)

            Item {
                Layout.preferredWidth: Config.scaled(48, languageBox.uiScale)
                Layout.preferredHeight: Config.scaled(48, languageBox.uiScale)

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

            // Before the shortcut's first use (a settings preview), just
            // what it's for.
            Text {
                Layout.fillWidth: true
                text: root.language.length > 0 ? root.language : "Input language"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(24, languageBox.uiScale)
                font.bold: true
                elide: Text.ElideRight
            }
        }
    }
}

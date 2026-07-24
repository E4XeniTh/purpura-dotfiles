import QtQuick
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config

// Blur-overlay input prompt - PIN/password entry for things like bluetooth
// pairing or wifi passwords. Meant to be dropped in as the last child of
// whatever widget it should cover (a device/network card, etc.): it fills
// that widget, blurs it out, then a vertical line grows at the center and
// opens left/right into a compact input box, "double doors" style. Note:
// the hosting window needs SettingsPanel.wantsKeyboardFocus: true (or
// equivalent WlrLayershell.keyboardFocus) for the input box to actually
// receive keystrokes - see SettingsPanel.qml.
Item {
    id: root

    anchors.fill: parent

    property real uiScale: 1.0
    property string promptText: "INPUT PASSWORD"
    // Hides typed characters - on for passwords/PINs, off for anything
    // that should be readable while typing (e.g. a wifi SSID, if this
    // component ever gets reused for that instead).
    property bool passwordMode: true

    // What to blur - defaults to this item's own parent, since that's the
    // normal way this gets used: nested inside the widget it should cover.
    property Item blurTarget: root.parent

    signal confirmed(string text)
    signal cancelled()

    property bool open: false
    // Stays true through the close animation (line shrinking back down),
    // same reasoning as SettingsPanel.qml's reallyVisible.
    property bool reallyVisible: false
    visible: root.reallyVisible

    function show(prompt) {
        if (prompt !== undefined) {
            root.promptText = prompt
        }
        field.text = ""
        root.open = true
    }

    function hide() {
        root.open = false
    }

    onOpenChanged: {
        if (open) {
            closeTimer.stop()
            reallyVisible = true

            dialogLine.width = Config.scaled(2, root.uiScale)
            dialogLine.height = 0
            dialogLine.state = "line"
            growTimer.restart()
        } else if (reallyVisible) {
            growTimer.stop()
            dialogLine.state = "line"
            closeTimer.restart()
        }
    }

    // Live blur of blurTarget - FastBlur can't take blurTarget directly as
    // its source without also blurring this dialog's own content drawn on
    // top of it, so it goes through an intermediate texture instead.
    ShaderEffectSource {
        id: blurSource
        anchors.fill: parent
        sourceItem: root.blurTarget
        live: true
        visible: false
    }

    FastBlur {
        anchors.fill: parent
        source: blurSource
        radius: Config.scaled(48, root.uiScale)
        visible: root.reallyVisible
    }

    Rectangle {
        id: dialogLine

        anchors.centerIn: parent
        width: 0
        height: 0
        color: Config.fillcolor
        border.width: Config.scaled(2, root.uiScale)
        border.color: Config.fgcolor

        states: [

            State {
                name: "line"

                PropertyChanges {
                    target: dialogLine

                    width: Config.scaled(2, root.uiScale)
                    height: parent.height * 0.7
                }
            },

            State {
                name: "open"

                PropertyChanges {
                    target: dialogLine

                    width: Math.min(parent.width * 0.8, Config.scaled(240, root.uiScale))
                    height: parent.height * 0.7
                }
            }

        ]

        transitions: [

            Transition {

                NumberAnimation {

                    properties: "width,height"

                    duration: 300

                    easing.type: Easing.OutCubic

                }

            }

        ]

        Item {
            anchors.fill: parent
            clip: true

            Column {
                anchors.centerIn: parent
                width: parent.width - Config.scaled(20, root.uiScale)
                spacing: Config.scaled(10, root.uiScale)

                Text {
                    width: parent.width
                    text: root.promptText
                    horizontalAlignment: Text.AlignHCenter
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(13, root.uiScale)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: Config.scaled(28, root.uiScale)
                    color: Config.fillcolor
                    border.width: Config.scaled(1, root.uiScale)
                    border.color: Config.fgcolordark

                    TextInput {
                        id: field

                        anchors {
                            fill: parent
                            margins: Config.scaled(6, root.uiScale)
                        }

                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        echoMode: root.passwordMode ? TextInput.Password : TextInput.Normal
                        clip: true

                        focus: dialogLine.state === "open"

                        Keys.onEscapePressed: {
                            root.cancelled()
                            root.hide()
                        }

                        onAccepted: {
                            root.confirmed(text)
                            root.hide()
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: growTimer

        // Must match the transition's duration above, so phase 1 (height,
        // the vertical line growing) fully finishes before phase 2 (width,
        // the doors opening) starts.
        interval: 300
        repeat: false

        onTriggered: {
            dialogLine.state = "open"
        }
    }

    Timer {
        id: closeTimer

        // Matches the line-collapse transition's duration.
        interval: 300
        repeat: false

        onTriggered: {
            root.reallyVisible = false
        }
    }
}

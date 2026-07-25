import QtQuick
import "../"
import "../../../Config.js" as Config

// A small labeled numeric input box, DashCard-style border, used for the
// resolution/position/scale fields in ScreenSettings.qml. Controlled
// component - value is driven externally (so a monitor switch can
// repopulate it), user edits are only committed via editingFinished,
// not on every keystroke.
Column {
    id: root

    property string label: ""
    property string value: ""
    property real uiScale: 1.0

    signal edited(string text)

    spacing: Config.scaled(4, root.uiScale)

    Text {
        text: root.label
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(11, root.uiScale)
    }

    Rectangle {
        width: parent.width
        height: Config.scaled(28, root.uiScale)
        color: Config.fillcolor
        border.width: Config.scaled(2, root.uiScale)
        border.color: input.activeFocus ? Config.fgcolorlight : Config.fgcolor

        TextInput {
            id: input
            anchors {
                fill: parent
                margins: Config.scaled(6, root.uiScale)
            }
            verticalAlignment: TextInput.AlignVCenter
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            selectByMouse: true
            clip: true

            // Declarative binding for the initial value only - QML
            // permanently breaks a property's binding the moment
            // something assigns to it imperatively, which is exactly
            // what typing into a TextInput does. Re-established
            // explicitly below whenever root.value changes externally
            // (a different monitor gets selected), but not while the
            // user is actively typing in this field.
            text: root.value

            Connections {
                target: root
                function onValueChanged() {
                    if (!input.activeFocus) {
                        input.text = root.value
                    }
                }
            }

            onEditingFinished: root.edited(text)
        }
    }
}

import QtQuick
import "../../../Config.js" as Config

// A whole-number box, as ShellSettings.qml draws them. It hands over what
// was typed on Enter or on leaving the box, not on each keystroke, so a
// number being typed can't get snapped to a minimum halfway through - then
// shows `value` again, which is whatever the owner made of it (clamped, or
// the old value if the box was left empty). Dark and locked while `usable`
// is false.
Rectangle {
    id: root

    property real uiScale: 1.0
    property int value: 0
    property bool usable: true

    signal committed(int value)

    implicitWidth: Config.scaled(70, root.uiScale)
    implicitHeight: Config.scaled(28, root.uiScale)

    color: Config.fillcolor
    border.width: Config.scaled(2, root.uiScale)
    border.color: !root.usable ? Config.fgcolordark
        : input.activeFocus ? Config.fgcolorlight : Config.fgcolor

    TextInput {
        id: input

        anchors {
            fill: parent
            margins: Config.scaled(6, root.uiScale)
        }

        enabled: root.usable
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        color: root.usable ? Config.fgcolor : Config.fgcolordark
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(13, root.uiScale)
        selectByMouse: true
        clip: true
        validator: RegularExpressionValidator { regularExpression: /^[0-9]*$/ }

        text: String(root.value)

        onEditingFinished: {
            const typed = parseInt(input.text, 10)
            if (!isNaN(typed)) root.committed(typed)
            input.text = String(root.value)
        }
        onAccepted: input.focus = false
    }

    // The value can also change from elsewhere (another option moving its
    // minimum, say) - shown unless it's being typed over right now.
    Connections {
        target: root

        function onValueChanged() {
            if (!input.activeFocus) input.text = String(root.value)
        }
    }
}

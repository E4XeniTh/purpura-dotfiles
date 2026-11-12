import QtQuick
import "../"
import "../../../Config.js" as Config

// A small labeled numeric input box, DashCard-style border, used for the
// position fields in ScreenSettings.qml. Controlled component - value is
// driven externally (so a monitor switch can repopulate it). showLabel:
// false drops the caption above the box, for a field labelled beside it.
Item {
    id: root

    property string label: ""
    property string value: ""
    property real uiScale: 1.0
    property bool showLabel: true

    signal edited(string text)

    // A fixed natural width, deliberately NOT derived from the field's own
    // current width. This used to be a plain Column whose children were
    // bound to the column's width, so its implicit width was simply
    // whatever width it had last been given - and inside ScreenSettings'
    // fillWidth RowLayouts that fed straight back into the next layout
    // pass. After a re-layout (an Apply resizing the screen, a UI Scale
    // change) a row could settle with one field holding all of its space
    // and the others squeezed to nothing - seen live as X Pos/Y Pos
    // vanishing while Scale stretched across the whole row. Every field
    // now asks for the same width, so a row always shares out evenly.
    implicitWidth: Config.scaled(80, root.uiScale)
    implicitHeight: fieldColumn.implicitHeight

    Column {
        id: fieldColumn

        width: root.width
        spacing: Config.scaled(4, root.uiScale)

        Text {
            width: parent.width
            visible: root.showLabel
            text: root.label
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(14, root.uiScale)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            width: parent.width
            height: Config.scaled(32, root.uiScale)
            color: Config.fillcolor
            border.width: Config.scaled(2, root.uiScale)
            border.color: input.activeFocus ? Config.fgcolorlight : Config.fgcolor

            TextInput {
                id: input
                anchors {
                    fill: parent
                    margins: Config.scaled(8, root.uiScale)
                }
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(16, root.uiScale)
                selectByMouse: true
                clip: true

                // Digits and a single decimal point only.
                validator: RegularExpressionValidator { regularExpression: /^-?[0-9]*\.?[0-9]*$/ }

                // Guards the programmatic resync below from being mistaken
                // for a user edit by onTextChanged (which would otherwise
                // re-stage the exact same value as a no-op "edit" every
                // time a different monitor is selected or the post-apply
                // refresh lands).
                property bool syncing: false

                // Declarative binding for the initial value only - QML
                // permanently breaks a property's binding the moment
                // something assigns to it imperatively, which is exactly
                // what typing into a TextInput does. Re-established
                // explicitly below whenever root.value changes externally.
                //
                // Unconditional - ScreenSettings' displayFor (what feeds
                // root.value) is a frozen snapshot that only ever changes
                // at deliberate moments (selecting a different monitor,
                // reopening the panel), never as a side effect of typing
                // into this field itself, so there's no live feedback loop
                // to guard against here. An earlier version gated this on
                // `!input.activeFocus`, on the theory that a monitor switch
                // always steals focus first (see ScreenSettings' explicit
                // forceActiveFocus() calls) - but that made a correct
                // resync depend on focus having actually already been
                // stolen by the time this fires, and confirmed live, it
                // could still lose that race and leave the field showing a
                // stale value typed for the *previous* monitor.
                text: root.value

                Connections {
                    target: root
                    function onValueChanged() {
                        input.syncing = true
                        input.text = root.value
                        input.syncing = false
                    }
                }

                // Committed live, on every keystroke - waiting for
                // editingFinished meant a field you never explicitly
                // defocused (Tab, click elsewhere, Enter) before hitting
                // Apply was left out of ScreenSettings' `pending` entirely,
                // so Apply would silently apply everything else while that
                // one field's edit was dropped and reverted to its old
                // value once the post-apply refresh landed.
                onTextChanged: {
                    if (!input.syncing) {
                        root.edited(input.text)
                    }
                }

                // Enter/Return gives up focus (the edit itself already
                // committed live above) instead of leaving the field
                // focused with a blinking cursor.
                onAccepted: input.focus = false
            }
        }
    }
}

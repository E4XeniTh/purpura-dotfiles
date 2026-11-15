import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config

// The power menu's "run this later" box, for the action whose button was
// right-clicked:
//
//   [ action ]  [ number ]  [ Hours/Minutes ]
//   [        ]
//   [        ]                [Enter] confirm
//
// The number box has the keyboard from the start; Enter sends `confirmed`
// (the hint at the bottom says so), Escape `dismissed` (as does a click
// outside, which PowerMenu.qml catches).
Rectangle {
    id: root

    property var action: null
    property real uiScale: 1.0

    signal confirmed(int amount, bool hours)
    signal dismissed()

    readonly property real pad: Config.scaled(14, root.uiScale)
    readonly property real gap: Config.scaled(10, root.uiScale)
    // The action's icon, as tall as the three rows beside it.
    readonly property real actionSize: Config.scaled(110, root.uiScale)
    readonly property real rowHeight: (root.actionSize - 2 * root.gap) / 3
    readonly property real fieldWidth: Config.scaled(120, root.uiScale)

    implicitWidth: grid.implicitWidth + 2 * root.pad
    implicitHeight: grid.implicitHeight + 2 * root.pad

    color: Qt.rgba(0, 0, 0, 1)
    border.width: Config.scaled(2, root.uiScale)
    border.color: Config.fgcolor

    // Clicks inside stay inside (the outside closes it).
    MouseArea {
        anchors.fill: parent
        onClicked: amountInput.forceActiveFocus()
    }

    function confirm() {
        const amount = parseInt(amountInput.text, 10)
        if (amount > 0) root.confirmed(amount, unitButton.hours)
    }

    function focusInput() {
        amountInput.forceActiveFocus()
    }

    Component.onCompleted: amountInput.forceActiveFocus()

    Row {
        id: grid
        anchors.centerIn: parent
        spacing: root.gap

        // Column 1, all three rows: the action.
        Item {
            width: root.actionSize
            height: root.actionSize

            IconImage {
                id: actionIcon
                anchors.centerIn: parent
                implicitSize: root.actionSize
                source: root.action ? Quickshell.iconPath(root.action.icon) : ""
            }

            ColorOverlay {
                anchors.fill: actionIcon
                source: actionIcon
                color: Config.fgcolor
            }
        }

        // Columns 2 and 3.
        Column {
            spacing: root.gap

            // Row 1: the number, and its unit.
            Row {
                spacing: root.gap

                Rectangle {
                    width: root.fieldWidth
                    height: root.rowHeight
                    color: Config.fillcolor
                    border.width: Config.scaled(2, root.uiScale)
                    border.color: amountInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

                    TextInput {
                        id: amountInput
                        anchors.fill: parent
                        anchors.margins: Config.scaled(6, root.uiScale)
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        color: Config.fgcolorlight
                        selectionColor: Config.fgcolordark
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        validator: IntValidator { bottom: 1; top: 999 }
                        maximumLength: 3

                        // Taken here whatever's typed, so they never reach the
                        // power menu (whose Enter would run the action now).
                        Keys.onReturnPressed: event => { event.accepted = true; root.confirm() }
                        Keys.onEnterPressed: event => { event.accepted = true; root.confirm() }
                        Keys.onEscapePressed: event => { event.accepted = true; root.dismissed() }
                    }
                }

                Rectangle {
                    id: unitButton
                    property bool hours: true
                    width: root.fieldWidth
                    height: root.rowHeight
                    color: unitMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.width: Config.scaled(2, root.uiScale)
                    border.color: Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: unitButton.hours ? "Hours" : "Minutes"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                    }

                    MouseArea {
                        id: unitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            unitButton.hours = !unitButton.hours
                            amountInput.forceActiveFocus()
                        }
                    }
                }
            }

            // Row 2: empty.
            Item {
                width: 1
                height: root.rowHeight
            }

            // Row 3: "[Enter] confirm", at the right of column 3 - the Enter
            // key drawn as a key cap with the return symbol in it, sized like
            // the settings panels' hint icons (HintItem).
            Item {
                width: 2 * root.fieldWidth + root.gap
                height: root.rowHeight

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Config.scaled(6, root.uiScale)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.scaled(22, root.uiScale)
                        height: Config.scaled(18, root.uiScale)
                        color: "transparent"
                        border.width: Config.scaled(1, root.uiScale)
                        border.color: Config.fgcolor

                        Text {
                            anchors.centerIn: parent
                            text: "\u21b5"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "confirm"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                    }
                }
            }
        }
    }
}

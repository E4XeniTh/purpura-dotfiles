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
//   [        ]                    [Confirm]
//
// The number box has the keyboard from the start; Enter or Confirm sends
// `confirmed`, Escape `dismissed` (as does a click outside, which
// PowerMenu.qml catches).
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

            // Row 3: Confirm, at the right of column 3.
            Item {
                width: 2 * root.fieldWidth + root.gap
                height: root.rowHeight

                Rectangle {
                    anchors.right: parent.right
                    width: confirmText.implicitWidth + Config.scaled(24, root.uiScale)
                    height: parent.height
                    color: confirmMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.width: Config.scaled(2, root.uiScale)
                    border.color: Config.fgcolor

                    Text {
                        id: confirmText
                        anchors.centerIn: parent
                        text: "Confirm"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                    }

                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.confirm()
                    }
                }
            }
        }
    }
}

import QtQuick
import "../"

// Simple current-month calendar. Self-contained (no external services).
Item {
    id: root

    property date today: new Date()
    readonly property int year: today.getFullYear()
    readonly property int month: today.getMonth()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property int firstWeekday: new Date(year, month, 1).getDay()

    Column {
        anchors.fill: parent
        spacing: 8

        Item {
            width: root.width
            height: monthtext.height

            Text {
                id: monthtext
                anchors.left: parent.left
                text: Qt.formatDate(root.today, "MMMM")
                color: Theme.fgcolor
                font.pixelSize: 14
                font.bold: true
            }

            Text {
                id: yeartext
                anchors.right: parent.right
                text: Qt.formatDate(root.today, "yyyy")
                color: Theme.fgcolor
                font.pixelSize: 14
                font.bold: true
            }
        }
        Grid {
            columns: 7
            columnSpacing: 2
            rowSpacing: 4

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]

                delegate: Text {
                    required property string modelData

                    width: (root.width - 12) / 7
                    height: 24

                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.fgcolordark
                    font.pixelSize: 12
                    font.bold: true
                    opacity: 1
                }
            }

            Repeater {
                model: root.firstWeekday

                delegate: Item {
                    width: (root.width - 12) / 7
                    height: 20
                }
            }

            Repeater {
                model: root.daysInMonth

                delegate: Rectangle {
                    id: dayCell

                    required property int index

                    readonly property bool isToday: (dayCell.index + 1) === root.today.getDate()

                    width: (root.width - 12) / 7
                    height: 20
                    radius: 0

                    color: isToday ? Theme.fgcolordark : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: dayCell.index + 1
                        color: dayCell.isToday ? Theme.fgcolor : Theme.fgcolordark
                        font.pixelSize: 12
                        font.bold: dayCell.isToday
                    }
                }
            }
        }
    }
}

import QtQuick
import "../"

// Simple current-month calendar. Self-contained (no external services).
Item {
    id: root

    property date today: new Date()
    readonly property int year: today.getFullYear()
    readonly property int month: today.getMonth()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    // Date.getDay() is Sunday-first (0-6). +6 mod 7 re-bases it to
    // Monday-first (0 = Monday ... 6 = Sunday) for the European week.
    readonly property int firstWeekday: (new Date(year, month, 1).getDay() + 6) % 7

    Column {
        anchors.fill: parent
        spacing: 16

        Item {
            width: root.width
            height: monthtext.height

            Text {
                id: monthtext
                anchors.left: parent.left
                text: Qt.formatDate(root.today, "    MMMM")
                color: Theme.fgcolor
                font.pixelSize: 14
                font.bold: true
            }

            Text {
                id: yeartext
                anchors.right: parent.right
                text: Qt.formatDate(root.today, "yyyy   ")
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
                model: ["M", "T", "W", "T", "F", "S", "S"]

                delegate: Text {
                    required property string modelData

                    width: (root.width - 12) / 7
                    height: 24

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignCenter
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
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}

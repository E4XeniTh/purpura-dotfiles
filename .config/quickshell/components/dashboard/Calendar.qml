import QtQuick
import "../"
import "../../Config.js" as Config

// Simple current-month calendar. Self-contained (no external services).
Item {
    id: root

    property real uiScale: 1.0

    property date today: new Date()
    readonly property int year: today.getFullYear()
    readonly property int month: today.getMonth()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    // Date.getDay() is Sunday-first (0-6). +6 mod 7 re-bases it to
    // Monday-first (0 = Monday ... 6 = Sunday) for the European week.
    readonly property int firstWeekday: (new Date(year, month, 1).getDay() + 6) % 7

    // Width of one of the 7 weekday columns, minus a small fixed gutter
    // (also scaled) that isn't otherwise accounted for by the Grid's own
    // spacing.
    readonly property real cellWidth: (root.width - Config.scaled(12, root.uiScale)) / 7

    Column {
        anchors.fill: parent
        spacing: Config.scaled(16, root.uiScale)

        Item {
            width: root.width
            height: monthtext.height

            Text {
                id: monthtext
                anchors.left: parent.left
                text: Qt.formatDate(root.today, "  MMMM")
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
            }

            Text {
                id: yeartext
                anchors.right: parent.right
                text: Qt.formatDate(root.today, "yyyy  ")
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
            }
        }
        Grid {
            columns: 7
            columnSpacing: Config.scaled(2, root.uiScale)
            rowSpacing: Config.scaled(4, root.uiScale)

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                delegate: Text {
                    required property string modelData

                    width: root.cellWidth
                    height: Config.scaled(24, root.uiScale)

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignCenter
                    text: modelData
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, root.uiScale)
                    font.bold: true
                    opacity: 1
                }
            }

            Repeater {
                model: root.firstWeekday

                delegate: Item {
                    width: root.cellWidth
                    height: Config.scaled(20, root.uiScale)
                }
            }

            Repeater {
                model: root.daysInMonth

                delegate: Rectangle {
                    id: dayCell

                    required property int index

                    readonly property bool isToday: (dayCell.index + 1) === root.today.getDate()

                    width: root.cellWidth
                    height: Config.scaled(20, root.uiScale)
                    radius: 0

                    color: isToday ? Config.fgcolordark : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: dayCell.index + 1
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(12, root.uiScale)
                        font.bold: dayCell.isToday
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}

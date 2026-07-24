import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../"
import "../../Config.js" as Config

// Current-month calendar, with month/year picker grids swapped in for the
// day grid. Self-contained (no external services).
Item {
    id: root

    property real uiScale: 1.0
    // Bound to the dashboard's own open state from Dashboard.qml, so the
    // calendar resets to today (and out of whichever picker mode it was
    // left in) every time the dashboard reopens instead of staying on
    // whatever month/year was last browsed to.
    property bool dashboardOpen: false

    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    // "days" (default), "months" (picking a month) or "years" (picking a
    // year) - mutually exclusive, see monthtext/yeartext below.
    property string mode: "days"

    // Whether the header's reset button should show - either mid-pick, or
    // parked on a month/year other than today's.
    readonly property bool awayFromToday: mode !== "days"
        || viewYear !== today.getFullYear()
        || viewMonth !== today.getMonth()

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function resetToToday() {
        today = new Date()
        viewYear = today.getFullYear()
        viewMonth = today.getMonth()
        mode = "days"
    }

    onDashboardOpenChanged: {
        if (dashboardOpen) {
            resetToToday()
        }
    }

    readonly property int daysInMonth: new Date(viewYear, viewMonth + 1, 0).getDate()
    // Date.getDay() is Sunday-first (0-6). +6 mod 7 re-bases it to
    // Monday-first (0 = Monday ... 6 = Sunday) for the European week.
    readonly property int firstWeekday: (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7

    // Width of one of the 7 weekday columns, minus a small fixed gutter
    // (also scaled) that isn't otherwise accounted for by the Grid's own
    // spacing.
    readonly property real cellWidth: (root.width - Config.scaled(12, root.uiScale)) / 7
    // Width of one of the 3 columns in the month/year picker grids.
    readonly property real pickerCellWidth: (root.width - 2 * Config.scaled(8, root.uiScale)) / 3

    Column {
        anchors.fill: parent
        // Tighter than before - a 6-row month (up to 42 day cells) needs
        // every bit of vertical room it can get, see the day grid's own
        // sizing below.
        spacing: Config.scaled(10, root.uiScale)

        Item {
            width: root.width
            height: monthtext.height

            Text {
                id: monthtext
                anchors {
                    left: parent.left
                    leftMargin: Config.scaled(4, root.uiScale)
                }
                visible: root.mode !== "months"
                text: root.monthNames[root.viewMonth]
                // Dimmed and unclickable while picking a year, same
                // treatment yeartext gets while picking a month.
                color: root.mode === "years" ? Config.fgcolordark
                    : (monthMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor)
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true

                MouseArea {
                    id: monthMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.mode === "days"
                    onClicked: root.mode = "months"
                }
            }

            // Reset-to-today button, shown between the two labels whenever
            // browsing away from today (mid-pick, or already landed on a
            // different month/year).
            Item {
                anchors.centerIn: parent
                visible: root.awayFromToday
                width: Config.scaled(14, root.uiScale)
                height: Config.scaled(14, root.uiScale)

                IconImage {
                    id: resetIcon
                    anchors.fill: parent
                    source: Quickshell.iconPath("edit-reset-symbolic")
                }

                ColorOverlay {
                    anchors.fill: resetIcon
                    source: resetIcon
                    color: resetMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                }

                MouseArea {
                    id: resetMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.resetToToday()
                }
            }

            Text {
                id: yeartext
                anchors {
                    right: parent.right
                    rightMargin: Config.scaled(4, root.uiScale)
                }
                visible: root.mode !== "years"
                text: root.viewYear
                color: root.mode === "months" ? Config.fgcolordark
                    : (yearMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor)
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true

                MouseArea {
                    id: yearMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.mode === "days"
                    onClicked: root.mode = "years"
                }
            }
        }

        Grid {
            visible: root.mode === "days"
            columns: 7
            columnSpacing: Config.scaled(2, root.uiScale)
            rowSpacing: Config.scaled(3, root.uiScale)

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                delegate: Text {
                    required property string modelData

                    width: root.cellWidth
                    height: Config.scaled(20, root.uiScale)

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignCenter
                    text: modelData
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(11, root.uiScale)
                    font.bold: true
                    opacity: 1
                }
            }

            Repeater {
                model: root.firstWeekday

                delegate: Item {
                    width: root.cellWidth
                    height: Config.scaled(18, root.uiScale)
                }
            }

            Repeater {
                model: root.daysInMonth

                delegate: Rectangle {
                    id: dayCell

                    required property int index

                    readonly property bool isToday: (dayCell.index + 1) === root.today.getDate()
                        && root.viewMonth === root.today.getMonth()
                        && root.viewYear === root.today.getFullYear()

                    width: root.cellWidth
                    height: Config.scaled(18, root.uiScale)
                    radius: 0

                    color: isToday ? Config.fgcolordark : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: dayCell.index + 1
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(11, root.uiScale)
                        font.bold: dayCell.isToday
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Grid {
            visible: root.mode === "months"
            columns: 3
            columnSpacing: Config.scaled(8, root.uiScale)
            rowSpacing: Config.scaled(8, root.uiScale)

            Repeater {
                model: 12

                delegate: Rectangle {
                    id: monthCell

                    required property int index

                    width: root.pickerCellWidth
                    height: Config.scaled(28, root.uiScale)
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: root.monthNames[monthCell.index].slice(0, 3)
                        color: monthPickMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(12, root.uiScale)
                        font.bold: monthCell.index === root.viewMonth
                    }

                    MouseArea {
                        id: monthPickMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.viewMonth = monthCell.index
                            root.mode = "days"
                        }
                    }
                }
            }
        }

        Grid {
            visible: root.mode === "years"
            columns: 3
            columnSpacing: Config.scaled(8, root.uiScale)
            rowSpacing: Config.scaled(8, root.uiScale)

            Repeater {
                model: 12

                delegate: Rectangle {
                    id: yearCell

                    required property int index
                    // Centers the 12-year picker roughly on the currently
                    // viewed year rather than always starting at it.
                    readonly property int yearValue: root.viewYear - 5 + yearCell.index

                    width: root.pickerCellWidth
                    height: Config.scaled(28, root.uiScale)
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: yearCell.yearValue
                        color: yearPickMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(12, root.uiScale)
                        font.bold: yearCell.yearValue === root.viewYear
                    }

                    MouseArea {
                        id: yearPickMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.viewYear = yearCell.yearValue
                            root.mode = "days"
                        }
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import "../../../Config.js" as Config

// A checkbox and its label, drawn the way ShellSettings.qml's own are. Dark
// and unclickable while `usable` is false - i.e. while the option it hangs
// off is turned off.
RowLayout {
    id: root

    property real uiScale: 1.0
    property string text: ""
    property bool checked: false
    property bool usable: true

    signal toggled()

    readonly property color shownColor: root.usable ? Config.fgcolor : Config.fgcolordark

    spacing: Config.scaled(8, root.uiScale)

    Rectangle {
        Layout.preferredWidth: Config.scaled(20, root.uiScale)
        Layout.preferredHeight: Config.scaled(20, root.uiScale)
        color: root.checked ? root.shownColor : Config.fillcolor
        border.width: Config.scaled(2, root.uiScale)
        border.color: root.shownColor
        radius: 0

        MouseArea {
            anchors.fill: parent
            enabled: root.usable
            hoverEnabled: true
            onClicked: root.toggled()
        }
    }

    Text {
        text: root.text
        color: root.shownColor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(13, root.uiScale)
        font.bold: true

        MouseArea {
            anchors.fill: parent
            enabled: root.usable
            hoverEnabled: true
            onClicked: root.toggled()
        }
    }

    Item { Layout.fillWidth: true }
}

import QtQuick
import QtQuick.Layouts
import "../../../Config.js" as Config
import "../../common"

// A checkbox and its label, drawn the way ShellSettings.qml's own are (the box
// is CheckSquare.qml, like the Qt apps' under the Kvantum theme). Dark and
// unclickable while `usable` is false - i.e. while the option it hangs off is
// turned off.
RowLayout {
    id: root

    property real uiScale: 1.0
    property string text: ""
    property bool checked: false
    property bool usable: true

    signal toggled()

    readonly property color shownColor: root.usable ? Config.fgcolor : Config.fgcolordark

    spacing: Config.scaled(8, root.uiScale)

    CheckSquare {
        Layout.preferredWidth: Config.scaled(20, root.uiScale)
        Layout.preferredHeight: Config.scaled(20, root.uiScale)
        uiScale: root.uiScale
        checked: root.checked
        tint: root.shownColor
        hovered: boxMouse.containsMouse || labelMouse.containsMouse

        MouseArea {
            id: boxMouse
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
            id: labelMouse
            anchors.fill: parent
            enabled: root.usable
            hoverEnabled: true
            onClicked: root.toggled()
        }
    }

    Item { Layout.fillWidth: true }
}

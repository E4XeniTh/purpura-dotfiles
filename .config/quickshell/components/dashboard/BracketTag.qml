import QtQuick
import "../../Config.js" as Config

// "┌ TEXT ┐" bracket-wrapped stat tag - SystemMonitor.qml's own small
// stat readouts (temp, percent, used/total) all use this, right-aligned
// next to each section's label. A separate reusable file rather than
// repeating the same three Text elements inline at every call site -
// this Quickshell's QML engine rejects the inline `component Name: Item
// {}` declaration syntax outright at boot (see PowerMenu.qml's own
// comment on its Repeater for the same limitation), so a real file is
// the only way to share this without duplicating it eight times over.
Row {
    id: root

    property real uiScale: 1.0
    property string text: ""
    // Preset width for the value text, unscaled px (Config.scaled is
    // applied internally). -1 falls back to the text's own implicit
    // width. Callers should pass this so the tag's total width - and
    // everything right-aligned alongside it - stays put as the digit/
    // character count of the value changes (e.g. "9%" vs "100%"),
    // instead of visibly growing and shrinking on every poll tick.
    property real valueWidth: -1
    spacing: Config.scaled(1, root.uiScale)

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "┌"
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(10, root.uiScale)
        font.bold: true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: root.valueWidth >= 0 ? Config.scaled(root.valueWidth, root.uiScale) : implicitWidth
        horizontalAlignment: Text.AlignHCenter
        text: root.text
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(11, root.uiScale)
        font.bold: true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "┐"
        color: Config.fgcolor
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(10, root.uiScale)
        font.bold: true
    }
}

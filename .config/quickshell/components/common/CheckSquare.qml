import QtQuick
import "../../Config.js" as Config

// A checkbox's box, drawn the way the Qt apps draw theirs under the dotfiles'
// Kvantum theme (~/.config/Kvantum/KvPurpleBlack, its checkbox-* elements): a
// border round an empty inside, and when ticked, a square half the box's size
// in the middle of it, the same colour as the border. Under the mouse - its
// own or its label's, as in Qt - the inside turns the hover purple.
//
// Just the drawing: whoever uses it says when it's ticked or hovered, and takes
// the clicks.
Rectangle {
    id: root

    property real uiScale: 1.0
    property bool checked: false
    property bool hovered: false
    // The border's and the tick's colour - Config.fgcolordark, say, while the
    // option can't be changed.
    property color tint: Config.fgcolor

    implicitWidth: Config.scaled(20, root.uiScale)
    implicitHeight: Config.scaled(20, root.uiScale)

    color: root.hovered ? Config.fgcolorhover : Config.fillcolor
    border.width: Config.scaled(2, root.uiScale)
    border.color: root.tint
    radius: 0

    Rectangle {
        // Half the box, rounded so it's an even number of pixels from both
        // sides - centred on whole pixels, never blurred across two.
        readonly property int side: {
            const box = Math.round(Math.min(root.width, root.height))
            const half = Math.round(box / 2)
            return (box - half) % 2 === 0 ? half : half - 1
        }

        anchors.centerIn: parent
        width: side
        height: side
        visible: root.checked
        color: root.tint
    }
}

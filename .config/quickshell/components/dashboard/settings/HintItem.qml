import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../../Config.js" as Config

// One "[icon] label" fragment used in the small hint rows at the bottom
// of the settings panels, explaining what left-click/right-click/
// double-click/scroll does on the cards above. A RowLayout, so it sizes
// itself to its content and can sit as one unit inside an outer
// Row/RowLayout, in either icon-first ("[icon] label", used for
// left-anchored hints) or label-first ("label [icon]", used for
// right-anchored hints in BluetoothSettings) order.
RowLayout {
    id: root

    property real uiScale: 1.0
    property string label: ""
    // Shown before everything else, e.g. "Dbl" for a double-click hint -
    // there's no dedicated double-click icon, so this plus the ordinary
    // left-click icon is how that's represented.
    property string prefix: ""
    property string iconSource: ""
    property color tint: Config.fgcolor
    property bool iconFirst: true

    spacing: Config.scaled(4, root.uiScale)

    Text {
        visible: root.prefix.length > 0
        text: root.prefix
        color: root.tint
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(14, root.uiScale)
    }

    Item {
        visible: root.iconFirst
        Layout.preferredWidth: Config.scaled(18, root.uiScale)
        Layout.preferredHeight: Config.scaled(18, root.uiScale)

        IconImage {
            id: leadIcon
            anchors.fill: parent
            source: root.iconSource
        }

        ColorOverlay {
            anchors.fill: leadIcon
            source: leadIcon
            color: root.tint
        }
    }

    Text {
        text: root.label
        color: root.tint
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(14, root.uiScale)
    }

    Item {
        visible: !root.iconFirst
        Layout.preferredWidth: Config.scaled(18, root.uiScale)
        Layout.preferredHeight: Config.scaled(18, root.uiScale)

        IconImage {
            id: trailIcon
            anchors.fill: parent
            source: root.iconSource
        }

        ColorOverlay {
            anchors.fill: trailIcon
            source: trailIcon
            color: root.tint
        }
    }
}

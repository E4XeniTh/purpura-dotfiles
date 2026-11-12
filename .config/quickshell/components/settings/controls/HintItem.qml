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
    // Pinned explicitly rather than relying on RowLayout's own default
    // cross-axis stretch/alignment for these children - left unset, the
    // icons/text ended up sitting low, offset toward the bottom of
    // whatever height an outer row gave this whole fragment instead of
    // centered within it.
    Layout.alignment: Qt.AlignVCenter

    Text {
        visible: root.prefix.length > 0
        Layout.alignment: Qt.AlignVCenter
        text: root.prefix
        color: root.tint
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(14, root.uiScale)
        verticalAlignment: Text.AlignVCenter
    }

    Item {
        visible: root.iconFirst
        Layout.alignment: Qt.AlignVCenter
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
        Layout.alignment: Qt.AlignVCenter
        text: root.label
        color: root.tint
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(14, root.uiScale)
        verticalAlignment: Text.AlignVCenter
    }

    Item {
        visible: !root.iconFirst
        Layout.alignment: Qt.AlignVCenter
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

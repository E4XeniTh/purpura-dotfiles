import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../../Config.js" as Config
import "../../common"
import "../controls"

// One monitor in ScreenSettings' left list. Left-click selects it (shows
// its config in the right-hand form); right-click toggles a pending
// activate/deactivate flag, reflected only in border color - nothing is
// actually enabled/disabled until Apply is pressed. Double-click marks it
// primary (fgcolorlight border, overriding the enabled/disabled color, and
// a [Primary] tag by the name - see ScreenSettings.qml for what "primary"
// actually does). The arrangement view (MonitorLayout.qml) colors its
// monitors' borders the same way.
//
// Below the icon/label row is a thin brightness slider (ddcutil for an
// external DDC/CI display, brightnessctl for a laptop's own internal
// panel - see Dashboard.qml) - also staged, not live: dragging it only
// stores a pending value (brightnessEdited), actually sent to the
// monitor on Apply, same as everything else here.
DashCard {
    id: root

    required property string name
    required property bool pendingEnabled
    required property bool selected
    required property bool isPrimary
    required property real brightness // 0-100
    // False for a monitor neither ddcutil nor brightnessctl can reach
    // at all (see Dashboard.qml's ddcBusNumbers/hasBrightnessctlDevice)
    // - e.g. a TV/monitor with no DDC/CI support, or neither tool
    // installed. The brightness slider (and its separator) below is
    // meaningless for one of these - dragging it would only ever fail
    // silently on Apply, so it's hidden entirely rather than shown
    // broken.
    required property bool supportsBrightness
    // The slider (and its separator) shows only for a display that can
    // take it and is on - disabled, or about to be on Apply, there's
    // nothing to set the brightness of.
    readonly property bool showsBrightness: root.supportsBrightness && root.pendingEnabled
    property real uiScale: 1.0

    signal clicked()
    signal toggleEnabled()
    signal makePrimary()
    signal brightnessEdited(real value)

    // Selecting it only lights up the background; the text goes by its
    // state alone - primary, enabled, disabled - as in the arrangement view.
    color: root.selected ? Config.fgcolorhover : Config.fillcolor
    readonly property color textColor: root.isPrimary ? Config.fgcolorlight
        : (root.pendingEnabled ? Config.fgcolor : Config.fgcolorred)
    border.color: root.isPrimary ? Config.fgcolorlight : (root.pendingEnabled ? Config.fgcolor : Config.fgcolorred)

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                root.clicked()
            } else {
                root.toggleEnabled()
            }
        }
        // Qt still fires a plain clicked() for the first
        // press/release of a double-click before this -
        // harmless here, it just also selects the card, which
        // makes sense alongside marking it primary anyway.
        onDoubleClicked: root.makePrimary()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Config.scaled(10, root.uiScale)
        }
        spacing: Config.scaled(6, root.uiScale)


        RowLayout {
            id: headerRow

            Layout.fillWidth: true
            spacing: Config.scaled(10, root.uiScale)

            Item {
                Layout.preferredWidth: Config.scaled(24, root.uiScale)
                Layout.preferredHeight: Config.scaled(24, root.uiScale)

                IconImage {
                    id: monitorIcon
                    anchors.fill: parent
                    source: Quickshell.iconPath("video-display-symbolic")
                }

                ColorOverlay {
                    anchors.fill: monitorIcon
                    source: monitorIcon
                    color: root.border.color
                }
            }

            // Takes the room the tag leaves, so the tag sits at the right
            // edge and the name only elides when the card's too narrow.
            Text {
                Layout.fillWidth: true
                text: root.name
                color: root.textColor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
                elide: Text.ElideRight
            }

            Tag {
                visible: root.isPrimary
                uiScale: root.uiScale
                label: "Primary"
            }

            // Scoped to just this row (not the whole card) so it
            // doesn't steal drag input from the brightness slider below.
        }

        Rectangle {
            visible: root.showsBrightness
            Layout.fillWidth: true
            Layout.preferredHeight: Config.scaled(1, root.uiScale)
            color: root.border.color
        }


        DeviceSlider {
            visible: root.showsBrightness
            Layout.fillWidth: true
            // Thinner/smaller than the volume OSD's own slider - this
            // is a secondary control buried in a small list card.
            uiScale: root.uiScale * 0.6
            value: root.brightness / 100
            onMoved: (newValue) => root.brightnessEdited(Math.round(newValue * 100))
        }


    }
}

import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Bar widget: brightness icon + a horizontal "digital"/segmented level bar
// (DigitalBar.qml, same style VolumeControl.qml/BatteryControl.qml use) +
// a percentage readout - click or drag anywhere on the segmented area to
// set brightness directly, scroll anywhere on the widget to nudge it.
//
// Targets whichever monitor is currently selected in Screen Settings
// (dashboard.videoSelectedMonitor), falling back to the designated
// primary before anything's ever been selected there - this can be any
// connected display, not just whichever screen this bar itself lives
// on, since Screen Settings lets you pick any of them. Actually applying
// a change is debounced by 330ms (see applyTimer below): every drag/
// scroll tick updates the on-screen value and Screen Settings' own
// slider (if open) immediately via setPendingBrightness, but the real
// ddcutil/brightnessctl call only fires once dragging/scrolling has
// paused - a slider drag alone would otherwise fire dozens of ddcutil
// invocations a second.
Rectangle {
    id: root

    property real uiScale: 1.0
    property var dashboard: null

    readonly property string targetMonitor: root.dashboard
        ? (root.dashboard.videoSelectedMonitor.length > 0 ? root.dashboard.videoSelectedMonitor : root.dashboard.primaryMonitor)
        : ""

    readonly property bool controllable: !!(root.dashboard && root.targetMonitor.length > 0 && root.dashboard.supportsBrightness(root.targetMonitor))
    readonly property real brightness: root.controllable ? root.dashboard.brightnessFor(root.targetMonitor) : 0

    function setBrightnessFromX(mx) {
        if (!root.controllable) return
        const value = Math.round(Math.max(0, Math.min(1, mx / bar.totalWidth)) * 100)
        root.dashboard.setPendingBrightness(root.targetMonitor, value)
        applyTimer.restart()
    }

    function nudgeBrightness(delta) {
        if (!root.controllable) return
        const value = Math.round(Math.max(0, Math.min(100, root.brightness + delta)))
        root.dashboard.setPendingBrightness(root.targetMonitor, value)
        applyTimer.restart()
    }

    // See the file comment above - the actual apply, debounced.
    Timer {
        id: applyTimer
        interval: 330
        repeat: false
        onTriggered: {
            if (root.controllable) root.dashboard.applyBrightnessFor([root.targetMonitor])
        }
    }

    // Hidden entirely (same collapse-to-nothing approach
    // BatteryControl.qml uses) when the current target has no
    // brightness control at all - no ddcutil bus, no brightnessctl
    // device, or no dashboard reference to ask in the first place.
    visible: root.controllable
    width: visible ? implicitWidth : 0
    height: visible ? implicitHeight : 0

    color: "transparent"
    border.width: Config.scaled(2, root.uiScale)
    border.color: Config.fgcolor
    radius: 0

    implicitHeight: Config.scaled(34, root.uiScale)
    implicitWidth: content.implicitWidth + Config.scaled(20, root.uiScale)

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Config.scaled(8, root.uiScale)

        Item {
            width: Config.scaled(20, root.uiScale)
            height: Config.scaled(20, root.uiScale)
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
                id: brightnessIcon
                anchors.fill: parent
                source: Quickshell.iconPath("display-brightness-symbolic", "video-display-symbolic")
            }

            ColorOverlay {
                anchors.fill: brightnessIcon
                source: brightnessIcon
                color: Config.fgcolor
            }
        }

        Item {
            id: segmentsBox
            width: bar.implicitWidth
            height: bar.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            // No anchors/explicit size on bar itself - see
            // VolumeControl.qml's identical segmentsBox for why that'd
            // be a binding cycle.
            DigitalBar {
                id: bar
                uiScale: root.uiScale
                value: root.brightness / 100
                segmentCount: 18
                litColor: dragArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onPressed: (mouse) => root.setBrightnessFromX(mouse.x)
                onPositionChanged: (mouse) => {
                    if (pressed) root.setBrightnessFromX(mouse.x)
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.brightness) + "%"
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }
    }

    // Scroll anywhere on the widget as a brightness shortcut, same
    // convention VolumeControl.qml uses.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => root.nudgeBrightness(wheel.angleDelta.y > 0 ? 5 : -5)
    }
}

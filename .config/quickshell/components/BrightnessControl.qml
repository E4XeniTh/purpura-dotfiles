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
// Always targets the designated primary monitor (root.dashboard.primaryMonitor)
// - not whichever monitor happens to be selected in Screen Settings, since
// that selection is just a UI cursor for editing a *different* monitor's
// resolution/position and has nothing to do with what the bar itself
// should control. Actually applying a change is debounced by 330ms (see
// applyTimer below): every drag/scroll tick updates the on-screen value
// immediately via setBarBrightness, but the real ddcutil/brightnessctl
// call only fires once dragging/scrolling has paused - a slider drag
// alone would otherwise fire dozens of ddcutil invocations a second.
// Deliberately uses its own barBrightnessOverride staging rather than
// Screen Settings' pendingBrightness (setPendingBrightness/brightnessFor)
// - sharing one meant dragging Screen Settings' own per-monitor slider
// made this widget immediately show the not-yet-applied value as if it
// had already taken effect.
Rectangle {
    id: root

    property real uiScale: 1.0
    property var dashboard: null

    // effectivePrimaryMonitor(), not root.dashboard.primaryMonitor
    // directly - the latter defaults to a hardcoded output name that
    // isn't persisted to disk, so on a laptop that's never had its
    // eDP-1 panel explicitly set as primary it pointed at a monitor
    // that doesn't exist at all, leaving this widget hidden forever
    // once detection finished (see Dashboard.qml's own comment on
    // effectivePrimaryMonitor for the same failure mode Bar.qml already
    // guards against for the bar's own visibility).
    readonly property string targetMonitor: root.dashboard ? root.dashboard.effectivePrimaryMonitor() : ""

    // False until both the ddcutil and brightnessctl detect Processes
    // (Dashboard.qml) have completed at least once - supportsBrightness()
    // can't be trusted either way before then, so this widget shows a
    // "detecting..." placeholder (see detecting below) rather than
    // guessing "unsupported" and popping in after the fact.
    readonly property bool detectionDone: !!(root.dashboard && root.dashboard.brightnessDetectionDone)
    readonly property bool detecting: !root.detectionDone

    readonly property bool controllable: !!(root.detectionDone && root.targetMonitor.length > 0 && root.dashboard.supportsBrightness(root.targetMonitor))
    readonly property real brightness: root.controllable ? root.dashboard.barBrightnessFor(root.targetMonitor) : 0

    function setBrightnessFromX(mx) {
        if (!root.controllable) return
        const value = Math.round(Math.max(0, Math.min(1, mx / bar.totalWidth)) * 100)
        root.dashboard.setBarBrightness(root.targetMonitor, value)
        applyTimer.restart()
    }

    function nudgeBrightness(delta) {
        if (!root.controllable) return
        const value = Math.round(Math.max(0, Math.min(100, root.brightness + delta)))
        root.dashboard.setBarBrightness(root.targetMonitor, value)
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
    // BatteryControl.qml uses) only once detection has actually finished
    // and confirmed the primary has no brightness control at all - while
    // still detecting, the widget stays up showing the placeholder below
    // instead of disappearing and possibly popping back in a moment later.
    visible: root.detecting || root.controllable
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
            visible: !root.detecting
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

        // Same width as the real bar (bar.implicitWidth, even while
        // hidden) and centered within it, so this doesn't shift the
        // percentage slot over versus the normal state.
        Text {
            visible: root.detecting
            anchors.verticalCenter: parent.verticalCenter
            width: bar.implicitWidth
            horizontalAlignment: Text.AlignHCenter
            text: "detecting"
            font.italic: true
            color: Config.fgcolordarklight
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
        }

        // Fixed width (fits "100%") regardless of digit count, so the
        // widget's own overall width doesn't jitter as the value changes
        // - same reasoning VolumeControl.qml/BatteryControl.qml apply to
        // their own percentage readouts.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Config.scaled(40, root.uiScale)
            horizontalAlignment: Text.AlignRight
            text: root.detecting ? "--" : Math.round(root.brightness) + "%"
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

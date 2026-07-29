import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Same structure/behavior as VolumeOsd.qml - a transient, read-only
// popup for the designated primary monitor's brightness. Triggered off
// dashboard.liveBrightness changing rather than a Pipewire-style signal
// (brightness has no equivalent live service) - deliberately watches
// liveBrightness specifically, not barBrightnessOverride/pendingBrightness,
// so this only pops up once a change has actually been applied (either
// via Bar.qml's own debounced apply, or Screen Settings' Apply button),
// not while a slider/drag is merely staged and not yet real.
Scope {
    id: root

    // Fed in from shell.qml, same as Bar.qml's own dashboard reference.
    property var dashboard: null

    readonly property string targetMonitor: root.dashboard ? root.dashboard.primaryMonitor : ""
    readonly property real currentBrightness: (root.dashboard && root.dashboard.liveBrightness[root.targetMonitor] !== undefined)
        ? root.dashboard.liveBrightness[root.targetMonitor]
        : 0

    // The very first currentBrightness change is Dashboard.qml's initial
    // ddcutil/brightnessctl query discovering the monitor's existing
    // value at startup, not an actual user-driven change - without this,
    // the OSD would pop up once every time quickshell starts.
    property bool initialized: false

    onCurrentBrightnessChanged: {
        if (!root.initialized) {
            root.initialized = true
            return
        }
        root.shouldShowOsd = true
        hideTimer.restart()
    }

    property bool shouldShowOsd: false
    // Set from the hover MouseArea below, so the OSD doesn't disappear out
    // from under the mouse while it's being looked at.
    property bool hovered: false

    Timer {
        id: hideTimer
        interval: 2500

        // Single-shot, so while hovered this just keeps re-arming itself
        // instead of actually hiding - it'll hide ~1s after hover ends.
        onTriggered: {
            if (root.hovered) {
                hideTimer.restart()
            } else {
                root.shouldShowOsd = false
            }
        }
    }

    // The OSD window will be created and destroyed based on shouldShowOsd.
    // PanelWindow.visible could be set instead of using a loader, but using
    // a loader will reduce the memory overhead when the window isn't open.
    LazyLoader {
        active: root.shouldShowOsd

        PanelWindow {
            // Since the panel's screen is unset, it will be picked by the compositor
            // when the window is created. Most compositors pick the current active monitor.

            anchors.bottom: true
            margins.bottom: screen.height / 8
            exclusiveZone: 0

            implicitWidth: 500
            implicitHeight: 84
            color: "transparent"

            // Purely a display - no click mask needed since nothing
            // inside accepts mouse input, only hover-to-stay-open.

            Rectangle {
                anchors.fill: parent
                color: Config.fillcolor
                radius: 0
                border.width: 2
                border.color: Config.fgcolor

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: root.hovered = true
                    onExited: root.hovered = false
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Item {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36

                        IconImage {
                            id: brightIcon
                            anchors.fill: parent
                            source: Quickshell.iconPath("display-brightness-symbolic", "video-display-symbolic")
                        }

                        ColorOverlay {
                            anchors.fill: brightIcon
                            source: brightIcon
                            color: Config.fgcolor
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: bar.implicitHeight

                        DigitalBar {
                            id: bar
                            uiScale: 1.4
                            targetWidth: parent.width
                            segmentCount: 30
                            value: root.currentBrightness / 100
                            litColor: Config.fgcolor
                        }
                    }

                    Text {
                        Layout.preferredWidth: 60
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.currentBrightness) + "%"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                }
            }
        }
    }
}

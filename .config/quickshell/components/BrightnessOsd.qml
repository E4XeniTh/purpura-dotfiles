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

    // Fed in from shell.qml too - a cross-reference to the other OSD's
    // own Scope instance, so each can tell whether the other is
    // currently shown (see otherOsdShown below) and shift itself out of
    // dead center instead of the two overlapping directly. A plain id
    // reference doesn't work here - VolumeOsd.qml/BrightnessOsd.qml are
    // separate top-level Scopes (siblings in shell.qml), and QML ids
    // aren't visible outside the component they're declared in.
    property var volumeOsd: null
    readonly property bool otherOsdShown: !!(root.volumeOsd && root.volumeOsd.shouldShowOsd)

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

    Timer {
        id: hideTimer
        interval: 1500

        onTriggered: {
                root.shouldShowOsd = false
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

            // Centered by default (no left/right anchor at all) - only
            // shifted right-of-center when VolumeOsd is ALSO up right
            // now, so the pair sits side by side (volume left,
            // brightness right - same left-to-right order Bar.qml's own
            // widgets use) instead of directly on top of each other.
            // Symmetric with VolumeOsd.qml's own mirror-image version of
            // this same margin.
            anchors.right: root.otherOsdShown
            margins.right: root.otherOsdShown ? Math.max(0, screen.width / 2 - implicitWidth - 10) : 0
            exclusiveZone: 0

            implicitWidth: 500
            implicitHeight: 84
            color: "transparent"

            // Purely a display - no click mask needed since nothing
            // inside accepts mouse input.

            Rectangle {
                anchors.fill: parent
                color: Config.fillcolor
                radius: 0
                border.width: 2
                border.color: Config.fgcolor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Item {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48

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
                            uiScale: 1.5
                            targetWidth: parent.width
                            segmentCount: 30
                            value: root.currentBrightness / 100
                            litColor: Config.fgcolor
                        }
                    }

                    Text {
                        Layout.preferredWidth: 60
                        horizontalAlignment: Text.AlignHCenter
                        text: Math.round(root.currentBrightness) + "%"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: 24
                        font.bold: true
                    }
                }
            }
        }
    }
}

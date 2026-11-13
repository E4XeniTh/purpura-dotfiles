import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config
import "../common"

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

    Timer {
        id: hideTimer
        interval: 1500

        onTriggered: {
                root.shouldShowOsd = false
        }
    }

    // Its box - OsdHost.qml shows it, with the other OSDs, where Settings >
    // General > Shell > OSD says, and sets uiScale.
    property Component box: Rectangle {
        id: brightnessBox

        property real uiScale: 1.0
        // The border's own: the screen and shell scale without the OSD
        // size, so the size setting never changes it.
        property real borderScale: 1.0

        width: Config.scaled(500, brightnessBox.uiScale)
        height: Config.scaled(84, brightnessBox.uiScale)
        color: Config.fillcolor
        radius: 0
        border.width: Config.scaled(2, brightnessBox.borderScale)
        border.color: Config.fgcolor

        RowLayout {
            anchors.fill: parent
            anchors.margins: Config.scaled(20, brightnessBox.uiScale)
            spacing: Config.scaled(16, brightnessBox.uiScale)

            Item {
                Layout.preferredWidth: Config.scaled(48, brightnessBox.uiScale)
                Layout.preferredHeight: Config.scaled(48, brightnessBox.uiScale)

                IconImage {
                    id: brightIcon
                    anchors.fill: parent
                    source: Quickshell.iconPath("video-display-brightness-symbolic", "monitor-symbolic")
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
                    uiScale: 1.5 * brightnessBox.uiScale
                    targetWidth: parent.width
                    segmentCount: 30
                    value: root.currentBrightness / 100
                    litColor: Config.fgcolor
                }
            }

            Text {
                Layout.preferredWidth: Config.scaled(60, brightnessBox.uiScale)
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(root.currentBrightness) + "%"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(24, brightnessBox.uiScale)
                font.bold: true
            }
        }
    }
}

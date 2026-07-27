import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../Config.js" as Config

// Shared shell for dashboard sub-panels (audio/weather/bluetooth settings):
// same two-phase stretch-then-drop open animation used everywhere else in
// this dashboard, anchored below it. Driven by `active` instead of a plain
// open/close pair, so a coordinator (Dashboard.qml) can sequence switching
// between panels: closing one plays its height-collapse animation first,
// only opening the next once `closed()` fires - see Dashboard.qml's
// toggleSettingsPanel().
PanelWindow {
    id: root

    // Set by the coordinator - only one sub-panel's `active` should ever
    // be true at a time.
    property bool active: false
    property real panelWidth: 800
    property real anchorTop: 0
    property real uiScale: 1.0
    property string namespaceName: "dashboard-panel"
    // Layer-shell surfaces default to no keyboard input at all - only
    // panels that actually need to type something (e.g. bluetooth's PIN/
    // password DialogCard) should opt into this, since OnDemand focus can
    // otherwise steal focus from other windows unexpectedly.
    property bool wantsKeyboardFocus: false

    // Callers nest their own content directly inside a SettingsPanel {}
    // block, same as any other Item - it's routed into contentHolder so
    // its childrenRect can drive the box's "open" height.
    default property alias content: contentHolder.data

    signal closed()

    // Actual window visibility - stays true through the close animation
    // (box shrinking back to the horizontal line) and only drops once
    // that finishes, unlike `active` which flips the instant the
    // coordinator picks a different panel.
    property bool reallyVisible: false
    visible: reallyVisible

    // Bypasses the close animation entirely - used when the dashboard
    // itself is closing, since dashWindow has no closing animation of its
    // own and a lingering 300ms sub-panel animation would look like a
    // orphaned floating box once the dashboard above it has already
    // vanished.
    function forceHide() {
        closeTimer.stop()
        openTimer.stop()
        reallyVisible = false
    }

    WlrLayershell.namespace: root.namespaceName
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.wantsKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusiveZone: 0

    anchors {
        top: true
    }

    margins {
        top: root.anchorTop
    }

    // A panel's real content height (contentHolder.height, driven by
    // whatever's nested inside - Bluetooth/Network/Screen settings all
    // vary a lot depending on how many devices/networks/monitors exist)
    // was never checked against how much screen is actually left below
    // where it opens - tall enough content could push the window's own
    // height past the bottom of the monitor. Same gap below as
    // anchorTop leaves above (Dashboard.qml's own Config.scaled(8, ...)
    // between the dashboard and this panel), so it's evenly framed
    // rather than flush with the edge.
    readonly property real maxAvailableHeight: root.screen
        ? Math.max(1, root.screen.height - root.anchorTop - Config.scaled(8, root.uiScale))
        : Number.MAX_VALUE
    readonly property real clampedContentHeight: Math.min(contentHolder.height, root.maxAvailableHeight)

    implicitWidth: root.panelWidth
    implicitHeight: Math.max(root.clampedContentHeight, 1)

    color: "transparent"

    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter

        width: 0
        height: 4

        color: Config.fillcolor

        states: [

            State {
                name: "horizontal"

                PropertyChanges {
                    target: box

                    width: root.panelWidth
                    height: 2
                }
            },

            State {
                name: "open"

                PropertyChanges {
                    target: box

                    width: root.panelWidth
                    height: Math.max(root.clampedContentHeight, 1)
                }
            }

        ]

        transitions: [

            Transition {

                NumberAnimation {

                    properties: "width,height"

                    duration: 300

                    easing.type: Easing.OutCubic

                }

            }

        ]

        Item {
            anchors.fill: parent
            clip: true

            Item {
                id: contentHolder

                width: root.panelWidth
                height: childrenRect.height
            }
        }

        Rectangle {
            anchors.fill: parent

            color: "transparent"

            border.width: Config.scaled(2, root.uiScale)
            border.color: Config.fgcolor

            radius: 0

            z: 10
        }
    }

    onActiveChanged: {
        if (active) {
            // Cancel a close in progress - re-activating before it
            // finished hiding just restarts the open sequence.
            closeTimer.stop()
            reallyVisible = true

            // Force a real state change even if the box was left sitting
            // in "horizontal" from a previous close (see closeTimer below)
            // - State/Transition only replay on an actual value change, so
            // going straight from "horizontal" to "horizontal" again would
            // silently no-op and skip the width-grow animation entirely.
            box.state = ""
            box.width = 0
            box.height = 4

            box.state = "horizontal"
            openTimer.restart()
        } else if (reallyVisible) {
            // Cancel an open in progress, otherwise it could still fire
            // box.state = "open" after we've already decided to close,
            // briefly flashing the panel back open mid-collapse.
            openTimer.stop()
            box.state = "horizontal"
            closeTimer.restart()
        }
    }

    Timer {
        id: openTimer

        // Must match the transition's duration above, so phase 1 (width)
        // fully finishes before phase 2 (height) starts.
        interval: 300
        repeat: false

        onTriggered: {
            box.state = "open"
        }
    }

    Timer {
        id: closeTimer

        // Matches the height-collapse transition's duration.
        interval: 300
        repeat: false

        onTriggered: {
            // Reset all the way back to the box's base (unstated) values,
            // not just left at "horizontal" - otherwise the next open's
            // box.state = "horizontal" is a same-value no-op (see above).
            box.state = ""
            box.width = 0
            box.height = 4

            root.reallyVisible = false
            root.closed()
        }
    }
}

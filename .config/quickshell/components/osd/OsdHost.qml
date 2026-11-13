import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../Config.js" as Config

// Where the volume, brightness and input language OSDs show, how big, and
// how they line up when more than one is up - Settings > General > Shell >
// OSD (barsettings.json, which ShellSettings.qml writes).
//
// One click-through window on the bar's monitor holds them all. It's sized
// for all three whatever's showing, so it never resizes as they come and go
// (Hyprland draws a layer surface's old picture stretched to a new size
// until the next one arrives); the ones showing pack together inside it,
// against the chosen edge. "Top" means under the bar: the window keeps out
// of the space the bar reserves (exclusiveZone 0).
//
// Each OSD decides when it shows (shouldShowOsd) and hands over its box as
// a Component with a uiScale property; this lays them out, in `osds` order.
Scope {
    id: root

    // Settings > General's global UI Scale (UiScale.qml), from shell.qml.
    property real shellScale: 1.0
    // The bar's monitor, from shell.qml.
    property string screenName: ""
    property var osds: []

    FileView {
        id: settingsFile

        path: Quickshell.env("HOME") + "/.config/quickshell/barsettings.json"
        // Read up front, so the first OSD already has its place - and a
        // change seen later is a real one (see the preview below).
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    readonly property var store: {
        try {
            return JSON.parse(settingsFile.text()) || {}
        } catch (e) {
            return {}
        }
    }

    // 50 - 150%.
    readonly property real size: {
        const n = Number(root.store.osdSize)
        return isFinite(n) && n > 0 ? Math.max(0.5, Math.min(1.5, n)) : 1
    }
    readonly property var positions: ["top-left", "top", "top-right", "bottom-left", "bottom", "bottom-right"]
    readonly property string position: root.positions.indexOf(root.store.osdPosition) >= 0 ? root.store.osdPosition : "bottom"
    readonly property bool atTop: root.position.startsWith("top")
    readonly property bool atLeft: root.position.endsWith("left")
    readonly property bool atRight: root.position.endsWith("right")
    // In a corner they always stack vertically.
    readonly property bool vertical: root.atLeft || root.atRight || root.store.osdStacking === "vertical"

    // A moment's look at all of them after any of these changes, so the
    // settings show what they do.
    property bool previewing: false

    function preview() {
        root.previewing = true
        previewTimer.restart()
    }

    onSizeChanged: root.preview()
    onPositionChanged: root.preview()
    onVerticalChanged: root.preview()

    Timer {
        id: previewTimer

        interval: 2000
        onTriggered: root.previewing = false
    }

    readonly property bool anyShown: root.previewing || root.osds.some(osd => osd && osd.shouldShowOsd)

    LazyLoader {
        active: root.anyShown

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === root.screenName) || Quickshell.screens[0] || null

            readonly property real baseScale: Config.uiScale(win.screen, root.shellScale)
            readonly property real uiScale: win.baseScale * root.size
            readonly property real gap: Config.scaled(10, win.uiScale)
            readonly property real boxWidth: Config.scaled(500, win.uiScale)
            readonly property real boxHeight: Config.scaled(84, win.uiScale)
            readonly property int count: Math.max(1, root.osds.length)

            WlrLayershell.namespace: "purpura-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: root.atTop
                bottom: !root.atTop
                left: root.atLeft
                right: root.atRight
            }
            // Centred along the top or bottom: an eighth of the screen in,
            // as they always were at the bottom. In a corner: tucked in.
            margins {
                top: root.atTop ? win.edgeDistance : 0
                bottom: root.atTop ? 0 : win.edgeDistance
                left: root.atLeft ? win.cornerInset : 0
                right: root.atRight ? win.cornerInset : 0
            }
            readonly property real cornerInset: Config.scaled(20, win.baseScale)
            readonly property real edgeDistance: (root.atLeft || root.atRight)
                ? win.cornerInset
                : (win.screen ? win.screen.height / 8 : 0)

            exclusiveZone: 0
            // Purely informational: clicks go straight through.
            mask: Region {}
            color: "transparent"

            implicitWidth: root.vertical ? win.boxWidth : win.count * win.boxWidth + (win.count - 1) * win.gap
            implicitHeight: root.vertical ? win.count * win.boxHeight + (win.count - 1) * win.gap : win.boxHeight

            // The ones showing, packed against the window's anchored side.
            Grid {
                columns: root.vertical ? 1 : win.count
                spacing: win.gap

                anchors.top: root.atTop ? parent.top : undefined
                anchors.bottom: root.atTop ? undefined : parent.bottom
                anchors.left: root.atLeft ? parent.left : undefined
                anchors.right: root.atRight ? parent.right : undefined
                anchors.horizontalCenter: (root.atLeft || root.atRight) ? undefined : parent.horizontalCenter

                Repeater {
                    model: root.osds

                    Loader {
                        id: osdLoader

                        required property var modelData

                        visible: root.previewing || !!(osdLoader.modelData && osdLoader.modelData.shouldShowOsd)
                        sourceComponent: osdLoader.modelData ? osdLoader.modelData.box : null

                        Binding {
                            target: osdLoader.item
                            property: "uiScale"
                            value: win.uiScale
                            when: !!osdLoader.item
                        }
                    }
                }
            }
        }
    }
}

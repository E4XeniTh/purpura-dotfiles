import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config
import "../common"
import "../settings"

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
//
// Right-click opens a menu like the volume control's: every monitor but the
// primary - by its port, or the name Settings > Display gave it - each with
// a checkbox saying whether it's on, then Display Settings and Night Light
// Settings. Clicking a monitor switches it on or off at once and closes the
// menu, as picking a device closes the volume control's; the switch carries
// on without it, and reopening shows the checkbox it asked for until it's
// done. A switch is the Display tab's own right click + Apply: that file is
// loaded out of sight for as long as it takes (see monitorSwitch below), so
// workspace pins, windows rescued off a monitor going dark and its
// remembered mode all come out exactly as they would there.
Rectangle {
    id: root

    property real uiScale: 1.0
    property var dashboard: null
    // Set from Bar.qml, so the right-click menu opens on this bar's monitor.
    property var screen: null

    // General > Shell settings' "Brightness Control" checkbox (see
    // ShellSettings.qml/Bar.qml) - a user-level show/hide independent of
    // whether the primary monitor actually supports brightness control at
    // all (see controllable/detecting below).
    property bool showBrightnessControl: true

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
    visible: root.showBrightnessControl && (root.detecting || root.controllable)
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

    // ---------------- right-click menu ----------------
    property bool menuOpen: false
    // Snapshot taken as it opens - see VolumeControl.qml's menuMarginLeft.
    property real menuMarginLeft: 0

    function closeMenu() {
        root.menuOpen = false
    }

    // Every monitor Hyprland knows, switched off ones included - read while
    // the menu's open, and once more after a switch.
    property var monitors: []
    property bool monitorsKnown: false
    readonly property var otherMonitors: root.monitors.filter(m => m.name !== root.targetMonitor)
    // What a click asked a monitor to be - what its checkbox shows until the
    // switch is over and Hyprland's been asked again.
    property var requested: ({})

    function monitorOn(m) {
        return root.requested[m.name] !== undefined ? root.requested[m.name] : !m.disabled
    }

    // What Settings > Display calls it - its port unless it's been renamed.
    AliasStore {
        id: monitorNames
        file: "monitoraliases.json"
    }

    function refreshMonitors() {
        monitorsProcess.running = false
        monitorsProcess.running = true
    }

    Process {
        id: monitorsProcess
        command: ["hyprctl", "-j", "monitors", "all"]

        // Whether this read began with no switch under way - only such a
        // read says where the switches left things.
        property bool switchFree: false
        onStarted: monitorsProcess.switchFree = !monitorSwitch.active

        stdout: StdioCollector {
            onStreamFinished: {
                let parsed
                try {
                    parsed = JSON.parse(text)
                } catch (e) {
                    return
                }
                root.monitors = parsed
                root.monitorsKnown = true
                if (monitorsProcess.switchFree && !monitorSwitch.active) root.requested = ({})
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.menuOpen
        onTriggered: root.refreshMonitors()
    }

    // Switches waiting for monitorSwitch to load.
    property var pendingSwitches: ({})

    function toggleMonitor(m) {
        const on = !root.monitorOn(m)
        root.requested = Object.assign({}, root.requested, { [m.name]: on })
        root.pendingSwitches = Object.assign({}, root.pendingSwitches, { [m.name]: on })
        switchLifetime.restart()
        if (monitorSwitch.item) root.sendSwitches()
        else monitorSwitch.active = true
    }

    function sendSwitches() {
        for (const name in root.pendingSwitches) monitorSwitch.item.setEnabledNow(name, root.pendingSwitches[name])
        root.pendingSwitches = ({})
        switchIdle.restart()
    }

    // The Display tab (ScreenSettings.qml), out of sight - it only exists
    // while Settings is open otherwise. Sized only so its layout has
    // something to work with; nothing of it is ever shown.
    Item {
        visible: false
        width: Config.scaled(800, root.uiScale)
        height: Config.scaled(600, root.uiScale)

        Loader {
            id: monitorSwitch

            anchors.fill: parent
            active: false

            sourceComponent: ScreenSettings {
                uiScale: root.uiScale
                primaryMonitor: root.dashboard ? root.dashboard.primaryMonitor : ""
                dashboardRoot: root.dashboard
            }

            // Left inactive - opening it as a tab would restart the read
            // of monitors.json it has just begun (see setEnabledNow()).
            onLoaded: root.sendSwitches()
            onStatusChanged: {
                if (monitorSwitch.status === Loader.Error) root.unloadSwitch()
            }
        }
    }

    // Unloaded again once its Apply has nothing left to do.
    Timer {
        id: switchIdle
        interval: 1500
        repeat: true
        onTriggered: {
            if (Object.keys(root.pendingSwitches).length > 0) return
            if (monitorSwitch.item && monitorSwitch.item.applying) return
            root.unloadSwitch()
        }
    }

    // Or after half a minute regardless, should a switch never finish (a
    // monitor unplugged midway, hyprctl not answering).
    Timer {
        id: switchLifetime
        interval: 30000
        onTriggered: root.unloadSwitch()
    }

    // The checkboxes go back to what Hyprland says once it's been asked.
    function unloadSwitch() {
        switchIdle.stop()
        switchLifetime.stop()
        monitorSwitch.active = false
        root.pendingSwitches = ({})
        root.refreshMonitors()
    }

    // Right-click anywhere on the widget - only the right button, so it
    // never competes with the bar's own dragging or the wheel above.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: {
            root.menuMarginLeft = Config.scaled(10, root.uiScale) + root.x
            root.menuOpen = !root.menuOpen
        }
    }

    // Same box-grow-open PanelWindow popup as VolumeControl.qml's and
    // Tray.qml's menus, anchored below this widget.
    PanelWindow {
        id: menuWindow

        screen: root.screen
        visible: root.menuOpen

        WlrLayershell.namespace: "brightnessMenu"
        WlrLayershell.layer: WlrLayer.Overlay

        exclusiveZone: 0

        anchors {
            top: true
            left: true
        }

        margins {
            top: Config.scaled(4, root.uiScale)
            left: root.menuMarginLeft
        }

        implicitWidth: root.width
        implicitHeight: Math.max(menuColumn.height + Config.scaled(10, root.uiScale), 1)

        color: "transparent"

        Rectangle {
            id: menuBox

            width: 0
            height: Config.scaled(2, root.uiScale)
            color: Config.fillcolor

            states: [
                State {
                    name: "horizontal"

                    PropertyChanges {
                        target: menuBox
                        width: menuWindow.implicitWidth
                        height: Config.scaled(3, root.uiScale)
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: menuBox
                        width: menuWindow.implicitWidth
                        height: menuWindow.implicitHeight
                    }
                }
            ]

            transitions: [
                Transition {
                    NumberAnimation {
                        properties: "width,height"
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            ]

            Item {
                anchors.fill: parent
                anchors.topMargin: Config.scaled(5, root.uiScale)
                anchors.bottomMargin: Config.scaled(5, root.uiScale)
                clip: true

                Column {
                    id: menuColumn
                    width: menuWindow.implicitWidth

                    // ---------------- the other monitors ----------------
                    Repeater {
                        model: ScriptModel {
                            values: root.otherMonitors
                            objectProp: "name"
                        }

                        delegate: Item {
                            id: monitorEntry

                            required property var modelData

                            readonly property bool isOn: root.monitorOn(monitorEntry.modelData)

                            width: menuColumn.width
                            height: Config.scaled(32, root.uiScale)

                            Rectangle {
                                anchors.fill: parent
                                color: monitorMouse.containsMouse ? Config.fgcolordark : "transparent"
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    right: monitorBox.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Config.scaled(10, root.uiScale)
                                    rightMargin: Config.scaled(10, root.uiScale)
                                }
                                text: monitorNames.name(monitorEntry.modelData.name, monitorEntry.modelData.name)
                                textFormat: Text.PlainText
                                color: monitorEntry.isOn ? Config.fgcolor : Config.fgcolordarklight
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                elide: Text.ElideRight
                            }

                            // On or off - CheckRow.qml's box.
                            Rectangle {
                                id: monitorBox
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: Config.scaled(10, root.uiScale)
                                }
                                width: Config.scaled(20, root.uiScale)
                                height: width
                                color: monitorEntry.isOn ? Config.fgcolor : Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: Config.fgcolor
                            }

                            MouseArea {
                                id: monitorMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.toggleMonitor(monitorEntry.modelData)
                                    root.closeMenu()
                                }
                            }
                        }
                    }

                    Item {
                        visible: root.monitorsKnown && root.otherMonitors.length === 0
                        width: menuColumn.width
                        height: Config.scaled(32, root.uiScale)

                        Text {
                            anchors {
                                fill: parent
                                leftMargin: Config.scaled(10, root.uiScale)
                                rightMargin: Config.scaled(10, root.uiScale)
                            }
                            verticalAlignment: Text.AlignVCenter
                            text: "No other monitors"
                            color: Config.fgcolordarklight
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.italic: true
                        }
                    }

                    // ---------------- separator ----------------
                    // Tray.qml's thin, inset menu separator.
                    Item {
                        width: menuColumn.width
                        height: Config.scaled(9, root.uiScale)

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Config.scaled(8, root.uiScale)
                                rightMargin: Config.scaled(8, root.uiScale)
                            }
                            height: Config.scaled(1, root.uiScale)
                            color: Config.fgcolordark
                        }
                    }

                    // ---------------- Display settings ----------------
                    Item {
                        width: menuColumn.width
                        height: Config.scaled(32, root.uiScale)

                        Rectangle {
                            anchors.fill: parent
                            color: displaySettingsMouse.containsMouse ? Config.fgcolordark : "transparent"

                            Text {
                                anchors {
                                    fill: parent
                                    leftMargin: Config.scaled(10, root.uiScale)
                                    rightMargin: Config.scaled(10, root.uiScale)
                                }
                                verticalAlignment: Text.AlignVCenter
                                text: "Display Settings"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: displaySettingsMouse
                                anchors.fill: parent
                                hoverEnabled: true

                                // The Display tab (2) - see SettingsScreen.qml's
                                // requestedInitialTab.
                                onClicked: {
                                    root.closeMenu()
                                    if (root.dashboard && root.dashboard.settingsScreen) {
                                        root.dashboard.settingsScreen.requestedInitialTab = 2
                                        root.dashboard.settingsScreen.open = true
                                    }
                                }
                            }
                        }
                    }

                    // ---------------- Night Light settings ----------------
                    Item {
                        width: menuColumn.width
                        height: Config.scaled(32, root.uiScale)

                        Rectangle {
                            anchors.fill: parent
                            color: nightLightMouse.containsMouse ? Config.fgcolordark : "transparent"

                            Text {
                                anchors {
                                    fill: parent
                                    leftMargin: Config.scaled(10, root.uiScale)
                                    rightMargin: Config.scaled(10, root.uiScale)
                                }
                                verticalAlignment: Text.AlignVCenter
                                text: "Night Light Settings"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: nightLightMouse
                                anchors.fill: parent
                                hoverEnabled: true

                                // General tab (0), Night Light section (3) -
                                // see SettingsScreen.qml's requestedInitialTab
                                // and requestedShellCategory.
                                onClicked: {
                                    root.closeMenu()
                                    if (root.dashboard && root.dashboard.settingsScreen) {
                                        root.dashboard.settingsScreen.requestedInitialTab = 0
                                        root.dashboard.settingsScreen.requestedShellCategory = 3
                                        root.dashboard.settingsScreen.open = true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: Config.scaled(2, root.uiScale)
                border.color: Config.fgcolor
                z: 10
            }
        }

        onVisibleChanged: {
            if (visible) {
                menuBox.width = 0
                menuBox.height = Config.scaled(4, root.uiScale)
                menuBox.state = "horizontal"
                menuOpenTimer.start()
            }
        }

        Timer {
            id: menuOpenTimer
            // The transition's length, so the width finishes before the
            // height starts.
            interval: 200
            repeat: false
            onTriggered: menuBox.state = "open"
        }
    }
}

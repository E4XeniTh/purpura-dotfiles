import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "settings"
import "../../Config.js" as Config

// Fullscreen settings screen - one dimmed (and, via hyprland.lua's own
// "settingsscreen" layer_rule, compositor-blurred) overlay window per
// connected monitor, mirroring LockScreen.qml/PowerMenu.qml's own
// multi-monitor treatment. Opened from the Settings button on
// Dashboard.qml's power/lock row, replacing the old per-icon popup
// settings panels (Sound/Network/Bluetooth/Display) with tabs inside
// one shared card instead. Only the primary monitor's window shows the
// actual tabbed card (see the Loader/isPrimary gating below); every
// other screen just shows the dimmed/blurred backdrop.
Scope {
    id: root

    property bool open: false

    // Fed in from shell.qml (Dashboard's own primaryMonitor/audio
    // selection/identifying) - same reasoning as PowerMenu.qml/
    // LockScreen.qml's own `dashboard` property: these settings tabs
    // used to live inside Dashboard.qml itself and read/write its root
    // Scope directly, so this keeps that exact same wiring now that
    // they're hosted here instead.
    property var dashboard: null

    readonly property string effectivePrimaryName: {
        const preferred = root.dashboard ? root.dashboard.primaryMonitor : ""
        if (preferred && Quickshell.screens.some(s => s.name === preferred)) return preferred
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    // 0 = Shell, 1 = Sound, 2 = Network, 3 = Bluetooth, 4 = Display.
    property int currentTab: 0

    IpcHandler {
        target: "settingsscreen"

        function toggle(): void { root.open = !root.open }
        function show(): void { root.open = true }
        function hide(): void { root.open = false }
    }

    GlobalShortcut {
        name: "settingsscreen"
        onPressed: {
            root.open = !root.open
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            property var modelData
            screen: modelData

            readonly property bool isPrimary: modelData.name === root.effectivePrimaryName

            // panelWidth is just the card's own physical width - wider
            // than Dashboard's own dashWidth since this is a dedicated
            // full screen now instead of a slim dropdown column. uiScale
            // stays on Dashboard.qml's own dashWidth-based formula
            // though (NOT derived from this wider panelWidth) so every
            // font/icon/border here renders at the same density as the
            // rest of the shell instead of visibly thicker/bigger.
            readonly property real dashWidth: modelData.width * 0.42
            readonly property real uiScale: Math.max(0.6, Math.min(1.8, dashWidth / 800))
            readonly property real panelWidth: Math.min(modelData.width * 0.7, 1200)

            // Opens right below the bar, same offset Dashboard.qml's own
            // dashWindow gets automatically from the compositor pushing
            // it out of the bar's reserved exclusive zone - this window
            // can't rely on that (WlrLayershell.exclusiveZone is -1, so
            // it ignores every exclusive zone including the bar's, which
            // is what lets it dim the strip of screen behind the bar
            // too), so the offset is computed by hand instead: Bar's own
            // top margin (10) + height (48) + Dashboard's own extra gap
            // (4) below that.
            readonly property real topOffset: Config.scaled(62, uiScale)

            WlrLayershell.namespace: "settingsscreen"
            WlrLayershell.layer: WlrLayer.Overlay

            // Only the primary window ever asks for keyboard input -
            // every other screen's window gets none at all, matching
            // LockScreen.qml/PowerMenu.qml's own convention. OnDemand
            // (not Exclusive) since ScreenSettings' resolution/position
            // fields are the only thing here that ever actually types -
            // see ScreenSettings.qml for where this used to come from
            // its own standalone SettingsPanel popup instead.
            WlrLayershell.keyboardFocus: win.isPrimary ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            WlrLayershell.exclusiveZone: -1

            visible: root.open

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"

            Rectangle {
                id: background

                anchors.fill: parent

                color: Qt.rgba(0, 0, 0, 0.55)

                opacity: 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                    }
                }
            }

            // Click outside the card to dismiss - mirrors PowerMenu.qml.
            // A click that lands INSIDE the card but on blank space (not
            // on any actual control) is swallowed by box's own catch-all
            // MouseArea below instead of reaching this one, so a stray
            // click near a tab button doesn't close the whole screen.
            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
            }

            // Only the primary screen gets the actual tabbed card -
            // gated on root.open too (not just isPrimary), same as
            // PowerMenu.qml/LockScreen.qml's own Loader, so this tears
            // down and rebuilds fresh every time the screen opens.
            Loader {
                id: panelLoader

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: win.topOffset
                }
                active: win.isPrimary && root.open
                sourceComponent: panelComponent

                property real panelWidth: win.panelWidth
                property real uiScale: win.uiScale
                // Same gap below as topOffset leaves above, so the card
                // reads as evenly framed rather than flush with the
                // bottom edge - mirrors SettingsPanel.qml's own
                // maxAvailableHeight convention.
                property real maxHeight: win.screen ? win.screen.height - win.topOffset * 2 : 900
            }

            onVisibleChanged: {
                if (visible) {
                    background.opacity = 0
                    background.opacity = 1
                } else {
                    root.currentTab = 0
                }
            }
        }
    }

    Component {
        id: panelComponent

        FocusScope {
            id: panelScope

            anchors.fill: parent

            readonly property real panelWidth: parent.panelWidth
            readonly property real uiScale: parent.uiScale
            readonly property real maxHeight: parent.maxHeight

            Keys.onEscapePressed: root.open = false

            Rectangle {
                id: box

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                }

                width: 0
                height: 4

                color: Config.fillcolor

                // Swallows any click that lands on blank card space (the
                // tab bar's own margins/gaps between buttons, or empty
                // space below a short tab's content) before it can fall
                // through to the full-window "click outside closes"
                // MouseArea sitting behind this card - without it, a
                // click just barely missing a tab button closed the
                // whole screen instead of doing nothing. Declared first
                // so it sits below every real control in z-order and
                // never steals a click meant for one of them.
                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                }

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: box

                            width: panelScope.panelWidth
                            height: 2
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: box

                            width: panelScope.panelWidth
                            // Always the full maxHeight, not whatever the
                            // active tab's own content happens to need -
                            // otherwise the window visibly grows/shrinks
                            // every time a different tab is picked. See
                            // tabFlick below, which is sized to match this
                            // exactly so the two never disagree.
                            height: panelScope.maxHeight
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

                    Column {
                        id: cardColumn

                        width: panelScope.panelWidth

                        // ---------------- tab bar ----------------
                        Item {
                            id: tabBar

                            width: parent.width
                            height: Config.scaled(56, panelScope.uiScale)

                            readonly property real margins: Config.scaled(10, panelScope.uiScale)
                            readonly property real spacing: Config.scaled(10, panelScope.uiScale)
                            readonly property real tabWidth: (width - margins * 2 - spacing * 4) / 5

                            Row {
                                anchors {
                                    fill: parent
                                    margins: tabBar.margins
                                }
                                spacing: tabBar.spacing

                                Repeater {
                                    model: [
                                        { label: "Shell", icon: "preferences-system-symbolic" },
                                        { label: "Sound", icon: "audio-volume-high-symbolic" },
                                        { label: "Network", icon: "network-wired-symbolic" },
                                        { label: "Bluetooth", icon: "network-bluetooth" },
                                        { label: "Display", icon: "video-display-symbolic" }
                                    ]

                                    delegate: DashCard {
                                        id: tabCard

                                        required property var modelData
                                        required property int index

                                        width: tabBar.tabWidth
                                        height: tabBar.height - tabBar.margins * 2
                                        uiScale: panelScope.uiScale
                                        color: tabMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                        border.color: root.currentTab === tabCard.index ? Config.fgcolorlight : Config.fgcolor

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: Config.scaled(8, panelScope.uiScale)

                                            // Icon + its ColorOverlay are
                                            // wrapped in a plain, explicitly
                                            // sized Item rather than sitting
                                            // directly as Row children - a
                                            // positioner like Row assigns its
                                            // children's x directly, which
                                            // silently fights/breaks an
                                            // anchors.fill binding on a
                                            // direct child (confirmed live:
                                            // the ColorOverlay ended up
                                            // drawn on top of the label
                                            // text instead of over the icon,
                                            // undefined precedence between
                                            // the two). Anchoring inside
                                            // this wrapper instead is safe
                                            // since the wrapper itself is
                                            // the well-behaved Row child.
                                            Item {
                                                width: Config.scaled(20, panelScope.uiScale)
                                                height: Config.scaled(20, panelScope.uiScale)
                                                anchors.verticalCenter: parent.verticalCenter

                                                IconImage {
                                                    id: tabIcon
                                                    anchors.fill: parent
                                                    source: Quickshell.iconPath(tabCard.modelData.icon)
                                                }

                                                ColorOverlay {
                                                    anchors.fill: tabIcon
                                                    source: tabIcon
                                                    color: tabCard.border.color
                                                }
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: tabCard.modelData.label
                                                color: tabCard.border.color
                                                font.family: Config.fontfamily
                                                font.pixelSize: Config.scaled(14, panelScope.uiScale)
                                                font.bold: true
                                            }
                                        }

                                        MouseArea {
                                            id: tabMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: root.currentTab = tabCard.index
                                        }
                                    }
                                }
                            }
                        }

                        // ---------------- divider ----------------
                        Rectangle {
                            id: divider
                            width: parent.width
                            height: Config.scaled(2, panelScope.uiScale)
                            color: Config.fgcolor
                        }

                        // ---------------- active tab's content ----------------
                        // Fixed to fill exactly what's left of maxHeight,
                        // not the active tab's own content height - see
                        // the box's "open" state above for why (a shorter
                        // tab just leaves blank space below it instead of
                        // shrinking the window). Each tab is anchors.fill'd
                        // to this instead of sizing itself, so its own
                        // internal lists can stretch down to meet it -
                        // any overflow within a tab is handled by that
                        // tab's own ListView clipping/scrolling, not by an
                        // outer Flickable here.
                        Item {
                            id: tabHost

                            width: parent.width
                            height: panelScope.maxHeight - tabBar.height - divider.height

                            ShellSettings {
                                id: shellTab
                                anchors.fill: parent
                                visible: root.currentTab === 0
                                panelWidth: panelScope.panelWidth
                                uiScale: panelScope.uiScale
                                active: root.open && root.currentTab === 0
                            }

                            AudioSettings {
                                id: audioTab
                                anchors.fill: parent
                                visible: root.currentTab === 1
                                panelWidth: panelScope.panelWidth
                                uiScale: panelScope.uiScale
                                active: root.open && root.currentTab === 1
                                selectedSinkId: root.dashboard ? root.dashboard.audioSelectedSinkId : null
                                selectedSourceId: root.dashboard ? root.dashboard.audioSelectedSourceId : null
                                onSinkSelected: (id) => { if (root.dashboard) root.dashboard.audioSelectedSinkId = id }
                                onSourceSelected: (id) => { if (root.dashboard) root.dashboard.audioSelectedSourceId = id }
                            }

                            NetworkSettings {
                                id: networkTab
                                anchors.fill: parent
                                visible: root.currentTab === 2
                                panelWidth: panelScope.panelWidth
                                uiScale: panelScope.uiScale
                                active: root.open && root.currentTab === 2
                            }

                            BluetoothSettings {
                                id: bluetoothTab
                                anchors.fill: parent
                                visible: root.currentTab === 3
                                panelWidth: panelScope.panelWidth
                                uiScale: panelScope.uiScale
                                active: root.open && root.currentTab === 3
                            }

                            ScreenSettings {
                                id: screenTab
                                anchors.fill: parent
                                visible: root.currentTab === 4
                                panelWidth: panelScope.panelWidth
                                uiScale: panelScope.uiScale
                                active: root.open && root.currentTab === 4
                                primaryMonitor: root.dashboard ? root.dashboard.primaryMonitor : ""
                                dashboardRoot: root.dashboard
                                onPrimarySelected: (name) => { if (root.dashboard) root.dashboard.primaryMonitor = name }
                                onIdentifyingChanged: { if (root.dashboard) root.dashboard.identifying = screenTab.identifying }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.width: Config.scaled(2, panelScope.uiScale)
                    border.color: Config.fgcolor

                    z: 10
                }
            }

            // Runs fresh every time this component is loaded (see the
            // Loader above, gated on root.open) - mirrors PowerMenu.qml/
            // LockScreen.qml's own Component.onCompleted reset-then-open
            // sequence, so the box always plays its open animation from
            // scratch and always starts back on the Sound tab.
            Component.onCompleted: {
                root.currentTab = 0

                box.width = 0
                box.height = 2

                box.state = "horizontal"

                panelScope.forceActiveFocus()

                openTimer.start()
            }

            Timer {
                id: openTimer

                interval: 300
                repeat: false

                onTriggered: {
                    box.state = "open"
                }
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Power menu overlay - one dimmed (and, via hyprland.lua's own
// "powermenu" layer_rule, compositor-blurred) window per connected
// monitor, mirroring LockScreen.qml's own multi-monitor treatment - the
// whole desktop should read as "something modal is open" instead of
// just one display of it, which is all a single non-multi-monitor
// PanelWindow ever gave the blur rule a surface to apply to. Only the
// primary monitor's window actually shows the interactive button row
// (see the Loader/isPrimary gating below); every other screen just
// shows the dimmed/blurred backdrop with nothing to click.
Scope {
    id: root

    property bool open: false

    // Fed in from shell.qml (Dashboard's own primaryMonitor) - same
    // "resolve to whichever screen is actually there" fallback
    // LockScreen.qml/Bar.qml already use, so this never ends up with no
    // window able to take keyboard focus (or every window
    // simultaneously) if primaryMonitor points at something not
    // actually connected.
    property var dashboard: null

    readonly property string effectivePrimaryName: {
        const preferred = root.dashboard ? root.dashboard.primaryMonitor : ""
        if (preferred && Quickshell.screens.some(s => s.name === preferred)) return preferred
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { root.open = !root.open }
        function show(): void { root.open = true }
        function hide(): void { root.open = false }
    }

    GlobalShortcut {
        name: "powermenu"

        onPressed: {
            root.open = true
        }
    }

    // Which button is highlighted for keyboard selection (left/right
    // arrow cycles, enter/return activates) - reset to the first one
    // every time the menu opens (see the PanelWindow's onVisibleChanged
    // below), rather than remembering wherever it was left last time.
    property int selectedIndex: 0

    // One entry per button - a plain data model driving a Repeater below
    // instead of four near-identical hand-duplicated Items (the
    // previous version's own comment noted why: this Quickshell's QML
    // engine rejects the `component Name: Item {}` declaration syntax
    // outright at boot). A Repeater's own `delegate:` is a different,
    // always-supported mechanism, so this refactor is unrelated to that
    // limitation.
    readonly property var actions: [
        {
            icon: "system-shutdown-symbolic",
            trigger: () => Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl poweroff"])
        },
        {
            icon: "system-reboot-symbolic",
            trigger: () => Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl reboot"])
        },
        {
            icon: "system-suspend-symbolic",
            trigger: () => Quickshell.execDetached(["systemctl", "suspend"])
        },
        {
            icon: "system-log-out-symbolic",
            trigger: () => Quickshell.execDetached(["hyprshutdown", "--post-cmd", "hyprctl dispatch 'hl.dsp.exit()'"])
        }
    ]

    function activateSelected() {
        const entry = root.actions[root.selectedIndex]
        if (!entry) return
        root.open = false
        entry.trigger()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            property var modelData
            screen: modelData

            readonly property bool isPrimary: modelData.name === root.effectivePrimaryName

            WlrLayershell.namespace: "powermenu"
            WlrLayershell.layer: WlrLayer.Overlay

            // Only the primary window ever asks for exclusive keyboard
            // input - every other screen's window gets none at all,
            // matching LockScreen.qml/WorkspaceOsd.qml's own convention
            // for a non-interactive secondary-screen overlay.
            WlrLayershell.keyboardFocus: win.isPrimary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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

            // Click outside the box to dismiss - buttons inside the
            // loaded menu box sit on top and consume their own clicks
            // first, so this only fires on the dimmed backdrop. Harmless
            // on a non-primary screen too (nothing else ever sits above
            // it there), just closes the menu the same way.
            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
            }

            // Only the primary screen gets the actual interactive menu -
            // gated on root.open too (not just isPrimary), same as
            // LockScreen.qml's own login-prompt Loader, so this tears
            // down and rebuilds fresh every time the menu opens rather
            // than one long-lived instance whose box/selection state
            // would need its own separate reset signal.
            Loader {
                anchors.fill: parent
                active: win.isPrimary && root.open
                sourceComponent: menuBoxComponent
            }

            onVisibleChanged: {
                if (visible) {
                    background.opacity = 0
                    background.opacity = 1
                }
            }
        }
    }

    Component {
        id: menuBoxComponent

        FocusScope {
            id: menuScope
            anchors.fill: parent

            Keys.onLeftPressed: root.selectedIndex = (root.selectedIndex + root.actions.length - 1) % root.actions.length
            Keys.onRightPressed: root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
            Keys.onReturnPressed: root.activateSelected()
            Keys.onEnterPressed: root.activateSelected()
            Keys.onEscapePressed: root.open = false

            Rectangle {
                id: menuBox

                anchors.centerIn: parent

                width: 0
                height: 4

                color: Qt.rgba(0, 0, 0, 1)

                states: [

                    State {

                        name: "horizontal"

                        PropertyChanges {

                            target: menuBox

                            width: 725
                            height: 2

                        }
                    },


                    State {

                        name: "open"

                        PropertyChanges {

                            target: menuBox

                            width: 725
                            height: 200

                        }
                    }

                ]



                transitions: [

                    Transition {

                        NumberAnimation {

                            properties: "width,height"

                            duration: 350

                            easing.type: Easing.OutCubic

                        }

                    }

                ]

                Item {

                    id: contentMask

                    anchors.fill: parent

                    clip: true

                    Row {

                        anchors.centerIn: parent

                        spacing: 24

                        Repeater {
                            model: root.actions

                            Item {
                                id: buttonItem
                                required property var modelData
                                required property int index

                                width: 150
                                height: 150

                                readonly property bool isSelected: buttonItem.index === root.selectedIndex

                                Rectangle {
                                    anchors.fill: parent

                                    radius: 0
                                    color: buttonMouseArea.containsMouse ? Config.fgcolorhover : "transparent"

                                    // Selected (keyboard-highlighted)
                                    // button gets a thicker, lighter
                                    // border so left/right arrow
                                    // navigation is visible without a
                                    // mouse anywhere near the menu.
                                    border.width: buttonItem.isSelected ? 3 : 2
                                    border.color: buttonItem.isSelected ? Config.fgcolorlight : Config.fgcolor

                                    IconImage {
                                        id: buttonIcon
                                        anchors.centerIn: parent
                                        implicitSize: 88
                                        source: Quickshell.iconPath(buttonItem.modelData.icon)
                                    }

                                    ColorOverlay {
                                        anchors.fill: buttonIcon
                                        source: buttonIcon
                                        color: Config.fgcolor
                                    }
                                }

                                MouseArea {
                                    id: buttonMouseArea

                                    anchors.fill: parent
                                    hoverEnabled: true

                                    // Hovering a button also moves the
                                    // keyboard selection onto it, so the
                                    // two selection mechanisms never
                                    // visibly disagree about which
                                    // button is "current".
                                    onEntered: root.selectedIndex = buttonItem.index

                                    onClicked: {
                                        root.selectedIndex = buttonItem.index
                                        root.activateSelected()
                                    }
                                }
                            }
                        }

                    }

                }

                Rectangle {

                    anchors.fill: parent

                    color: "transparent"

                    border.color: Config.fgcolor
                    border.width: 2

                    z: 10

                }

            }

            // Runs fresh every time this component is loaded (see the
            // Loader above, gated on root.open) - not just once ever -
            // so a selection left on some other button from the
            // previous time the menu was open never carries into the
            // next one, and the open animation always plays from
            // scratch. Mirrors LockScreen.qml's own loginPromptComponent
            // Component.onCompleted reset-then-open sequence.
            Component.onCompleted: {
                root.selectedIndex = 0

                menuBox.width = 0
                menuBox.height = 2

                menuBox.state = "horizontal"

                menuScope.forceActiveFocus()

                openTimer.start()
            }

            Timer {
                id: openTimer

                // Must match the transition's duration above, so phase 1
                // (width) fully finishes before phase 2 (height) starts.
                interval: 350

                repeat: false

                onTriggered: {
                    menuBox.state = "open"
                }
            }
        }
    }
}

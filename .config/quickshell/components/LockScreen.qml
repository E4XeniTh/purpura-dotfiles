import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Lock screen - one dimmed (and, via hyprland.lua's own "lockscreen"
// layer_rule, compositor-blurred) overlay window per connected monitor,
// not just whichever single screen Quickshell used to pick for this
// when it was a single un-multi-monitored PanelWindow - the whole
// desktop should read as locked, not just one display of it.
//
// Only the primary monitor's window actually loads the interactive
// avatar/password prompt (see the Loader below, gated on isPrimary) -
// every other screen just shows the dimmed/blurred background with
// nothing to click or type into. This also keeps keyboard focus
// unambiguous: only one WlrLayershell surface here ever requests
// Exclusive input at a time, since every surface demanding it
// simultaneously would be undefined.
Scope {
    id: root

    // Settings > Shell's global UI Scale (UiScale.qml), from shell.qml -
    // multiplied into every window's Config.uiScale below.
    property real shellScale: 1.0

    property bool locked: false

    // Fed in from shell.qml (Dashboard's own primaryMonitor) - see
    // effectivePrimaryName below for what happens if this is never
    // wired up, or points at a monitor that isn't actually connected.
    property var dashboard: null

    // Always resolves to some currently-connected screen's name -
    // Dashboard's primaryMonitor when it's wired up and actually
    // connected, otherwise whichever screen happens to be first - so
    // exactly one window is ever primary, never none (or, worse, every
    // window at once).
    readonly property string effectivePrimaryName: {
        const preferred = root.dashboard ? root.dashboard.primaryMonitor : ""
        if (preferred && Quickshell.screens.some(s => s.name === preferred)) return preferred
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    IpcHandler {
        target: "lockscreen"

        // Lock only - no unlock/toggle. A real unlock has to go through
        // PAM (attemptLogin/unlock() below); exposing an IPC unlock here
        // would be a permanent, unauthenticated bypass reachable from
        // any local process, unlike the explicitly-temporary debug
        // GlobalShortcut right below.
        function lock(): void { root.locked = true }
    }

    GlobalShortcut {
        name: "lockscreen"

        onPressed: {
            root.locked = true
        }
    }

    // TEMPORARY DEBUG ESCAPE HATCH - remove once PamContext auth is
    // confirmed working. This bypasses the password check entirely: it
    // just flips the lock state directly, so anyone with this keybind
    // can unlock the screen with no password at all. Fine while testing
    // lock/unlock in isolation from PAM; not something to leave bound
    // permanently.
    GlobalShortcut {
        name: "lockscreen-toggle-debug"

        onPressed: {
            root.locked = !root.locked
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            property var modelData
            screen: modelData

            readonly property bool isPrimary: modelData.name === root.effectivePrimaryName

            // The shell-wide per-screen scale (see Config.uiScale).
            readonly property real uiScale: Config.uiScale(modelData, root.shellScale)

            WlrLayershell.namespace: "lockscreen"

            WlrLayershell.layer: WlrLayer.Overlay

            // Only the primary window ever asks for exclusive keyboard
            // input - every other screen's window gets none at all,
            // matching WorkspaceOsd.qml's own click-through OSD windows.
            WlrLayershell.keyboardFocus: win.isPrimary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            WlrLayershell.exclusiveZone: -1

            visible: root.locked

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

            // Only the primary screen gets the actual avatar/password
            // prompt - active is gated on root.locked too (not just
            // isPrimary), so this Loader tears the whole thing down on
            // unlock and builds it fresh on the next lock, the same way
            // Component.onCompleted below resets it - rather than one
            // long-lived instance whose reset would need its own
            // separate signal plumbing.
            Loader {
                anchors.fill: parent
                active: win.isPrimary && root.locked
                sourceComponent: loginPromptComponent

                property real uiScale: win.uiScale
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
        id: loginPromptComponent

        Item {
            id: prompt

            anchors.fill: parent

            // From the Loader above (its window's screen).
            readonly property real uiScale: parent.uiScale

            property bool wrongPassword: false

            Rectangle {
                id: loginBox

                property real shakeOffset: 0

                anchors {
                    centerIn: parent
                    horizontalCenterOffset: shakeOffset
                }

                width: 0
                height: Config.scaled(2, prompt.uiScale)

                color: Qt.rgba(0, 0, 0, 1)

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: loginBox

                            width: Config.scaled(400, prompt.uiScale)
                            height: Config.scaled(2, prompt.uiScale)
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: loginBox

                            width: Config.scaled(400, prompt.uiScale)
                            height: Config.scaled(400, prompt.uiScale)
                        }
                    }

                ]

                transitions: [

                    Transition {

                        NumberAnimation {
                            properties: "width,height"
                            duration: 500
                            easing.type: Easing.OutCubic
                        }

                    }

                ]

                Item {
                    id: contentMask

                    anchors.fill: parent

                    clip: true

                    Column {
                        id: loginContent

                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            verticalCenter: parent.verticalCenter
                        }

                        spacing: Config.scaled(20, prompt.uiScale)

                        Image {
                            id: avatar

                            source: "file://" + Quickshell.env("HOME") + "/.face"

                            width: Config.scaled(192, prompt.uiScale)
                            height: Config.scaled(192, prompt.uiScale)

                            anchors.horizontalCenter: parent.horizontalCenter

                            fillMode: Image.PreserveAspectCrop

                            clip: true

                            Rectangle {
                                anchors.fill: parent

                                color: "transparent"

                                border.color: prompt.wrongPassword ? "#ff3b3b" : Config.fgcolor
                                border.width: Config.scaled(2, prompt.uiScale)

                                radius: 0
                            }
                        }

                        TextField {
                            id: passwordInput

                            focus: true

                            width: Config.scaled(240, prompt.uiScale)
                            height: Config.scaled(30, prompt.uiScale)

                            // The system's default font, scaled with the
                            // screen like the rest of the prompt.
                            font.pointSize: (Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize : 10) * prompt.uiScale

                            placeholderText: authProcess.running ? "Checking..." : "Password"

                            echoMode: TextInput.Password

                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter

                            enabled: !authProcess.running

                            background: Rectangle {
                                color: Qt.rgba(0, 0, 0, 0.3)

                                border.color: prompt.wrongPassword ? "#ff3b3b" : Config.fgcolor
                                border.width: Config.scaled(2, prompt.uiScale)

                                radius: 0

                                Behavior on border.color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            Keys.onReturnPressed: {
                                attemptLogin(passwordInput.text)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.color: prompt.wrongPassword ? "#ff3b3b" : Config.fgcolor
                    border.width: Config.scaled(2, prompt.uiScale)

                    z: 10

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }
                }

            }

            Process {
                id: authProcess

                stdinEnabled: true

                onExited: (exitCode, exitStatus) => {
                    if (exitCode === 0) {
                        unlock()
                    } else {
                        failedLogin()
                    }
                }
            }

            SequentialAnimation {
                id: shakeAnim

                NumberAnimation { target: loginBox; property: "shakeOffset"; to: -Config.scaled(12, prompt.uiScale); duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: loginBox; property: "shakeOffset"; to: Config.scaled(12, prompt.uiScale); duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: loginBox; property: "shakeOffset"; to: -Config.scaled(8, prompt.uiScale); duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: loginBox; property: "shakeOffset"; to: 0; duration: 60; easing.type: Easing.OutQuad }
            }

            Timer {
                id: wrongFlashTimer

                interval: 400
                repeat: false

                onTriggered: prompt.wrongPassword = false
            }

            Timer {
                id: openTimer

                interval: 500

                repeat: false

                onTriggered: {
                    loginBox.state = "open"
                }
            }

            // Runs fresh every time this component is loaded (see the
            // Loader above) - i.e. once per lock, not just once ever -
            // so a leftover typed password or a login box stuck in its
            // "open" state from the previous session never carries
            // over into the next one.
            Component.onCompleted: {
                loginBox.width = 0
                loginBox.height = Config.scaled(2, prompt.uiScale)

                passwordInput.clear()

                loginBox.state = "horizontal"

                openTimer.start()
            }

            function attemptLogin(password) {
                if (password.length === 0 || authProcess.running) {
                    return
                }

                authProcess.command = [Quickshell.shellDir + "/helpers/auth", Quickshell.env("USER")]
                authProcess.running = true
                authProcess.write(password + "\n")
            }

            function unlock() {
                passwordInput.clear()

                root.locked = false
            }

            function failedLogin() {
                passwordInput.clear()

                prompt.wrongPassword = true
                wrongFlashTimer.restart()
                shakeAnim.restart()

                passwordInput.forceActiveFocus()
            }
        }
    }
}

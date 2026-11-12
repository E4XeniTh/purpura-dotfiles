import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Config.js" as Config

// Lock screen - a real Wayland session lock (ext-session-lock-v1, through
// Quickshell's WlSessionLock). While it's up, Hyprland gives input to the
// lock's own surfaces and nothing else: no keybind gets through except
// the ones hyprland.lua marks `locked = true` (volume, brightness, media
// keys). If the shell dies while locked, the session stays locked. The
// lock makes one surface per monitor by itself.
//
// Hyprland paints black behind a lock unless told otherwise. The dimmed,
// blurred desktop behind this one is misc.session_lock_xray (keep drawing
// the workspaces underneath) plus misc.session_lock_blur, which this sets
// itself - see applyLockLook().
//
// Only the primary monitor shows the avatar/password prompt, with the
// clock above it and what's playing beside it. The keyboard follows the
// mouse from monitor to monitor while locked, though, so every monitor
// takes typing into the one shared password and checks it on Enter.
Scope {
    id: root

    // Settings > Shell's global UI Scale (UiScale.qml), from shell.qml -
    // multiplied into every surface's Config.uiScale below.
    property real shellScale: 1.0

    // Read by Bar.qml; PowerMenu.qml locks by setting it.
    property alias locked: persist.locked

    // Fed in from shell.qml (Dashboard's own primaryMonitor) - see
    // effectivePrimaryName below for what happens if this is never
    // wired up, or points at a monitor that isn't actually connected.
    property var dashboard: null

    // Survives a config reload, which a plain property wouldn't: reloading
    // with this back at false would unlock the session. It has to stay the
    // first object in here - a Scope reloads its children in order, so
    // this is restored before the lock below takes over from the old one.
    PersistentProperties {
        id: persist
        reloadableId: "lockscreen"

        property bool locked: false
    }

    // Always resolves to some currently-connected screen's name -
    // Dashboard's primaryMonitor when it's wired up and actually
    // connected, otherwise whichever screen happens to be first - so
    // exactly one surface is ever primary, never none (or, worse, every
    // surface at once).
    readonly property string effectivePrimaryName: {
        const preferred = root.dashboard ? root.dashboard.primaryMonitor : ""
        if (preferred && Quickshell.screens.some(s => s.name === preferred)) return preferred
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    function lock() { persist.locked = true }

    IpcHandler {
        target: "lockscreen"

        // Lock only - no unlock/toggle. The only way out is the password
        // check (attemptLogin() below); an IPC unlock would be a
        // permanent, unauthenticated bypass reachable from any local
        // process.
        function lock(): void { root.lock() }

        // helpers/purpura-update.sh waits for this to be false before
        // installing anything that would reload the shell under the lock.
        function isLocked(): bool { return persist.locked }
    }

    GlobalShortcut {
        name: "lockscreen"

        onPressed: root.lock()
    }

    // ---------------- the look ----------------
    // Runtime config, so it's back after every `hyprctl reload` too - a
    // reload resets anything hyprland.lua itself doesn't set.
    function applyLockLook() {
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ misc = { session_lock_xray = true, session_lock_blur = true } })"])
    }

    Component.onCompleted: root.applyLockLook()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.applyLockLook()
        }
    }

    // ---------------- the lock ----------------
    WlSessionLock {
        id: sessionLock

        locked: persist.locked

        // Hyprland turns a lock down when another locker already holds
        // the session. The shell shouldn't then carry on as if locked.
        onLockStateChanged: {
            if (!sessionLock.locked && persist.locked) root.lockFailed()
        }

        WlSessionLockSurface {
            id: lockSurface

            // Transparent, so the desktop shows through the dim below
            // (see applyLockLook()).
            color: "transparent"

            readonly property bool isPrimary: !!lockSurface.screen && lockSurface.screen.name === root.effectivePrimaryName

            // The shell-wide per-screen scale (see Config.uiScale).
            readonly property real uiScale: Config.uiScale(lockSurface.screen, root.shellScale)

            Rectangle {
                anchors.fill: parent

                color: Qt.rgba(0, 0, 0, 0.55)

                NumberAnimation on opacity {
                    from: 0
                    to: 1
                    duration: 250
                }
            }

            // Typing on a monitor without the prompt - invisible, but the
            // keyboard is here whenever the mouse is (see the header).
            TextInput {
                id: keySink

                width: 1
                height: 1
                opacity: 0

                focus: !lockSurface.isPrimary
                readOnly: root.checking
                echoMode: TextInput.Password

                onTextEdited: root.password = keySink.text

                Keys.onReturnPressed: root.attemptLogin()
                Keys.onEnterPressed: root.attemptLogin()
            }

            Connections {
                target: root

                function onPasswordChanged() {
                    if (keySink.text !== root.password) keySink.text = root.password
                }
            }

            // Active on the primary monitor only. Every lock makes its
            // surfaces afresh, so this starts over with every lock too.
            Loader {
                anchors.fill: parent

                active: lockSurface.isPrimary
                focus: lockSurface.isPrimary

                sourceComponent: loginPromptComponent

                property real uiScale: lockSurface.uiScale
            }
        }
    }

    // A lock that can't be asked for at all (no ext-session-lock-v1, or
    // this shell already holding one) is dropped without a signal, so it
    // gets checked once the request has settled.
    Connections {
        target: persist

        function onLockedChanged() {
            root.password = ""
            root.wrongPassword = false
            if (persist.locked) Qt.callLater(root.checkLockTaken)
        }
    }

    function checkLockTaken() {
        if (persist.locked && !sessionLock.locked) root.lockFailed()
    }

    // Says so out loud: walking away from a screen you think is locked
    // is worse than the lock itself not coming up.
    function lockFailed() {
        persist.locked = false
        Quickshell.execDetached([
            "notify-send", "-u", "critical", "-a", "Lock screen", "-i", "system-lock-screen-symbolic",
            "Couldn't lock the screen",
            "Hyprland turned the lock down - another lock screen may already be running."
        ])
    }

    // ---------------- password ----------------
    // Shared by every monitor's surface (see the header).
    property string password: ""
    property bool wrongPassword: false
    readonly property bool checking: authProcess.running

    // The prompt shakes on it.
    signal authFailed()

    function attemptLogin() {
        if (root.password.length === 0 || authProcess.running) {
            return
        }

        authProcess.command = [Quickshell.shellDir + "/helpers/auth", Quickshell.env("USER")]
        authProcess.running = true
        authProcess.write(root.password + "\n")
        // Gone from every field while it's checked, which also shows the
        // prompt's "Checking..." placeholder.
        root.password = ""
    }

    function unlock() {
        root.password = ""
        persist.locked = false
    }

    function failLogin() {
        root.password = ""
        root.wrongPassword = true
        wrongFlashTimer.restart()
        root.authFailed()
    }

    Process {
        id: authProcess

        stdinEnabled: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.unlock()
            } else {
                root.failLogin()
            }
        }
    }

    Timer {
        id: wrongFlashTimer

        interval: 400
        repeat: false

        onTriggered: root.wrongPassword = false
    }

    // ---------------- the prompt (primary monitor) ----------------
    Component {
        id: loginPromptComponent

        Item {
            id: prompt

            anchors.fill: parent

            // From the Loader above (its surface's screen).
            readonly property real uiScale: parent.uiScale

            // The login box's full size, and the space between it and the
            // boxes beside it - which are laid out against the box's full
            // size and stay put while it shakes.
            readonly property real boxSize: Config.scaled(400, prompt.uiScale)
            readonly property real sideBoxHeight: Math.round(prompt.boxSize / 4)
            readonly property real gap: Config.scaled(12, prompt.uiScale)

            // Set once the login box has finished opening: the clock and
            // what's playing only open after that.
            property bool extrasOpen: false

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

                            width: prompt.boxSize
                            height: Config.scaled(2, prompt.uiScale)
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: loginBox

                            width: prompt.boxSize
                            height: prompt.boxSize
                        }
                    }

                ]

                transitions: [

                    Transition {
                        to: "horizontal"

                        NumberAnimation {
                            properties: "width,height"
                            duration: 500
                            easing.type: Easing.OutCubic
                        }
                    },

                    Transition {
                        to: "open"

                        SequentialAnimation {
                            NumberAnimation {
                                properties: "width,height"
                                duration: 500
                                easing.type: Easing.OutCubic
                            }

                            ScriptAction {
                                script: prompt.extrasOpen = true
                            }
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

                                border.color: root.wrongPassword ? "#ff3b3b" : Config.fgcolor
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

                            placeholderText: root.checking ? "Checking..." : "Password"

                            echoMode: TextInput.Password

                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter

                            // Read-only rather than disabled while it's
                            // checked, so it never loses the keyboard.
                            readOnly: root.checking

                            background: Rectangle {
                                color: Qt.rgba(0, 0, 0, 0.3)

                                border.color: root.wrongPassword ? "#ff3b3b" : Config.fgcolor
                                border.width: Config.scaled(2, prompt.uiScale)

                                radius: 0

                                Behavior on border.color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            onTextEdited: root.password = passwordInput.text

                            Keys.onReturnPressed: root.attemptLogin()
                            Keys.onEnterPressed: root.attemptLogin()
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.color: root.wrongPassword ? "#ff3b3b" : Config.fgcolor
                    border.width: Config.scaled(2, prompt.uiScale)

                    z: 10

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }
                }

            }

            // ---------------- clock ----------------
            // As wide as the login box and a quarter of its height, just
            // above it, opening upward from its bottom edge.
            Rectangle {
                id: clockBox

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.verticalCenter
                    bottomMargin: prompt.boxSize / 2 + prompt.gap
                }

                width: prompt.boxSize
                height: prompt.extrasOpen ? prompt.sideBoxHeight : 0
                visible: height > 0

                color: Qt.rgba(0, 0, 0, 1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }

                // Full size and pinned to the edge the box opens from, so
                // opening uncovers it rather than squeezing it - the same
                // way the login box uncovers its own content.
                Item {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: prompt.sideBoxHeight

                    Text {
                        id: clockText

                        anchors.centerIn: parent

                        text: Qt.formatDateTime(new Date(), "hh:mm")
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(56, prompt.uiScale)
                        font.bold: true
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.color: Config.fgcolor
                    border.width: Config.scaled(2, prompt.uiScale)

                    z: 10
                }
            }

            Timer {
                interval: 1000
                running: true
                repeat: true

                onTriggered: clockText.text = Qt.formatDateTime(new Date(), "hh:mm")
            }

            // ---------------- what's playing ----------------
            // Just right of the login box, the clock's size, while
            // something's playing - see LockMedia.qml. Loaded rather than
            // written in here so that MPRIS going wrong only costs that box.
            Loader {
                anchors {
                    left: parent.horizontalCenter
                    leftMargin: prompt.boxSize / 2 + prompt.gap
                    verticalCenter: parent.verticalCenter
                }

                source: "LockMedia.qml"

                // Read by LockMedia.qml.
                property real uiScale: prompt.uiScale
                property real openWidth: prompt.boxSize
                property real boxHeight: prompt.sideBoxHeight
                property bool allowed: prompt.extrasOpen
            }

            SequentialAnimation {
                id: shakeAnim

                NumberAnimation { target: loginBox; property: "shakeOffset"; to: -Config.scaled(12, prompt.uiScale); duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: loginBox; property: "shakeOffset"; to: Config.scaled(12, prompt.uiScale); duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: loginBox; property: "shakeOffset"; to: -Config.scaled(8, prompt.uiScale); duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: loginBox; property: "shakeOffset"; to: 0; duration: 60; easing.type: Easing.OutQuad }
            }

            Connections {
                target: root

                function onPasswordChanged() {
                    if (passwordInput.text !== root.password) passwordInput.text = root.password
                }

                function onAuthFailed() {
                    shakeAnim.restart()
                    passwordInput.forceActiveFocus()
                }
            }

            Timer {
                id: openTimer

                interval: 500

                repeat: false

                onTriggered: {
                    loginBox.state = "open"
                }
            }

            // Runs fresh every time this is loaded (see the Loader above) -
            // i.e. once per lock - so the boxes open again with every lock.
            Component.onCompleted: {
                loginBox.width = 0
                loginBox.height = Config.scaled(2, prompt.uiScale)

                loginBox.state = "horizontal"

                openTimer.start()

                passwordInput.text = root.password
                passwordInput.forceActiveFocus()
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects

PanelWindow {

    id: root

    WlrLayershell.namespace: "lockscreen"

    WlrLayershell.layer: WlrLayer.Overlay

    WlrLayershell.keyboardFocus: WlrLayershell.Exclusive

    WlrLayershell.exclusiveZone: -1

    visible: LockState.locked

    property bool wrongPassword: false

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

        color: Qt.rgba(0,0,0,0.35)

        opacity: 0

        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
    }


    Rectangle {

        id: loginBox

        property real shakeOffset: 0

        anchors {
            centerIn: parent
            horizontalCenterOffset: shakeOffset
        }

        width: 0
        height: 4

        color: Qt.rgba(0,0,0,1)

        states: [

            State {

                name: "horizontal"

                PropertyChanges {

                    target: loginBox

                    width: 400
                    height: 2

                }
            },


            State {

                name: "open"

                PropertyChanges {

                    target: loginBox

                    width:400
                    height:400

                }
            }

        ]



        transitions: [

            Transition {

                NumberAnimation {

                    properties:"width,height"

                    duration:500

                    easing.type:Easing.OutCubic

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

                spacing: 20


                Image {

                    id: avatar

                    source: "file://" + Quickshell.env("HOME") + "/.face"

                    width: 192
                    height: 192

                    anchors.horizontalCenter: parent.horizontalCenter

                    fillMode: Image.PreserveAspectCrop

                    clip: true


                    Rectangle {

                        anchors.fill: parent

                        color: "transparent"

                        border.color: root.wrongPassword ? "#ff3b3b" : Theme.fgcolor
                        border.width: 2

                        radius: 0
                    }
                }


                TextField {

                    id: passwordInput

                    focus:true

                    width: 240
                    height: 30

                    placeholderText: authProcess.running ? "Checking..." : "Password"

                    echoMode: TextInput.Password

                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter

                    enabled: !authProcess.running


                    background: Rectangle {

                        color: Qt.rgba(0,0,0,0.3)

                        border.color: root.wrongPassword ? "#ff3b3b" : Theme.fgcolor
                        border.width: 2

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

            border.color: root.wrongPassword ? "#ff3b3b" : Theme.fgcolor
            border.width: 2

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

        NumberAnimation { target: loginBox; property: "shakeOffset"; to: -12; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: loginBox; property: "shakeOffset"; to: 12; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: loginBox; property: "shakeOffset"; to: -8; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: loginBox; property: "shakeOffset"; to: 0; duration: 60; easing.type: Easing.OutQuad }
    }

    Timer {

        id: wrongFlashTimer

        interval: 400
        repeat: false

        onTriggered: root.wrongPassword = false
    }


    onVisibleChanged: {

        if (visible) {

            loginBox.width = 0
            loginBox.height = 2

            background.opacity = 0

            passwordInput.clear()


            background.opacity = 1

            loginBox.state = "horizontal"

            openTimer.start()

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

        LockState.locked = false

    }

    function failedLogin() {

        passwordInput.clear()

        root.wrongPassword = true
        wrongFlashTimer.restart()
        shakeAnim.restart()

        passwordInput.forceActiveFocus()

    }

    function openLockScreen() {

        loginBox.state = ""

        loginBox.width = 0
        loginBox.height = 2

        background.opacity = 0

        passwordInput.clear()

        LockState.locked = true

    }

}

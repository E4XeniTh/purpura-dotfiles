import QtQuick
import QtQuick.Controls
import Quickshell
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

        anchors.centerIn: parent

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

                    source: "file:///home/fayelia/.face"

                    width: 192
                    height: 192

                    anchors.horizontalCenter: parent.horizontalCenter

                    fillMode: Image.PreserveAspectCrop

                    clip: true


                    Rectangle {

                        anchors.fill: parent

                        color: "transparent"

                        border.color: Theme.fgcolor
                        border.width: 2

                        radius: 0
                    }
                }


                TextField {

                    id: passwordInput

                    focus:true

                    width: 240
                    height: 30

                    placeholderText: "Password"

                    echoMode: TextInput.Password

                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter


                    background: Rectangle {

                        color: Qt.rgba(0,0,0,0.3)

                        border.color: Theme.fgcolor
                        border.width: 2

                        radius: 0
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

            border.color: Theme.fgcolor
            border.width: 2

            z: 10
        }

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

        console.log("Trying password")

        // temporary testing
        if (password === "jaje") {

            unlock()
        }
        else{

            failedLogin()}

    }

    function unlock() {

        passwordInput.clear()

        LockState.locked = false

    }

    function failedLogin() {

        passwordInput.clear()

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

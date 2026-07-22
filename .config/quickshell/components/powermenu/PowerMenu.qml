import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"
import "../../Config.js" as Config

PanelWindow {

    id: root

    WlrLayershell.namespace: "powermenu"

    WlrLayershell.layer: WlrLayer.Overlay

    WlrLayershell.keyboardFocus: WlrLayershell.Exclusive

    WlrLayershell.exclusiveZone: -1

    visible: PowerMenuState.open

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


    // Click outside the box to dismiss. Buttons inside menuBox sit on top
    // and consume their own clicks first, so this only fires on the
    // dimmed backdrop.
    MouseArea {
        anchors.fill: parent
        onClicked: PowerMenuState.open = false
    }


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

                PowerMenuButton {
                    icon: "system-shutdown-symbolic"
                    onActivated: {
                        PowerMenuState.open = false
                        shutdownProcess.running = true
                    }
                }

                PowerMenuButton {
                    icon: "system-reboot-symbolic"
                    onActivated: {
                        PowerMenuState.open = false
                        rebootProcess.running = true
                    }
                }

                PowerMenuButton {
                    icon: "system-suspend-symbolic"
                    onActivated: {
                        PowerMenuState.open = false
                        suspendProcess.running = true
                    }
                }

                PowerMenuButton {
                    icon: "system-log-out-symbolic"
                    onActivated: {
                        PowerMenuState.open = false
                        logoutProcess.running = true
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


    onVisibleChanged: {

        if (visible) {

            menuBox.width = 0
            menuBox.height = 2

            background.opacity = 0


            background.opacity = 1

            menuBox.state = "horizontal"

            openTimer.start()

        }

    }


    Timer {

        id: openTimer

        // Must match the transition's duration below, so phase 1 (width)
        // fully finishes before phase 2 (height) starts.
        interval: 350

        repeat: false

        onTriggered: {

            menuBox.state = "open"

        }

    }

    Process {
        id: shutdownProcess
        command: ["systemctl", "poweroff"]
    }

    Process {
        id: rebootProcess
        command: ["systemctl", "reboot"]
    }

    Process {
        id: suspendProcess
        command: ["systemctl", "suspend"]
    }

    Process {
        id: logoutProcess
        command: ["hyprctl", "dispatch", "exit"]
    }

}

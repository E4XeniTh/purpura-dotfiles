import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import "../Config.js" as Config

PanelWindow {

    id: root

    property bool open: false

    WlrLayershell.namespace: "powermenu"

    WlrLayershell.layer: WlrLayer.Overlay

    WlrLayershell.keyboardFocus: WlrLayershell.Exclusive

    WlrLayershell.exclusiveZone: -1

    visible: root.open

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

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
        onClicked: root.open = false
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

                // Large icon-only buttons. Duplicated rather than pulled
                // into a shared inline `component` - this Quickshell's
                // QML engine doesn't support that syntax (rejected with a
                // hard "Syntax error" at boot, taking the whole shell
                // down with it).

                Item {
                    width: 150
                    height: 150

                    Rectangle {
                        anchors.fill: parent

                        radius: 0
                        color: shutdownMouseArea.containsMouse ? Config.fgcolorhover : "transparent"

                        border.width: 2
                        border.color: Config.fgcolor

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 88
                            source: Quickshell.iconPath("system-shutdown-symbolic")
                        }
                    }

                    MouseArea {
                        id: shutdownMouseArea

                        anchors.fill: parent
                        hoverEnabled: true

                        onClicked: {
                            root.open = false
                            shutdownProcess.running = true
                        }
                    }
                }

                Item {
                    width: 150
                    height: 150

                    Rectangle {
                        anchors.fill: parent

                        radius: 0
                        color: rebootMouseArea.containsMouse ? Config.fgcolorhover : "transparent"

                        border.width: 2
                        border.color: Config.fgcolor

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 88
                            source: Quickshell.iconPath("system-reboot-symbolic")
                        }
                    }

                    MouseArea {
                        id: rebootMouseArea

                        anchors.fill: parent
                        hoverEnabled: true

                        onClicked: {
                            root.open = false
                            rebootProcess.running = true
                        }
                    }
                }

                Item {
                    width: 150
                    height: 150

                    Rectangle {
                        anchors.fill: parent

                        radius: 0
                        color: suspendMouseArea.containsMouse ? Config.fgcolorhover : "transparent"

                        border.width: 2
                        border.color: Config.fgcolor

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 88
                            source: Quickshell.iconPath("system-suspend-symbolic")
                        }
                    }

                    MouseArea {
                        id: suspendMouseArea

                        anchors.fill: parent
                        hoverEnabled: true

                        onClicked: {
                            root.open = false
                            suspendProcess.running = true
                        }
                    }
                }

                Item {
                    width: 150
                    height: 150

                    Rectangle {
                        anchors.fill: parent

                        radius: 0
                        color: logoutMouseArea.containsMouse ? Config.fgcolorhover : "transparent"

                        border.width: 2
                        border.color: Config.fgcolor

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 88
                            source: Quickshell.iconPath("system-log-out-symbolic")
                        }
                    }

                    MouseArea {
                        id: logoutMouseArea

                        anchors.fill: parent
                        hoverEnabled: true

                        onClicked: {
                            root.open = false
                            logoutProcess.running = true
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

        // hyprshutdown's own internal Hyprland-exit call still uses the
        // legacy `hyprctl dispatch exit` string dispatcher, which doesn't
        // reach anything under Lua config mode - --post-cmd's value has
        // to be ONE array element (no shell here to rejoin split words
        // back into a single argument the way a shell command line would).
        command: ["hyprshutdown", "--post-cmd", "hyprctl dispatch 'hl.dsp.exit()'"]
    }

}

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

import "../../Config.js" as Config

Scope {
    id: root
    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true
        }
    }

    PanelWindow {
        anchors { top: true; right: true }
        margins { top: 10; right: 10 }

        implicitWidth: 380
        implicitHeight: Math.max(1, column.implicitHeight)
        color: Config.fillcolor

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            Repeater {
                model: server.trackedNotifications
                delegate: Rectangle {
                    id: card
                    required property var modelData

                    Timer {
                        running: card.modelData.urgency !== NotificationUrgency.Critical
                        interval: Config.notificationtimeout
                        onTriggered: card.modelData.dismiss()
                    }

                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: Config.fillcolor
                    border.width: 2
                    border.color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor

                    RowLayout {
                        id: layout
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Image {
                            Layout.preferredHeight: 36
                            Layout.preferredWidth: 36
                            Layout.alignment: Qt.AlignTop
                            fillMode: Image.PreserveAspectFit
                            visible: source.toString() !== ""
                            source: card.modelData.image || card.modelData. appIcon || ""
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary
                                color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor
                                font.family: "monospace"
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: card.modelData.body
                                color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolorlight
                                font.family: "monospace"
                                font.pixelSize: 14 - 2
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: card.modelData.dismiss()
                    }

                }
            }
        }
    }

    property bool centerOpen: false

    IpcHandler {
        target: "notificationpanel"
        function toggle() : void { root.centerOpen = !root.centerOpen }
        function show() : void { root.centerOpen = true }
        function hide() : void { root.centerOpen = false }
    }

    PanelWindow {
        margins { top: 10; right: 10 }
        anchors { top: true; right: true }
        visible: root.centerOpen
        width: panelBox.width
        height: panelBox.height
        color: "transparent"
        Rectangle {
            id: panelBox
            visible: root.centerOpen
            color: "transparent"
            width: centerCol.width
            height: centerCol.implicitHeight
            Rectangle {
                id: mainRect
                anchors.fill: parent
                color: Config.fillcolor
                border.width: 2
                border.color: Config.fgcolor
                clip: true

                ColumnLayout {
                    id: centerCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 10
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: Config.fgcolor
                            font.family: "monospace"
                            font.pixelSize: 14
                            font.bold: true
                        }

                        // TODO: "Clear all" needs a real history list to
                        // clear - trackedNotifications only holds the
                        // still-active ones shown as toasts, not a
                        // persistent history. Referenced `history` here
                        // was never defined anywhere, so this was dead on
                        // arrival; re-add once history tracking exists.
                    }
                }

            }

            states: [

                State {
                    name: "spread"

                    PropertyChanges {
                        target: panelBox

                        width: 400
                        height: 2
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: panelBox

                        width: 400
                        height: centerCol.implicitHeight
                    }
                }

            ]

            transitions: [

                Transition {

                    NumberAnimation {

                        properties: "width,height"

                        duration: 250

                        easing.type: Easing.OutCubic

                    }

                }

            ]

            onVisibleChanged: {
                if (visible) {
                    panelBox.width = 0
                    panelBox.height = 4

                    panelBox.state = "spread"
                    centerOpenTimer.start()
                }
            }

            Timer {
                id: centerOpenTimer

                // Must match the transition's duration above, so phase 1
                // (width) fully finishes before phase 2 (height) starts.
                interval: 250
                repeat: false

                onTriggered: {
                    panelBox.state = "open"
                }
            }
        }
    }
}

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

import "../Config.js" as Config

Scope {
    id: root
    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true

            // Snapshot the fields we need as plain values rather than
            // keeping a reference to `n` itself - once it's dismissed
            // (timeout or click) the live Notification object is no
            // longer guaranteed to be valid, but history needs to
            // outlive that.
            historyModel.insert(0, {
                summary: n.summary,
                body: n.body,
                appIcon: n.appIcon,
                image: n.image,
                urgency: n.urgency
            })

            while (historyModel.count > 50) {
                historyModel.remove(historyModel.count - 1)
            }
        }
    }

    // Persistent notification history for the center panel - separate
    // from server.trackedNotifications, which only holds the still-active
    // notifications shown as toasts above and loses entries the moment
    // they're dismissed or time out.
    ListModel {
        id: historyModel
    }

    PanelWindow {
        visible: !root.centerOpen
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
                    // Grows for wrapped multi-line bodies instead of
                    // clipping them to a fixed 60px card.
                    Layout.preferredHeight: Math.max(60, toastContentColumn.implicitHeight + 20)
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
                            id: toastContentColumn
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary
                                color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: card.modelData.body
                                color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolorlight
                                font.family: Config.fontfamily
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
        margins { top: 4; right: 10 }
        anchors { top: true; right: true }
        visible: root.centerOpen

        // Fixed/content-derived size, NOT bound to panelBox's currently-
        // animating width/height. Binding the window itself to the live
        // animation meant every frame resized the actual Wayland surface
        // (a real compositor round-trip, not just a repaint), which is
        // what made the panel feel like it was lagging behind while
        // spreading. Dashboard/PowerMenu/Tray never do this - their outer
        // window is sized once from the full/settled content, and only
        // an internal Rectangle (panelBox here) animates via clip.
        implicitWidth: 400
        implicitHeight: Math.max(centerCol.implicitHeight, 1)

        color: "transparent"
        Rectangle {
            id: panelBox
            visible: root.centerOpen
            color: "transparent"
            width: centerCol.width
            height: centerCol.implicitHeight

            // No anchor at all defaults to the window's top-left, so as
            // width grew the box appeared to grow rightward from a fixed
            // left edge. Anchoring the right edge to the window's right
            // instead makes it grow from the right, matching every other
            // panel in this shell (all anchored top+right themselves).
            anchors.right: parent.right
            Rectangle {
                id: mainRect
                anchors.fill: parent
                color: Config.fillcolor
                border.width: 2
                border.color: Config.fgcolor
                clip: true

                ColumnLayout {
                    id: centerCol

                    // Fixed width instead of anchoring left+right to
                    // mainRect: mainRect.anchors.fill is panelBox, and
                    // panelBox's own width/height are themselves driven
                    // by centerCol (below/states). Anchoring centerCol's
                    // width to that same chain re-creates the circular
                    // dependency the height fix already had to break -
                    // width just wasn't obviously circular the same way
                    // until you trace it through. A literal width removes
                    // any coupling in either direction: 400 (panelBox's
                    // fixed open width) minus 10px margin on each side.
                    width: 380

                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: 10
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Text {
                            visible: historyModel.count > 0
                            text: "Clear all"
                            color: clearAllMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: 12

                            MouseArea {
                                id: clearAllMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: historyModel.clear()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: historyModel.count === 0
                        text: "No notifications"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        id: historyList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 420)
                        visible: historyModel.count > 0
                        clip: true
                        spacing: 8
                        model: historyModel
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: historyList.width
                            // Grows for wrapped multi-line bodies instead
                            // of clipping them to a fixed 60px card.
                            height: Math.max(60, historyContentColumn.implicitHeight + 20)
                            color: Config.fillcolor
                            border.width: 2
                            border.color: model.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Image {
                                    Layout.preferredHeight: 36
                                    Layout.preferredWidth: 36
                                    Layout.alignment: Qt.AlignTop
                                    fillMode: Image.PreserveAspectFit
                                    visible: source.toString() !== ""
                                    source: model.image || model.appIcon || ""
                                }

                                ColumnLayout {
                                    id: historyContentColumn
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: model.summary
                                        color: model.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: 14
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: model.body
                                        color: model.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolorlight
                                        font.family: Config.fontfamily
                                        font.pixelSize: 14 - 2
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: historyModel.remove(index)
                            }
                        }
                    }

                    // Small breathing room below the list - centerCol's
                    // implicitHeight otherwise leaves content sitting
                    // flush against mainRect's bottom border.
                    Item {
                        height: 8
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

                        duration: 300

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
                interval: 300
                repeat: false

                onTriggered: {
                    panelBox.state = "open"
                }
            }
        }
    }
}

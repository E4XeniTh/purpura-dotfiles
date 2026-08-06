import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
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
            // outlive that. notificationId is kept specifically so this
            // row can be found again below.
            const notifId = n.id
            historyModel.insert(0, {
                notificationId: notifId,
                summary: n.summary,
                body: n.body,
                appIcon: n.appIcon,
                image: n.image,
                urgency: n.urgency
            })

            while (historyModel.count > 50) {
                historyModel.remove(historyModel.count - 1)
            }

            // Removing the history row from INSIDE a MouseArea click
            // handler (two earlier attempts, both still reportedly not
            // working) meant replicating "was this actually a genuine
            // user dismissal" per call site, and depending on exactly
            // when card.modelData was read relative to dismiss()/
            // invoke() possibly tearing it down. Listening to the
            // notification's OWN closed(reason) signal instead is
            // authoritative and single-sourced: dismiss() (right click,
            // left click, and whatever invoke() does for a non-resident
            // notification) reports Dismissed here no matter which of
            // those actually fired it or in what order; expire() (the
            // auto-timeout Timer below, switched from dismiss() to
            // expire() specifically for this) reports Expired instead,
            // which deliberately leaves the history row alone - a
            // notification nobody interacted with is exactly what
            // history is for. Disconnects itself after firing once,
            // since a Notification only ever closes a single time.
            function onClosed(reason) {
                n.closed.disconnect(onClosed)
                if (reason === NotificationCloseReason.Dismissed) {
                    root.removeHistoryByNotificationId(notifId)
                }
            }
            n.closed.connect(onClosed)
        }
    }

    // Persistent notification history for the center panel - separate
    // from server.trackedNotifications, which only holds the still-active
    // notifications shown as toasts above and loses entries the moment
    // they're dismissed or time out.
    ListModel {
        id: historyModel
    }

    // Closes the panel on "Clear all" / on deleting the last remaining
    // entry, matching Clipboard.qml's own close-when-empty behavior.
    function clearAllHistory() {
        historyModel.clear()
        root.centerOpen = false
    }

    function removeHistoryEntry(index) {
        historyModel.remove(index)
        if (historyModel.count === 0) root.centerOpen = false
    }

    // Clicking a toast (either button, see cardMouseArea below) counts
    // as having dealt with it, so its history row goes away too instead
    // of sitting there duplicating what the popup already handled - a
    // notification that just times out unclicked is left in history
    // untouched, that's the whole point of it being there.
    function removeHistoryByNotificationId(notifId) {
        // Number(...) both sides - ListModel's dynamic-role storage and
        // the live Notification.id property aren't guaranteed to come
        // back as the exact same JS numeric subtype, and === doesn't
        // coerce.
        const target = Number(notifId)
        for (let i = 0; i < historyModel.count; i++) {
            if (Number(historyModel.get(i).notificationId) === target) {
                historyModel.remove(i)
                break
            }
        }
        if (historyModel.count === 0) root.centerOpen = false
    }

    PanelWindow {
        visible: !root.centerOpen
        anchors { top: true; right: true }
        margins { top: 4; right: 10 }

        implicitWidth: 380
        implicitHeight: Math.max(1, column.implicitHeight)
        color: "transparent"

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 4

            Repeater {
                model: server.trackedNotifications
                delegate: Rectangle {
                    id: card
                    required property var modelData

                    Timer {
                        running: card.modelData.urgency !== NotificationUrgency.Critical
                        interval: Config.notificationtimeout
                        // expire(), not dismiss() - reports
                        // NotificationCloseReason.Expired via closed(),
                        // which onNotification's listener (above)
                        // deliberately does NOT treat as a reason to
                        // clear the history row. dismiss() is reserved
                        // for an actual user action (see cardMouseArea
                        // below), which DOES clear it.
                        onTriggered: card.modelData.expire()
                    }

                    Layout.fillWidth: true
                    // Grows for wrapped multi-line bodies instead of
                    // clipping them to a fixed 60px card.
                    Layout.preferredHeight: Math.max(60, toastContentColumn.implicitHeight + 20)
                    color: cardMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
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

                    // Right click: dismiss only. Left click: "give
                    // attention" like a real desktop notification would
                    // (invoke the sender-registered default action - e.g.
                    // Discord focusing the sender - if it has one), then
                    // dismiss either way and close the center panel. Only
                    // works here, not from a history row below: the
                    // default action requires the original sender still
                    // be alive and tracked, which is exactly what
                    // history's own snapshot-only entries deliberately
                    // don't keep a live reference to (see onNotification
                    // above). Neither branch removes the history row
                    // directly anymore - dismiss() below triggers
                    // closed(Dismissed), which onNotification's own
                    // listener reacts to on its own (see there for why).
                    MouseArea {
                        id: cardMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                card.modelData.dismiss()
                                return
                            }
                            const defaultAction = card.modelData.actions.find(a => a.identifier === "default")
                            if (defaultAction) defaultAction.invoke()
                            card.modelData.dismiss()
                            root.centerOpen = false
                        }
                    }

                }
            }
        }
    }

    property bool centerOpen: false

    onCenterOpenChanged: {
        if (root.centerOpen) {
            autoCloseTimer.restart()
        } else {
            autoCloseTimer.stop()
        }
    }

    // Auto-close after 5s with the mouse not over the panel -
    // HoverHandler on mainRect (below) restarts this to a fresh 5s every
    // time the mouse leaves, and stops it while the mouse is present, so
    // it only ever fires after 5 full uninterrupted seconds of no mouse
    // activity in the panel.
    Timer {
        id: autoCloseTimer
        interval: 5000
        repeat: false
        onTriggered: root.centerOpen = false
    }

    IpcHandler {
        target: "notificationpanel"
        function toggle() : void { root.centerOpen = !root.centerOpen }
        function show() : void { root.centerOpen = true }
        function hide() : void { root.centerOpen = false }
    }

    GlobalShortcut {
        name: "notifications"
        onPressed: {
            root.centerOpen = !root.centerOpen
        }
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

                // Purely observational - doesn't grab/consume anything
                // the way a MouseArea would, so it coexists fine with
                // every entry's own MouseArea underneath.
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            autoCloseTimer.stop()
                        } else {
                            autoCloseTimer.restart()
                        }
                    }
                }

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
                            font.pixelSize: 14

                            MouseArea {
                                id: clearAllMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.clearAllHistory()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: historyModel.count === 0
                        text: "No notifications
                        "
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: 14
                        font.bold: true
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
                            color: historyMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
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

                            // No live Notification object survives into
                            // history (see onNotification above), so
                            // there's no default action left to invoke
                            // here - left click can only remove + close,
                            // not "give attention" the way a still-live
                            // toast card (above) can.
                            MouseArea {
                                id: historyMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    root.removeHistoryEntry(index)
                                    if (mouse.button === Qt.LeftButton) root.centerOpen = false
                                }
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

            // Scoped to the actual spread->open state change only - an
            // unscoped Transition here also animates EVERY later change
            // to the "open" state's own height binding
            // (centerCol.implicitHeight, which moves every time a
            // history row is removed), not just the initial open.
            // That's what was producing a border-color flash: a
            // Rectangle's border briefly fills its whole area once an
            // animated resize shrinks it small enough that there's no
            // room left for the fill color to show between the strokes.
            // Content-driven size changes now happen instantly instead
            // of animating through that, while the deliberate open
            // sequence below is untouched.
            transitions: [

                Transition {

                    from: "spread"
                    to: "open"

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

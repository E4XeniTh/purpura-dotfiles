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

    // Settings > Shell's global UI Scale (UiScale.qml), from shell.qml -
    // multiplied into every window's Config.uiScale below.
    property real shellScale: 1.0

    // EdgeGaps.qml: lines this up with the bar's right end.
    property var edgeGaps: null

    // Right-click on Bar.qml's notification button toggles this - true
    // mutes POPUPS specifically (see onNotification below), history
    // keeps recording regardless, same as how a real "do not disturb"
    // toggle is expected to behave (mute the interruption, still log
    // it for later).
    property bool notificationsDisabled: false

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
                urgency: n.urgency,
                screenshotFile: root.screenshotFileFrom(n.hints)
            })

            while (historyModel.count > 50) {
                root.discardScreenshot(historyModel.count - 1)
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

            // Muting popups reuses the exact same Expired-vs-Dismissed
            // distinction above instead of a separate suppression path -
            // expire() (not dismiss()) drops it out of
            // server.trackedNotifications (so the toast Repeater below
            // never actually renders a card for it) without touching
            // history, since onClosed only clears history on a genuine
            // Dismissed.
            if (root.notificationsDisabled) {
                n.expire()
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

    // Closes the panel on "Clear all" / on deleting the last remaining
    // entry, matching Clipboard.qml's own close-when-empty behavior.
    // A screenshot's notification saves it when clicked, in a popup or in
    // history alike (helpers/screenshot-finish.sh). Each row owns the copy it
    // offers, which is deleted along with the row unless it's being saved.
    // Nothing else can offer one, so a file from outside the cache is ignored.
    readonly property string screenshotDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/purpura/screenshots"

    function screenshotFileFrom(hints) {
        const file = hints["x-purpura-screenshot"]
        if (typeof file !== "string" || !file.startsWith(root.screenshotDir + "/") || file.includes("/../")) return ""
        return file
    }

    function discardScreenshot(index) {
        const file = historyModel.get(index).screenshotFile
        if (file) Quickshell.execDetached(["rm", "-f", file])
    }

    function saveScreenshot(index) {
        const file = historyModel.get(index).screenshotFile
        if (!file) return
        historyModel.setProperty(index, "screenshotFile", "")
        Quickshell.execDetached(["bash", Quickshell.shellDir + "/helpers/screenshot-save.sh", file])
    }

    function historyIndexOf(notifId) {
        // Number(...) both sides - ListModel's dynamic-role storage and
        // the live Notification.id property aren't guaranteed to come
        // back as the exact same JS numeric subtype, and === doesn't
        // coerce.
        const target = Number(notifId)
        for (let i = 0; i < historyModel.count; i++) {
            if (Number(historyModel.get(i).notificationId) === target) return i
        }
        return -1
    }

    // History doesn't outlive the shell, so neither do the copies it offers.
    Process {
        command: ["rm", "-rf", root.screenshotDir]
        running: true
    }

    function clearAllHistory() {
        for (let i = 0; i < historyModel.count; i++) root.discardScreenshot(i)
        historyModel.clear()
        root.centerOpen = false
    }

    function removeHistoryEntry(index) {
        root.discardScreenshot(index)
        historyModel.remove(index)
        if (historyModel.count === 0) root.centerOpen = false
    }

    // Clicking a toast (either button, see cardMouseArea below) counts
    // as having dealt with it, so its history row goes away too instead
    // of sitting there duplicating what the popup already handled - a
    // notification that just times out unclicked is left in history
    // untouched, that's the whole point of it being there.
    function removeHistoryByNotificationId(notifId) {
        const i = root.historyIndexOf(notifId)
        if (i >= 0) {
            root.discardScreenshot(i)
            historyModel.remove(i)
        }
        if (historyModel.count === 0) root.centerOpen = false
    }

    PanelWindow {
        id: toastWindow

        // The shell-wide per-screen scale (see Config.uiScale) of
        // whichever screen the compositor put this window on.
        readonly property real uiScale: Config.uiScale(toastWindow.screen, root.shellScale)

        visible: !root.centerOpen
        anchors { top: true; right: true }
        // Normally pushed below the bar's own reserved exclusive zone by
        // the compositor (margins.top just adds a small extra gap on top
        // of that auto-push). While ignoresBarPadding, exclusiveZone -1
        // stops that auto-push (there's no bar reservation worth
        // avoiding - it's hidden behind the fullscreen client anyway),
        // so margins.top is measured from the true screen edge instead -
        // 10 to roughly land where the bar's own top edge would be,
        // rather than flush against the very corner.
        margins { top: Config.scaled(root.ignoresBarPadding ? 10 : 4, toastWindow.uiScale); right: root.edgeGaps ? root.edgeGaps.right : 10 }
        exclusiveZone: root.ignoresBarPadding ? -1 : 0

        implicitWidth: Config.scaled(380, toastWindow.uiScale)
        implicitHeight: Math.max(1, column.implicitHeight)
        color: "transparent"

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Config.scaled(4, toastWindow.uiScale)

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
                    Layout.preferredHeight: Math.max(Config.scaled(60, toastWindow.uiScale), toastContentColumn.implicitHeight + Config.scaled(20, toastWindow.uiScale))
                    color: cardMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.width: Config.scaled(2, toastWindow.uiScale)
                    border.color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor

                    RowLayout {
                        id: layout
                        anchors.fill: parent
                        anchors.margins: Config.scaled(10, toastWindow.uiScale)
                        spacing: Config.scaled(10, toastWindow.uiScale)

                        Image {
                            Layout.preferredHeight: Config.scaled(36, toastWindow.uiScale)
                            Layout.preferredWidth: Config.scaled(36, toastWindow.uiScale)
                            Layout.alignment: Qt.AlignTop
                            fillMode: Image.PreserveAspectFit
                            visible: source.toString() !== ""
                            source: card.modelData.image || card.modelData. appIcon || ""
                        }

                        ColumnLayout {
                            id: toastContentColumn
                            Layout.fillWidth: true
                            spacing: Config.scaled(2, toastWindow.uiScale)

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary
                                color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(14, toastWindow.uiScale)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: card.modelData.body
                                color: modelData.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolorlight
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(12, toastWindow.uiScale)
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
                            const row = root.historyIndexOf(card.modelData.id)
                            if (row >= 0) root.saveScreenshot(row)
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

    // Cross-wired from shell.qml - Updater.qml's own dropdown holds the
    // reverse reference and does the same thing, same mutual-exclusivity
    // convention Dashboard.qml/SettingsScreen.qml already use for each
    // other (each only closes the OTHER on its own open, guarded on its
    // own flag transitioning true, so this can't ping-pong).
    property var updater: null

    onCenterOpenChanged: {
        if (root.centerOpen) {
            autoCloseTimer.restart()
            if (root.updater) root.updater.dropdownOpen = false
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

    // Whether the currently-focused window is genuinely fullscreen - so
    // both PanelWindows here can ignore the bar's reserved exclusive
    // zone (and sit flush at the true top of the screen) while the bar
    // itself is hidden behind a fullscreen client anyway, rather than
    // leaving a bar-height gap at the top for nothing. Same detection
    // Dashboard.qml/FullscreenHintOsd.qml already use: there's no
    // reactive "fullscreen" property on Quickshell's Hyprland toplevel
    // type, so this re-verifies via `hyprctl activewindow -j`'s
    // fullscreenClient field (0=none/1=maximized/2=fullscreen/3=both)
    // rather than trusting any single IPC event's own data.
    //
    // Reacts to every raw event, not just "fullscreen>>0/1" - same
    // unfiltered convention WorkspaceOsd.qml/WorkspaceRow.qml's own
    // Connections already use. Switching workspaces (or focus) away from
    // a fullscreen window never fires its own "fullscreen" event (that
    // window's fullscreen flag hasn't changed, only which workspace is
    // active has), so filtering to "fullscreen" only left this convinced
    // a fullscreen client was still active on a workspace that had
    // switched away from it entirely.
    //
    // Neither PanelWindow below is given an explicit `screen:` (unlike
    // Dashboard/Bar/etc.'s per-monitor Variants), so - same as
    // Dashboard.qml's own "no click position, always the primary screen"
    // fallback for its GlobalShortcut toggle - this only ever compares
    // against Quickshell.screens[0], which is where an unscreened
    // PanelWindow ends up here too.
    property bool activeIsFullscreen: false
    property string fullscreenMonitorName: ""
    readonly property bool ignoresBarPadding: root.activeIsFullscreen && Quickshell.screens.length > 0 && root.fullscreenMonitorName === Quickshell.screens[0].name

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            fullscreenCheckProcess.running = true
        }
    }

    Process {
        id: fullscreenCheckProcess
        command: ["hyprctl", "activewindow", "-j"]

        stdout: StdioCollector {
            id: fullscreenCheckCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(fullscreenCheckCollector.text)
                } catch (e) {
                    parsed = null
                }
                const mon = Hyprland.activeToplevel && Hyprland.activeToplevel.monitor
                root.activeIsFullscreen = !!(parsed && parsed.fullscreenClient === 2 && mon)
                root.fullscreenMonitorName = (root.activeIsFullscreen && mon) ? mon.name : ""
            }
        }
    }

    PanelWindow {
        id: centerWindow

        // See the toast PanelWindow above.
        readonly property real uiScale: Config.uiScale(centerWindow.screen, root.shellScale)

        // See the toast PanelWindow above for why margins.top/
        // exclusiveZone differ between the two ignoresBarPadding branches.
        margins { top: Config.scaled(root.ignoresBarPadding ? 10 : 4, centerWindow.uiScale); right: root.edgeGaps ? root.edgeGaps.right : 10 }
        anchors { top: true; right: true }
        exclusiveZone: root.ignoresBarPadding ? -1 : 0
        visible: root.centerOpen

        // Fixed/content-derived size, NOT bound to panelBox's currently-
        // animating width/height. Binding the window itself to the live
        // animation meant every frame resized the actual Wayland surface
        // (a real compositor round-trip, not just a repaint), which is
        // what made the panel feel like it was lagging behind while
        // spreading. Dashboard/PowerMenu/Tray never do this - their outer
        // window is sized once from the full/settled content, and only
        // an internal Rectangle (panelBox here) animates via clip.
        implicitWidth: Config.scaled(400, centerWindow.uiScale)
        implicitHeight: Math.max(centerCol.implicitHeight + Config.scaled(20, centerWindow.uiScale), 1)

        color: "transparent"
        Rectangle {
            id: panelBox
            visible: root.centerOpen
            color: "transparent"
            width: centerCol.width
            // +20 = the 10px top margin centerCol's own anchors.margins
            // already gives it (an offset on its position, not something
            // that eats into this box's own height budget) PLUS a
            // matching 10px gap below it - the exact same "+20 = 10 top +
            // 10 bottom" Clipboard.qml's own panelBox comment explains
            // for its box. A bare +10 here left nothing left over for the
            // bottom gap at all (10 entirely consumed accounting for the
            // top offset), clipping the empty-state label flush against
            // the border.
            height: centerCol.implicitHeight + Config.scaled(20, centerWindow.uiScale)

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
                border.width: Config.scaled(2, centerWindow.uiScale)
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
                    // until you trace it through. A width built from
                    // constants alone removes any coupling in either
                    // direction: panelBox's fixed open width (400) minus
                    // the 10px margin on each side.
                    width: Config.scaled(400, centerWindow.uiScale) - 2 * Config.scaled(10, centerWindow.uiScale)

                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: Config.scaled(10, centerWindow.uiScale)
                    }
                    spacing: Config.scaled(10, centerWindow.uiScale)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, centerWindow.uiScale)
                            font.bold: true
                        }

                        Text {
                            visible: historyModel.count > 0
                            text: "Clear all"
                            color: clearAllMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, centerWindow.uiScale)

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
                        text: "No notifications"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(12, centerWindow.uiScale)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        id: historyList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, Config.scaled(420, centerWindow.uiScale))
                        visible: historyModel.count > 0
                        clip: true
                        spacing: Config.scaled(8, centerWindow.uiScale)
                        model: historyModel
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: historyList.width
                            // Grows for wrapped multi-line bodies instead
                            // of clipping them to a fixed 60px card.
                            height: Math.max(Config.scaled(60, centerWindow.uiScale), historyContentColumn.implicitHeight + Config.scaled(20, centerWindow.uiScale))
                            color: historyMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                            border.width: Config.scaled(2, centerWindow.uiScale)
                            border.color: model.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Config.scaled(10, centerWindow.uiScale)
                                spacing: Config.scaled(10, centerWindow.uiScale)

                                Image {
                                    Layout.preferredHeight: Config.scaled(36, centerWindow.uiScale)
                                    Layout.preferredWidth: Config.scaled(36, centerWindow.uiScale)
                                    Layout.alignment: Qt.AlignTop
                                    fillMode: Image.PreserveAspectFit
                                    visible: source.toString() !== ""
                                    source: model.image || model.appIcon || ""
                                }

                                ColumnLayout {
                                    id: historyContentColumn
                                    Layout.fillWidth: true
                                    spacing: Config.scaled(2, centerWindow.uiScale)

                                    Text {
                                        Layout.fillWidth: true
                                        text: model.summary
                                        color: model.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(14, centerWindow.uiScale)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: model.body
                                        color: model.urgency === NotificationUrgency.Critical ? "red" : Config.fgcolorlight
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(12, centerWindow.uiScale)
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
                            // A screenshot is the exception, as its row
                            // owns the file and saves it without the sender.
                            MouseArea {
                                id: historyMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.LeftButton) root.saveScreenshot(index)
                                    root.removeHistoryEntry(index)
                                    if (mouse.button === Qt.LeftButton) root.centerOpen = false
                                }
                            }
                        }
                    }
                    Item { height: Config.scaled(2, centerWindow.uiScale) }
                }
            }

            states: [

                State {
                    name: "spread"

                    PropertyChanges {
                        target: panelBox

                        width: Config.scaled(400, centerWindow.uiScale)
                        height: Config.scaled(2, centerWindow.uiScale)
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: panelBox

                        width: Config.scaled(400, centerWindow.uiScale)
                        height: centerCol.implicitHeight + Config.scaled(20, centerWindow.uiScale)
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
                    panelBox.height = Config.scaled(4, centerWindow.uiScale)

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

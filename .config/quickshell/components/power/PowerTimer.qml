import QtQuick
import Quickshell

// A power menu action - shutdown, restart, suspend... - run after a delay.
// Set with a right click on its button in the power menu
// (PowerTimerInput.qml), shown in the power menu and with the dashboard
// (PowerTimerCountdown.qml). PowerMenu.qml holds the one there is, as
// `timer`, and runs the action when `fired` comes. Lives as long as the
// shell does.
Scope {
    id: root

    // The power menu's entry for the action ({ key, label, icon, trigger }),
    // and when it runs (ms since the epoch) - null and 0 when there's none.
    property var action: null
    property real at: 0
    readonly property bool active: root.action !== null && root.at > 0
    // The clock the time left is counted from, ticking once a second while
    // there's an action waiting.
    property real now: Date.now()

    signal fired(var action)

    function start(action, amount, hours) {
        if (!action || !(amount > 0)) return
        root.now = Date.now()
        root.action = action
        root.at = root.now + amount * (hours ? 3600000 : 60000)
    }

    function cancel() {
        root.action = null
        root.at = 0
    }

    function isFor(key) {
        return root.active && root.action.key === key
    }

    // "1:05:09" / "4:09" left.
    function remaining() {
        const total = Math.max(0, Math.ceil((root.at - root.now) / 1000))
        const h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60
        const two = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s)
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            if (root.now < root.at) return
            const action = root.action
            root.cancel()
            root.fired(action)
        }
    }
}

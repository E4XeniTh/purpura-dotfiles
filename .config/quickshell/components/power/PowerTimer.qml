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
    // The clock the time left is counted from, ticking each time the shown
    // second changes while there's an action waiting (see tick()).
    property real now: Date.now()

    signal fired(var action)

    function start(action, amount, hours) {
        if (!action || !(amount > 0)) return
        root.now = Date.now()
        root.action = action
        root.at = root.now + amount * (hours ? 3600000 : 60000)
        root.tick()
    }

    function cancel() {
        ticker.stop()
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

    // Wakes up just past the moment the time left crosses a whole second,
    // rather than once a second from whenever it started: a free-running
    // second timer sits at some arbitrary offset from those moments, and its
    // own few milliseconds of jitter then land some ticks just before one and
    // some just after - a shown second lasting nearly two, the next almost
    // none. An early wakeup only means one more tick.
    function tick() {
        root.now = Date.now()
        const left = root.at - root.now
        if (left <= 0) {
            const action = root.action
            root.cancel()
            root.fired(action)
            return
        }
        ticker.interval = left % 1000 + 5
        ticker.restart()
    }

    Timer {
        id: ticker
        repeat: false
        onTriggered: if (root.active) root.tick()
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../../../Config.js" as Config

// Monitor list (left, 35%) + resolution/position/scale editor (right,
// 65%). Instantiated inside dashWindow (see Dashboard.qml), which drives
// `active` through its settings-panel coordinator.
//
// Reads via `hyprctl -j monitors all` (includes currently-disabled
// monitors, unlike the plain `monitors` request) and writes via
// `hyprctl eval 'hl.monitor({...})'` - this config is parsed by
// hyprlang's Lua frontend (see hyprland.lua), which rejects the older
// `hyprctl keyword monitor "..."` syntax outright ("keyword can't work
// with non-legacy parsers. Use eval."), confirmed live. Quickshell's own
// Quickshell.Hyprland module only exposes dispatch() for dispatcher-
// class commands (neither keyword nor eval), and its monitor list
// doesn't appear to include disabled monitors either, so shelling out to
// the real binary covers both needs with one consistent data source.
//
// Nothing is applied live as you edit - right-clicking a monitor
// (activate/deactivate) and editing any field are both staged in
// `pending` and only actually run on Apply, which also rewrites
// monitors.conf (see hyprland.lua's autostart block) so the layout
// survives a restart instead of reverting to hyprland.lua's own static
// primary-display definition.
SettingsPanel {
    id: root

    namespaceName: "screenSettings"

    // Layer-shell surfaces default to no keyboard input at all (see
    // SettingsPanel.qml) - without this, the resolution/position/scale
    // fields below could never actually receive typed input at all, no
    // matter what QML-level focus() they had.
    wantsKeyboardFocus: true

    // Raw hyprctl monitors, refreshed on open and after Apply.
    property var monitors: []
    property string selectedName: ""
    property bool identifying: false

    // Fed in from Dashboard.qml (root.primaryMonitor there) rather than
    // owned here - this instance is local to one screen's dashWindow,
    // but "primary" needs to be a single shared value every screen's
    // Bar can read. Double-clicking a card emits primarySelected instead
    // of setting a local property directly, for the same reason.
    property string primaryMonitor: ""
    signal primarySelected(string name)

    // Staged edits, keyed by monitor name: { [name]: { enabled, width,
    // height, refresh, x, y, scale, mode } }. A monitor only appears
    // here once touched - values omitted from the object fall back to
    // `monitors`. Cleared on every Apply.
    property var pending: ({})
    readonly property bool dirty: Object.keys(root.pending).length > 0

    // Whether each monitor's mode toggle is set to "Preferred", keyed by
    // name. Kept separate from `pending` (which Apply clears) because
    // hyprctl's own monitor JSON has no way to report "this is running
    // in preferred mode" after the fact - once applied there's nothing
    // to read back, so the toggle has to remember its own state itself
    // to stay showing "Preferred" instead of reverting to "Manual".
    property var preferredModes: ({})

    function setPreferredMode(name, value) {
        const updated = Object.assign({}, root.preferredModes)
        updated[name] = value
        root.preferredModes = updated
    }

    function baseFor(name) {
        for (const m of root.monitors) {
            if (m.name === name) return m
        }
        return null
    }

    // Merges the live hyprctl state with any staged edit for `name` -
    // what the UI should actually display/edit.
    function effectiveFor(name) {
        const base = root.baseFor(name)
        if (!base) return null
        const p = root.pending[name] || {}
        return {
            name: base.name,
            enabled: p.enabled !== undefined ? p.enabled : !base.disabled,
            width: p.width !== undefined ? p.width : base.width,
            height: p.height !== undefined ? p.height : base.height,
            refresh: p.refresh !== undefined ? p.refresh : base.refreshRate,
            x: p.x !== undefined ? p.x : base.x,
            y: p.y !== undefined ? p.y : base.y,
            scale: p.scale !== undefined ? p.scale : base.scale
        }
    }

    function setPending(name, key, value) {
        const updated = Object.assign({}, root.pending)
        updated[name] = Object.assign({}, updated[name] || {})
        updated[name][key] = value
        root.pending = updated
    }

    // Snapshot of the selected monitor's values actually shown in the
    // input boxes. Deliberately NOT a reactive binding onto
    // effectiveFor(selectedName) - a post-Apply monitors refresh (which
    // changes root.monitors but not root.selectedName) must never touch
    // whatever's currently sitting in the boxes. Only ever reassigned
    // from syncDisplay(), which is only ever called once a dedicated,
    // freshly-requested `hyprctl -j monitors all` actually lands - never
    // from whatever root.monitors happens to already hold, since that
    // can be stale (mid-flight from a just-applied change on a
    // *different* monitor, confirmed live: switching to an untouched
    // monitor right after applying another one's position showed the
    // untouched monitor's own position wrong too).
    property var displayFor: ({})

    // Set true immediately before a fetch that should update the
    // display once it lands - checked (and cleared) in
    // monitorsProcess.onStreamFinished below. A refetch that isn't
    // explicitly flagged (e.g. the settle refetch after Apply) leaves
    // the boxes alone.
    property bool syncDisplayOnNextFetch: false

    // True from the moment Apply is clicked until hyprctl has actually
    // confirmed every touched monitor settled into the values we asked
    // for (see expectedState/monitorsMatchExpected below). A selection
    // made while this is true was still racing hyprctl's in-flight
    // writes - even a fresh `hyprctl -j monitors all` fired right then
    // could read a mid-transition state, and confirmed live, so could an
    // *untouched* monitor's own reported position (repositioning one
    // output can transiently perturb how Hyprland reports others during
    // its layout reflow). Selections made during this window are
    // deferred - queued via selectedName/syncDisplayOnNextFetch - until
    // the pending apply's own verification fetch confirms settlement,
    // instead of racing it with a second, independent fetch.
    property bool applyPending: false

    // What we expect each touched monitor to report once Apply's
    // hl.monitor() calls have actually landed, keyed by name - compared
    // against fresh hyprctl reads in monitorsMatchExpected() below. Only
    // fields we sent an explicit value for are checked; "preferred"
    // mode/"auto" position can't be predicted in advance so they're
    // skipped rather than compared.
    property var expectedState: ({})
    property int verifyAttempts: 0
    readonly property int maxVerifyAttempts: 12

    function syncDisplay() {
        root.displayFor = root.effectiveFor(root.selectedName) || {}
    }

    // Selecting a display always re-queries hyprctl right then and only
    // populates the boxes from that fresh answer - never from whatever
    // root.monitors already happens to hold - unless an apply is still
    // in flight, in which case its own settle refetch will pick up this
    // selection once it lands instead.
    function selectMonitor(name) {
        root.selectedName = name
        root.syncDisplayOnNextFetch = true
        if (!root.applyPending) {
            root.refreshMonitors()
        }
    }

    function refreshMonitors() {
        monitorsProcess.running = false
        monitorsProcess.running = true
    }

    // Builds one hl.monitor({...}) Lua call, exactly the form hyprland.lua
    // itself uses for DP-1 - this config is parsed by hyprlang's Lua
    // frontend, which rejects `hyprctl keyword` outright ("keyword can't
    // work with non-legacy parsers. Use eval.") - confirmed live: the
    // real write path is `hyprctl eval '<this string>'`. Shared by
    // applyChanges() below and mirrored by apply-monitors.sh at startup.
    // Alongside the line itself, returns what we expect hyprctl to
    // report back for this monitor once it's actually landed, so
    // applyChanges() can verify it rather than guess how long to wait.
    //
    // A monitor hyprctl reported as disabled may have stale/placeholder
    // geometry (0x0, etc.) since nothing was actually driving it - if
    // the user is enabling one without having typed real values in
    // themselves, trusting those numbers outright can hand hyprctl an
    // invalid mode/position. Falls back to Hyprland's own
    // "preferred"/"auto" tokens instead whenever a field wasn't both (a)
    // already active before this Apply and (b) not something the user
    // actually edited.
    function buildMonitorPlan(name) {
        const base = root.baseFor(name)
        const eff = root.effectiveFor(name)
        if (!eff.enabled) {
            return {
                line: `hl.monitor({ output = "${eff.name}", disabled = true })`,
                expected: { disabled: true }
            }
        }

        const p = root.pending[name] || {}
        const wasActive = base && !base.disabled

        const usesExplicitMode = !root.preferredModes[name] && (wasActive || p.width !== undefined || p.height !== undefined)
        const mode = usesExplicitMode ? `${eff.width}x${eff.height}@${eff.refresh}` : "preferred"
        const usesExplicitPosition = wasActive || p.x !== undefined || p.y !== undefined
        const position = usesExplicitPosition ? `${eff.x}x${eff.y}` : "auto"
        const scale = eff.scale > 0 ? eff.scale : 1

        // disabled = false has to be explicit - hl.monitor() only
        // touches the fields you pass, so a monitor that was previously
        // disabled would otherwise stay disabled even with a full
        // mode/position/scale given (confirmed live: applying without
        // this left a re-enabled monitor off despite hyprctl replying
        // "ok" to every call).
        return {
            line: `hl.monitor({ output = "${eff.name}", disabled = false, mode = "${mode}", position = "${position}", scale = "${scale}" })`,
            expected: {
                disabled: false,
                usesExplicitMode,
                usesExplicitPosition,
                width: eff.width,
                height: eff.height,
                x: eff.x,
                y: eff.y,
                scale: scale
            }
        }
    }

    // True once every touched monitor's live hyprctl state matches what
    // we asked for in expectedState - checked after every post-apply
    // refetch instead of assuming a fixed delay is always enough (it
    // isn't: repositioning one output can take Hyprland a variable
    // amount of time to settle, and can transiently perturb how it
    // reports *other*, untouched monitors too).
    function monitorsMatchExpected() {
        for (const name in root.expectedState) {
            const exp = root.expectedState[name]
            const base = root.baseFor(name)
            if (!base) return false
            if (exp.disabled) {
                if (!base.disabled) return false
                continue
            }
            if (base.disabled) return false
            if (exp.usesExplicitPosition && (base.x !== exp.x || base.y !== exp.y)) return false
            if (exp.usesExplicitMode && (base.width !== exp.width || base.height !== exp.height)) return false
            if (Math.abs(base.scale - exp.scale) > 0.001) return false
        }
        return true
    }

    function applyChanges() {
        if (!root.dirty) return

        const lines = []
        const expected = {}
        for (const m of root.monitors) {
            const plan = root.buildMonitorPlan(m.name)
            lines.push(plan.line)
            expected[m.name] = plan.expected
        }
        root.expectedState = expected
        root.verifyAttempts = 0

        const script = lines.map(l => `hyprctl eval '${l}'`).join(" ; ")
        console.log("ScreenSettings: applying:\n" + script)
        root.applyPending = true
        applyProcess.command = ["sh", "-c", script]
        applyProcess.running = false
        applyProcess.running = true

        monitorsFile.setText(lines.join("\n") + "\n")

        root.pending = ({})
    }

    onActiveChanged: {
        if (root.active) {
            root.pending = ({})
            root.syncDisplayOnNextFetch = true
            root.refreshMonitors()
        } else {
            root.identifying = false
        }
    }

    Process {
        id: monitorsProcess
        command: ["hyprctl", "-j", "monitors", "all"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.monitors = parsed
                    if (root.selectedName === "" || !root.baseFor(root.selectedName)) {
                        root.selectedName = parsed.length > 0 ? parsed[0].name : ""
                        root.syncDisplay()
                        root.syncDisplayOnNextFetch = false
                    }

                    if (root.applyPending) {
                        root.verifyAttempts++
                        if (root.monitorsMatchExpected() || root.verifyAttempts >= root.maxVerifyAttempts) {
                            root.applyPending = false
                            if (root.syncDisplayOnNextFetch) {
                                root.syncDisplay()
                                root.syncDisplayOnNextFetch = false
                            }
                        } else {
                            verifyRetryTimer.restart()
                        }
                    } else if (root.syncDisplayOnNextFetch) {
                        root.syncDisplay()
                        root.syncDisplayOnNextFetch = false
                    }
                } catch (e) {
                    root.monitors = []
                }
            }
        }
    }

    Process {
        id: applyProcess
        command: ["true"]

        // hyprctl's reply to an "eval" request (including error text like
        // an invalid mode/position) is written to its own STDOUT, not
        // stderr - logged unconditionally (not just on error) so the
        // exact hyprctl response is visible if anything's still wrong.
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("ScreenSettings: hyprctl eval reply:\n" + text)
                }
                // hyprctl replying "ok" only means Hyprland accepted the
                // request, not that the output's new geometry has
                // actually landed yet (repositioning/resizing a monitor
                // is an async DRM/Wayland commit) - refetching
                // immediately can catch a monitor (or even an untouched
                // one!) mid-transition. Kicks the first verification
                // check rather than assuming any fixed delay is enough -
                // see monitorsProcess above, which keeps retrying via
                // verifyRetryTimer until monitorsMatchExpected().
                verifyRetryTimer.restart()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ScreenSettings: hyprctl eval error(s):\n" + text)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            console.log("ScreenSettings: apply process exited, code=" + exitCode)
        }
    }

    // Repeatedly restarted (from applyProcess and from monitorsProcess
    // itself, see above) until monitorsMatchExpected() finally passes or
    // maxVerifyAttempts is hit - each firing is just one more attempt,
    // not a fixed "this must be long enough" delay.
    Timer {
        id: verifyRetryTimer
        interval: 150
        repeat: false
        onTriggered: root.refreshMonitors()
    }

    // Persisted alongside hyprland.lua - see that file's autostart block,
    // which replays these lines via hyprctl keyword on every login so
    // Apply here survives a restart.
    FileView {
        id: monitorsFile
        path: Quickshell.env("HOME") + "/.config/hypr/monitors.conf"
        // Write-only from here (the startup script is what reads it) -
        // no need to preload/read it back.
        preload: false
    }

    Item {
        id: contentWrapper

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: contentRow.margins * 2 + Math.max(leftColumn.implicitHeight, rightColumn.implicitHeight)

        RowLayout {
            id: contentRow

            readonly property real margins: Config.scaled(18, root.uiScale)

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: contentRow.margins
            }
            spacing: Config.scaled(12, root.uiScale)

            readonly property real dividerWidth: Config.scaled(2, root.uiScale)
            readonly property real availableWidth: width - spacing * 2 - dividerWidth
            readonly property real leftWidth: availableWidth * 0.35
            readonly property real rightWidth: availableWidth * 0.65
            readonly property real listMaxHeight: Config.scaled(300, root.uiScale)
            readonly property real cardHeight: Config.scaled(56, root.uiScale)

            // ---------------- LEFT: monitor list ----------------
            ColumnLayout {
                id: leftColumn

                Layout.preferredWidth: contentRow.leftWidth
                Layout.alignment: Qt.AlignTop
                spacing: Config.scaled(8, root.uiScale)

                Text {
                    text: "Displays"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                ListView {
                    id: monitorList

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, contentRow.listMaxHeight)
                    clip: true
                    spacing: Config.scaled(8, root.uiScale)
                    boundsBehavior: Flickable.StopAtBounds

                    model: root.monitors

                    delegate: MonitorCard {
                        required property var modelData

                        width: monitorList.width
                        height: contentRow.cardHeight
                        uiScale: root.uiScale
                        name: modelData.name
                        selected: root.selectedName === modelData.name
                        pendingEnabled: root.effectiveFor(modelData.name) ? root.effectiveFor(modelData.name).enabled : !modelData.disabled
                        isPrimary: root.primaryMonitor === modelData.name

                        // Steals keyboard focus away from any TextInput
                        // in the right-hand form before switching, and
                        // always re-queries hyprctl fresh rather than
                        // trusting whatever root.monitors already holds
                        // (see selectMonitor()).
                        onClicked: {
                            contentWrapper.forceActiveFocus()
                            root.selectMonitor(modelData.name)
                        }
                        // Fail-safes: the primary monitor can't be
                        // disabled (it's always the one thing the bar
                        // lives on), and a disabled monitor can't be
                        // made primary in the first place.
                        onToggleEnabled: {
                            if (modelData.name === root.primaryMonitor) return
                            root.setPending(modelData.name, "enabled", !root.effectiveFor(modelData.name).enabled)
                        }
                        onMakePrimary: {
                            const eff = root.effectiveFor(modelData.name)
                            if (eff && eff.enabled) {
                                root.primarySelected(modelData.name)
                            }
                        }
                    }
                }
            }

            // ---------------- divider ----------------
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.preferredHeight: Math.max(leftColumn.implicitHeight, rightColumn.implicitHeight)
                color: Config.fgcolor
            }

            // ---------------- RIGHT: selected monitor's config ----------------
            ColumnLayout {
                id: rightColumn

                readonly property bool modePreferred: !!root.preferredModes[root.selectedName]

                Layout.preferredWidth: contentRow.rightWidth
                Layout.alignment: Qt.AlignTop
                spacing: Config.scaled(12, root.uiScale)

                // ---------------- mode toggle ----------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Mode:"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        font.bold: true
                    }

                    DashCard {
                        Layout.preferredWidth: Config.scaled(110, root.uiScale)
                        Layout.preferredHeight: Config.scaled(34, root.uiScale)
                        uiScale: root.uiScale
                        color: modeToggleMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor

                        Text {
                            anchors.centerIn: parent
                            text: rightColumn.modePreferred ? "Preferred" : "Manual"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, root.uiScale)
                            font.bold: true
                        }

                        MouseArea {
                            id: modeToggleMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                const next = !rightColumn.modePreferred
                                root.setPreferredMode(root.selectedName, next)
                                // Also staged in `pending` purely so
                                // `dirty` picks up the change and Apply
                                // starts blinking - preferredModes above
                                // is the actual source of truth read by
                                // buildMonitorPlan() and survives Apply's
                                // pending clear.
                                root.setPending(root.selectedName, "mode", next)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(6, root.uiScale)
                    // Width/height/refresh are meaningless once the
                    // monitor is set to hyprland's own "preferred" mode
                    // token - faded out and disabled rather than
                    // `visible: false`, which would drop the row from
                    // rightColumn's layout entirely and make the whole
                    // settings screen change height when the mode
                    // toggle is flipped.
                    opacity: rightColumn.modePreferred ? 0 : 1
                    enabled: !rightColumn.modePreferred

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Width"
                        value: root.displayFor.width !== undefined ? String(root.displayFor.width) : ""
                        onEdited: (text) => root.setPending(root.selectedName, "width", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(10, root.uiScale)
                        text: "x"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Height"
                        value: root.displayFor.height !== undefined ? String(root.displayFor.height) : ""
                        onEdited: (text) => root.setPending(root.selectedName, "height", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(10, root.uiScale)
                        text: "@"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Refresh Rate"
                        value: root.displayFor.refresh !== undefined ? String(root.displayFor.refresh) : ""
                        onEdited: (text) => root.setPending(root.selectedName, "refresh", parseFloat(text) || 60)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(6, root.uiScale)

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "X Pos"
                        value: root.displayFor.x !== undefined ? String(root.displayFor.x) : ""
                        onEdited: (text) => root.setPending(root.selectedName, "x", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(10, root.uiScale)
                        text: "x"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Y Pos"
                        value: root.displayFor.y !== undefined ? String(root.displayFor.y) : ""
                        onEdited: (text) => root.setPending(root.selectedName, "y", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(10, root.uiScale)
                        text: ","
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Scale"
                        value: root.displayFor.scale !== undefined ? String(root.displayFor.scale) : ""
                        onEdited: (text) => root.setPending(root.selectedName, "scale", parseFloat(text) || 1)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(4, root.uiScale)

                    // ---------------- bottom left: identify ----------------
                    DashCard {
                        Layout.preferredWidth: Config.scaled(100, root.uiScale)
                        Layout.preferredHeight: Config.scaled(32, root.uiScale)
                        uiScale: root.uiScale
                        color: identifyMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor

                        Text {
                            anchors.centerIn: parent
                            text: "Identify"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                        }

                        MouseArea {
                            id: identifyMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.identifying = true
                                identifyTimer.restart()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // ---------------- bottom right: apply ----------------
                    DashCard {
                        id: applyButton

                        Layout.preferredWidth: Config.scaled(100, root.uiScale)
                        Layout.preferredHeight: Config.scaled(32, root.uiScale)
                        uiScale: root.uiScale

                        property color blinkColor: Config.fgcolor
                        border.color: root.dirty ? applyButton.blinkColor : Config.fgcolordark

                        SequentialAnimation {
                            running: root.dirty
                            loops: Animation.Infinite
                            ColorAnimation { target: applyButton; property: "blinkColor"; to: Config.fgcolorlight; duration: 800 }
                            ColorAnimation { target: applyButton; property: "blinkColor"; to: Config.fgcolor; duration: 800 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Apply"
                            color: root.dirty ? Config.fgcolor : Config.fgcolordark
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.dirty
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.applyChanges()
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: identifyTimer
        interval: 3000
        repeat: false
        onTriggered: root.identifying = false
    }
}

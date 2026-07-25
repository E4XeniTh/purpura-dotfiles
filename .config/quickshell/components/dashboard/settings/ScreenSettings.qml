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
    // effectiveFor(selectedName) - it's only ever reassigned here, from
    // onSelectedNameChanged below and once after the panel (re)opens.
    // That means a post-Apply monitors refresh (which changes
    // root.monitors but not root.selectedName) can no longer touch
    // whatever's currently sitting in the boxes, no matter how that
    // refresh's timing lines up with typing/focus - fixes an
    // intermittent bug where an edit would occasionally get silently
    // reverted by the refresh that follows Apply.
    property var displayFor: ({})

    function syncDisplay() {
        root.displayFor = root.effectiveFor(root.selectedName) || {}
    }

    onSelectedNameChanged: root.syncDisplay()

    // Set whenever the panel opens so the next monitors fetch re-syncs
    // the display even if selectedName happens to still be valid (and
    // therefore wouldn't otherwise trigger onSelectedNameChanged).
    property bool needsDisplaySync: false

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
    //
    // A monitor hyprctl reported as disabled may have stale/placeholder
    // geometry (0x0, etc.) since nothing was actually driving it - if
    // the user is enabling one without having typed real values in
    // themselves, trusting those numbers outright can hand hyprctl an
    // invalid mode/position. Falls back to Hyprland's own
    // "preferred"/"auto" tokens instead whenever a field wasn't both (a)
    // already active before this Apply and (b) not something the user
    // actually edited.
    function monitorLine(name) {
        const base = root.baseFor(name)
        const eff = root.effectiveFor(name)
        if (!eff.enabled) {
            return `hl.monitor({ output = "${eff.name}", disabled = true })`
        }

        const p = root.pending[name] || {}
        const wasActive = base && !base.disabled

        const mode = root.preferredModes[name]
            ? "preferred"
            : (wasActive || p.width !== undefined || p.height !== undefined)
                ? `${eff.width}x${eff.height}@${eff.refresh}`
                : "preferred"
        const position = (wasActive || p.x !== undefined || p.y !== undefined)
            ? `${eff.x}x${eff.y}`
            : "auto"
        const scale = eff.scale > 0 ? eff.scale : 1

        // disabled = false has to be explicit - hl.monitor() only
        // touches the fields you pass, so a monitor that was previously
        // disabled would otherwise stay disabled even with a full
        // mode/position/scale given (confirmed live: applying without
        // this left a re-enabled monitor off despite hyprctl replying
        // "ok" to every call).
        return `hl.monitor({ output = "${eff.name}", disabled = false, mode = "${mode}", position = "${position}", scale = "${scale}" })`
    }

    function applyChanges() {
        if (!root.dirty) return

        const lines = []
        for (const m of root.monitors) {
            lines.push(root.monitorLine(m.name))
        }

        const script = lines.map(l => `hyprctl eval '${l}'`).join(" ; ")
        console.log("ScreenSettings: applying:\n" + script)
        applyProcess.command = ["sh", "-c", script]
        applyProcess.running = false
        applyProcess.running = true

        monitorsFile.setText(lines.join("\n") + "\n")

        root.pending = ({})
    }

    onActiveChanged: {
        if (root.active) {
            root.pending = ({})
            root.needsDisplaySync = true
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
                        // Triggers onSelectedNameChanged, which syncs
                        // the display itself.
                        root.selectedName = parsed.length > 0 ? parsed[0].name : ""
                    } else if (root.needsDisplaySync) {
                        root.syncDisplay()
                    }
                    root.needsDisplaySync = false
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
                root.refreshMonitors()
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
                        // in the right-hand form before switching -
                        // otherwise LabeledField's re-sync guard
                        // (`if (!input.activeFocus)`) skips whichever
                        // field was still focused, leaving it frozen on
                        // the previous monitor's value.
                        onClicked: {
                            contentWrapper.forceActiveFocus()
                            root.selectedName = modelData.name
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
                                // monitorLine() and survives Apply's
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

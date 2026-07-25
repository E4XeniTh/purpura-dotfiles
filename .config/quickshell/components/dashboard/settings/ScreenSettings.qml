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
// One monitor at a time by design: selecting a display always re-reads
// its live hyprctl state right then (never a cached copy) and any
// unsaved width/height/position/scale/mode edit is discarded the moment
// you select a *different* one - this panel is for changing one
// display, hitting Apply, then moving to the next, not staging edits
// across several simultaneously. The one exception is right-click
// enable/disable, which stays staged across monitors (see
// pendingEnabled below) so you can flip several on/off and Apply once.
SettingsPanel {
    id: root

    namespaceName: "screenSettings"

    // Layer-shell surfaces default to no keyboard input at all (see
    // SettingsPanel.qml) - without this, the resolution/position/scale
    // fields below could never actually receive typed input at all, no
    // matter what QML-level focus() they had.
    wantsKeyboardFocus: true

    // Raw hyprctl monitors, refreshed on open, on selecting a monitor,
    // and after Apply.
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

    function baseFor(name) {
        for (const m of root.monitors) {
            if (m.name === name) return m
        }
        return null
    }

    // Right-click enable/disable toggles, keyed by monitor name - the
    // one thing this panel still lets you stage across *multiple*
    // monitors before a single Apply. Cleared on Apply and on reopening
    // the panel.
    property var pendingEnabled: ({})

    function setPendingEnabled(name, value) {
        const updated = Object.assign({}, root.pendingEnabled)
        updated[name] = value
        root.pendingEnabled = updated
    }

    function enabledFor(name) {
        if (root.pendingEnabled[name] !== undefined) return root.pendingEnabled[name]
        const base = root.baseFor(name)
        return base ? !base.disabled : false
    }

    // Width/height/refresh/x/y/scale edits, always for whichever
    // monitor is currently selected - discarded (not merged, not
    // persisted) the instant a different monitor is selected or Apply
    // runs, rather than staged per-monitor across the whole session.
    property var edited: ({})
    property bool selectedDirty: false
    property bool preferredMode: false

    readonly property bool dirty: root.selectedDirty || Object.keys(root.pendingEnabled).length > 0

    function setEdited(key, value) {
        const updated = Object.assign({}, root.edited)
        updated[key] = value
        root.edited = updated
        root.selectedDirty = true
    }

    function togglePreferredMode() {
        root.preferredMode = !root.preferredMode
        root.selectedDirty = true
    }

    // What the input boxes actually show - a live hyprctl snapshot for
    // whichever monitor is currently selected. Cleared immediately on
    // selection (so a brief fetch-in-flight window never shows a
    // stale/wrong monitor's numbers) and repopulated once the fresh
    // fetch lands, in monitorsProcess below.
    property var displayFor: ({})

    // Always re-queries hyprctl fresh right then and discards whatever
    // was being edited for the previously selected monitor - never
    // trusts a cached copy or remembers unsaved edits across monitors.
    function selectMonitor(name) {
        root.selectedName = name
        root.edited = ({})
        root.selectedDirty = false
        root.preferredMode = false
        root.displayFor = ({})
        root.refreshMonitors()
    }

    function refreshMonitors() {
        monitorsProcess.running = false
        monitorsProcess.running = true
    }

    // Builds one hl.monitor({...}) Lua call, exactly the form
    // hyprland.lua itself uses for DP-1 - this config is parsed by
    // hyprlang's Lua frontend, which rejects `hyprctl keyword` outright
    // ("keyword can't work with non-legacy parsers. Use eval.") -
    // confirmed live: the real write path is `hyprctl eval '<this
    // string>'`. Used both for the actively-edited monitor and for any
    // monitor with a pending enable/disable toggle.
    //
    // A monitor hyprctl reported as disabled may have stale/placeholder
    // geometry (0x0, etc.) since nothing was actually driving it -
    // trusting those numbers outright can hand hyprctl an invalid
    // mode/position. Falls back to Hyprland's own "preferred"/"auto"
    // tokens whenever a field wasn't both (a) already active and (b)
    // actually known (edited, for the selected monitor).
    function buildMonitorLine(name) {
        const base = root.baseFor(name)
        if (!base) return null

        if (!root.enabledFor(name)) {
            return `hl.monitor({ output = "${name}", disabled = true })`
        }

        const isSelected = name === root.selectedName
        const e = isSelected ? root.edited : {}
        const wasActive = !base.disabled

        const width = e.width !== undefined ? e.width : base.width
        const height = e.height !== undefined ? e.height : base.height
        const refresh = e.refresh !== undefined ? e.refresh : base.refreshRate
        const x = e.x !== undefined ? e.x : base.x
        const y = e.y !== undefined ? e.y : base.y
        const rawScale = e.scale !== undefined ? e.scale : base.scale
        const scale = rawScale > 0 ? rawScale : 1

        const usesExplicitMode = isSelected
            ? (!root.preferredMode && (wasActive || e.width !== undefined || e.height !== undefined))
            : wasActive
        const mode = usesExplicitMode ? `${width}x${height}@${refresh}` : "preferred"

        const usesExplicitPosition = wasActive || e.x !== undefined || e.y !== undefined
        const position = usesExplicitPosition ? `${x}x${y}` : "auto"

        // disabled = false has to be explicit - hl.monitor() only
        // touches the fields you pass, so a monitor that was previously
        // disabled would otherwise stay disabled even with a full
        // mode/position/scale given (confirmed live: applying without
        // this left a re-enabled monitor off despite hyprctl replying
        // "ok" to every call).
        return `hl.monitor({ output = "${name}", disabled = false, mode = "${mode}", position = "${position}", scale = "${scale}" })`
    }

    function applyChanges() {
        if (!root.dirty) return

        // Only touched monitors are actually sent live - the selected
        // one (if edited) plus any right-clicked enable/disable
        // toggles - not every monitor every time, which used to
        // trigger Hyprland's layout reflow for displays nobody asked to
        // change.
        const touched = new Set(Object.keys(root.pendingEnabled))
        if (root.selectedDirty && root.selectedName) {
            touched.add(root.selectedName)
        }

        const sendLines = []
        for (const name of touched) {
            const line = root.buildMonitorLine(name)
            if (line) sendLines.push(line)
        }

        // monitors.conf persists the *whole* layout, not just what
        // changed this time, since apply-monitors.sh replays every line
        // in it from scratch at login (hyprland.lua only defines DP-1).
        const allLines = []
        for (const m of root.monitors) {
            const line = root.buildMonitorLine(m.name)
            if (line) allLines.push(line)
        }
        monitorsFile.setText(allLines.join("\n") + "\n")

        if (sendLines.length > 0) {
            const script = sendLines.map(l => `hyprctl eval '${l}'`).join(" ; ")
            console.log("ScreenSettings: applying:\n" + script)
            applyProcess.command = ["sh", "-c", script]
            applyProcess.running = false
            applyProcess.running = true
        }

        root.pendingEnabled = ({})
        root.edited = ({})
        root.selectedDirty = false
        // preferredMode intentionally left as-is - Apply shouldn't flip
        // the toggle back to "Manual" for the monitor you just applied.
    }

    onActiveChanged: {
        if (root.active) {
            root.pendingEnabled = ({})
            root.edited = ({})
            root.selectedDirty = false
            root.preferredMode = false
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
                    }
                    const base = root.baseFor(root.selectedName)
                    root.displayFor = base
                        ? { width: base.width, height: base.height, refresh: base.refreshRate, x: base.x, y: base.y, scale: base.scale }
                        : {}
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
                // request, not that the output's geometry has actually
                // landed yet (an async DRM/Wayland commit) - one short
                // settle delay before the follow-up refetch, rather than
                // the multi-attempt verification loop this used to run.
                // If it's ever still stale, reselecting the monitor
                // (which always pulls a fresh read, see selectMonitor())
                // is the reliable fallback.
                applySettleTimer.restart()
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

    Timer {
        id: applySettleTimer
        interval: 300
        repeat: false
        onTriggered: root.refreshMonitors()
    }

    // Persisted alongside hyprland.lua - see that file's autostart block,
    // which replays these lines via hyprctl eval on every login so
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
                        pendingEnabled: root.enabledFor(modelData.name)
                        isPrimary: root.primaryMonitor === modelData.name

                        // Steals keyboard focus away from any TextInput
                        // in the right-hand form before switching, and
                        // always re-queries hyprctl fresh (see
                        // selectMonitor()) rather than trusting a cached
                        // copy.
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
                            root.setPendingEnabled(modelData.name, !root.enabledFor(modelData.name))
                        }
                        onMakePrimary: {
                            if (root.enabledFor(modelData.name)) {
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
                            text: root.preferredMode ? "Preferred" : "Manual"
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
                                root.togglePreferredMode()
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
                    opacity: root.preferredMode ? 0 : 1
                    enabled: !root.preferredMode

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Width"
                        value: root.displayFor.width !== undefined ? String(root.displayFor.width) : ""
                        onEdited: (text) => root.setEdited("width", parseInt(text, 10) || 0)
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
                        onEdited: (text) => root.setEdited("height", parseInt(text, 10) || 0)
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
                        onEdited: (text) => root.setEdited("refresh", parseFloat(text) || 60)
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
                        onEdited: (text) => root.setEdited("x", parseInt(text, 10) || 0)
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
                        onEdited: (text) => root.setEdited("y", parseInt(text, 10) || 0)
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
                        onEdited: (text) => root.setEdited("scale", parseFloat(text) || 1)
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

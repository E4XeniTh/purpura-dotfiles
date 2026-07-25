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
// enable/disable (and the per-card brightness sliders), which stay
// staged across monitors (see pendingEnabled/pendingBrightness below)
// so you can flip/adjust several and Apply once.
//
// A disabled monitor's own hyprctl geometry is a stale placeholder
// (0x0, etc. - nothing's actually driving it), so selecting one instead
// shows whatever was last remembered for it in ~/.config/hypr/
// screens.json, written on every Apply - this is purely so re-enabling
// a monitor doesn't force retyping its position/resolution from
// scratch. An enabled monitor always shows its real, live hyprctl state
// instead, screens.json or not.
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

    // Right-click enable/disable toggles, keyed by monitor name - one of
    // the two things this panel still lets you stage across *multiple*
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

    // Whether each monitor's mode toggle is set to "Preferred", keyed by
    // name - unlike `edited` above, this *is* remembered across
    // switching monitors (and across Apply): hyprctl's own monitor JSON
    // has no way to report "this is running in preferred mode" after
    // the fact, so there's nothing to re-derive it from on reselect -
    // the toggle has to remember its own state itself. Also seeded from
    // screens.json on load (see screensStoreProcess) for monitors not
    // touched yet this session.
    property var preferredModes: ({})

    function setPreferredMode(name, value) {
        const updated = Object.assign({}, root.preferredModes)
        updated[name] = value
        root.preferredModes = updated
    }

    readonly property bool dirty: root.selectedDirty
        || Object.keys(root.pendingEnabled).length > 0
        || Object.keys(root.pendingBrightness).length > 0

    function setEdited(key, value) {
        const updated = Object.assign({}, root.edited)
        updated[key] = value
        root.edited = updated
        root.selectedDirty = true
    }

    function togglePreferredMode() {
        root.setPreferredMode(root.selectedName, !root.preferredModes[root.selectedName])
        root.selectedDirty = true
    }

    // What the input boxes actually show - a live hyprctl snapshot (or,
    // for a disabled monitor, its remembered screens.json values) for
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
        root.displayFor = ({})
        root.refreshMonitors()
    }

    function refreshMonitors() {
        monitorsProcess.running = false
        monitorsProcess.running = true
    }

    // Resolves what a monitor's width/height/refresh/x/y/scale/mode
    // "should" be right now - the single source of truth used both to
    // build the hl.monitor() line for Apply and to populate the input
    // boxes/screens.json snapshot, so those three things can never
    // disagree with each other.
    //
    // For a disabled monitor, hyprctl's own geometry may be a stale
    // placeholder (0x0, etc.) since nothing's actually driving it -
    // falls back to whatever screens.json remembers for it instead.
    // usesExplicitMode/usesExplicitPosition say whether the *enabled*
    // hl.monitor() line (were this monitor enabled) should give
    // hyprctl real numbers or Hyprland's own "preferred"/"auto" tokens
    // - only meaningful when the monitor is actually enabled.
    function effectiveStateFor(name) {
        const base = root.baseFor(name)
        if (!base) return null

        const isSelected = name === root.selectedName
        const e = isSelected ? root.edited : {}
        const stored = root.screensStore[name]
        const remembered = base.disabled && stored ? stored : base

        const width = e.width !== undefined ? e.width : remembered.width
        const height = e.height !== undefined ? e.height : remembered.height
        const refresh = e.refresh !== undefined
            ? e.refresh
            : (remembered.refreshRate !== undefined ? remembered.refreshRate : remembered.refresh)
        const x = e.x !== undefined ? e.x : remembered.x
        const y = e.y !== undefined ? e.y : remembered.y
        const rawScale = e.scale !== undefined ? e.scale : remembered.scale
        const scale = rawScale > 0 ? rawScale : 1

        if (!root.enabledFor(name)) {
            return {
                disabled: true,
                width, height, refresh, x, y, scale,
                mode: stored ? stored.mode : "manual",
                usesExplicitMode: false,
                usesExplicitPosition: false
            }
        }

        const wasActive = !base.disabled
        // A monitor being (re-)enabled with a screens.json entry has
        // trustworthy remembered geometry too, same as one that was
        // already active - without this, re-enabling a disabled
        // monitor without editing anything fell back to
        // "preferred"/"auto" and silently discarded exactly the
        // remembered values the input boxes were already showing.
        const hasRememberedGeometry = wasActive || !!stored
        const usesExplicitMode = isSelected
            ? (!root.preferredModes[name] && (hasRememberedGeometry || e.width !== undefined || e.height !== undefined))
            : hasRememberedGeometry
        const usesExplicitPosition = hasRememberedGeometry || e.x !== undefined || e.y !== undefined

        return {
            disabled: false,
            width, height, refresh, x, y, scale,
            mode: root.preferredModes[name] ? "preferred" : "manual",
            usesExplicitMode,
            usesExplicitPosition
        }
    }

    // Builds one hl.monitor({...}) Lua call, exactly the form
    // hyprland.lua itself uses for DP-1 - this config is parsed by
    // hyprlang's Lua frontend, which rejects `hyprctl keyword` outright
    // ("keyword can't work with non-legacy parsers. Use eval.") -
    // confirmed live: the real write path is `hyprctl eval '<this
    // string>'`. Used both for the actively-edited monitor and for any
    // monitor with a pending enable/disable toggle.
    function buildMonitorLine(name) {
        const state = root.effectiveStateFor(name)
        if (!state) return null

        if (state.disabled) {
            return `hl.monitor({ output = "${name}", disabled = true })`
        }

        const mode = state.usesExplicitMode ? `${state.width}x${state.height}@${state.refresh}` : "preferred"
        const position = state.usesExplicitPosition ? `${state.x}x${state.y}` : "auto"

        // disabled = false has to be explicit - hl.monitor() only
        // touches the fields you pass, so a monitor that was previously
        // disabled would otherwise stay disabled even with a full
        // mode/position/scale given (confirmed live: applying without
        // this left a re-enabled monitor off despite hyprctl replying
        // "ok" to every call).
        return `hl.monitor({ output = "${name}", disabled = false, mode = "${mode}", position = "${position}", scale = "${state.scale}" })`
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
        // screens.json is built from the same per-monitor state at the
        // same time, so re-enabling a monitor later shows exactly what
        // it was just set to (or, if untouched, whatever it already
        // remembered).
        const allLines = []
        const storeSnapshot = {}
        for (const m of root.monitors) {
            const line = root.buildMonitorLine(m.name)
            if (line) allLines.push(line)

            const state = root.effectiveStateFor(m.name)
            if (state) {
                storeSnapshot[m.name] = {
                    width: state.width,
                    height: state.height,
                    refresh: state.refresh,
                    x: state.x,
                    y: state.y,
                    scale: state.scale,
                    mode: state.mode
                }
            }
        }
        monitorsFile.setText(allLines.join("\n") + "\n")

        root.screensStore = storeSnapshot
        screensStoreFile.setText(JSON.stringify(storeSnapshot, null, 2) + "\n")

        if (sendLines.length > 0) {
            const script = sendLines.map(l => `hyprctl eval '${l}'`).join(" ; ")
            console.log("ScreenSettings: applying:\n" + script)
            applyProcess.command = ["sh", "-c", script]
            applyProcess.running = false
            applyProcess.running = true
        }

        root.applyBrightness()

        // Re-detect after every Apply, not just on panel open - a
        // monitor just enabled here (or physically powered on) wouldn't
        // otherwise get a ddcBusNumbers entry until the panel was closed
        // and reopened, since DDC/CI detection depends on the display's
        // actual physical power state, not Hyprland's enabled/disabled
        // state. Also refreshes every brightness slider's live value
        // (queueBrightnessQueries() runs again once this lands).
        root.detectDdcDisplays()

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
            root.pendingBrightness = ({})
            root.refreshMonitors()
            root.loadScreensStore()
            root.detectDdcDisplays()
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
                    const state = root.effectiveStateFor(root.selectedName)
                    root.displayFor = state
                        ? { width: state.width, height: state.height, refresh: state.refresh, x: state.x, y: state.y, scale: state.scale }
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

    // ---------------- disabled-monitor memory (screens.json) ----------------

    // Last known good width/height/refresh/x/y/scale/mode per monitor
    // name, loaded once on open and rewritten on every Apply - see
    // effectiveStateFor() above for how a disabled monitor falls back to
    // this instead of hyprctl's own stale placeholder geometry.
    property var screensStore: ({})

    function loadScreensStore() {
        screensStoreProcess.running = false
        screensStoreProcess.running = true
    }

    Process {
        id: screensStoreProcess
        // Read via `cat` (like every other read in this file goes
        // through Process/hyprctl) rather than FileView, so a missing
        // file (first run) just yields empty stdout instead of needing
        // to reason about FileView's own missing-file behavior.
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/screens.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.screensStore = parsed
                    // Seed preferredModes from what was last saved, for
                    // any monitor not already touched this session -
                    // otherwise a disabled monitor remembered as
                    // "preferred" would show "Manual" until reselected
                    // once quickshell restarts.
                    const seeded = Object.assign({}, root.preferredModes)
                    for (const name in parsed) {
                        if (seeded[name] === undefined) {
                            seeded[name] = parsed[name].mode === "preferred"
                        }
                    }
                    root.preferredModes = seeded
                } catch (e) {
                    root.screensStore = {}
                }
            }
        }
    }

    FileView {
        id: screensStoreFile
        path: Quickshell.env("HOME") + "/.config/hypr/screens.json"
        preload: false
    }

    // ---------------- DDC/CI brightness ----------------

    // Best-effort mapping from Hyprland's monitor name (e.g. "HDMI-A-1")
    // to the I2C bus number ddcutil should talk to it over, built from
    // `ddcutil detect`'s "I2C bus: /dev/i2c-N" and "DRM connector:"/
    // "DRM_connector:" lines (both present in the same per-display block
    // - the field name's separator on the latter, space or underscore,
    // varies by ddcutil version, confirmed live). A monitor that doesn't
    // support DDC/CI at all (e.g. a TV) shows up as "Invalid display"
    // instead of "Display N" and is correctly never mapped.
    //
    // Targeted via `--bus N` rather than `--display N` - confirmed live,
    // `--display N` makes ddcutil re-resolve which bus that display
    // number currently refers to on every single invocation (effectively
    // re-detecting), while `--bus N` talks to that I2C bus directly and
    // skips it entirely (~0.5s vs several seconds per call).
    property var ddcBusNumbers: ({})

    // 0-100, queried live per monitor once ddcBusNumbers is known.
    // Assumes VCP feature 0x10 (brightness) is reported on a 0-100
    // scale, which is the case for the vast majority of DDC/CI panels.
    property var liveBrightness: ({})

    // Staged like pendingEnabled above (not like `edited`) - every
    // card's slider is visible and draggable at once, regardless of
    // which monitor is selected, so more than one can be adjusted
    // before a single Apply.
    property var pendingBrightness: ({})

    function setPendingBrightness(name, value) {
        const updated = Object.assign({}, root.pendingBrightness)
        updated[name] = value
        root.pendingBrightness = updated
    }

    function brightnessFor(name) {
        if (root.pendingBrightness[name] !== undefined) return root.pendingBrightness[name]
        if (root.liveBrightness[name] !== undefined) return root.liveBrightness[name]
        return 50
    }

    function detectDdcDisplays() {
        ddcDetectProcess.running = false
        ddcDetectProcess.running = true
    }

    // Queried one at a time, not all in parallel - ddcutil talks to
    // real I2C hardware, and overlapping queries against the same/
    // adjacent buses are a common source of ddcutil timeouts/errors.
    property var ddcQueryQueue: []

    // Names to skip on the very next queueBrightnessQueries() call -
    // set by applyBrightness() right before the post-apply redetect
    // (see applyChanges()) so that redetect's own requery doesn't
    // immediately re-read (and potentially stomp) a monitor whose
    // brightness this exact Apply just set. Needed because setvcp runs
    // with --noverify, so there's no guarantee the write has actually
    // landed on the hardware by the time a fresh getvcp reads it back -
    // confirmed live: without this, a second brightness change would
    // apply correctly but the slider would immediately snap back to the
    // stale pre-apply value once the redetect's requery landed. Cleared
    // after one use; a later Apply (even for a different monitor) will
    // requery this one normally again, by which point plenty of real
    // time has passed for it to have settled.
    property var skipNextBrightnessQuery: []

    function queueBrightnessQueries() {
        const skip = root.skipNextBrightnessQuery
        root.skipNextBrightnessQuery = []
        root.ddcQueryQueue = Object.keys(root.ddcBusNumbers).filter(name => !skip.includes(name))
        root.runNextBrightnessQuery()
    }

    function runNextBrightnessQuery() {
        if (root.ddcQueryQueue.length === 0) return
        const name = root.ddcQueryQueue[0]
        ddcGetProcess.currentName = name
        ddcGetProcess.command = ["ddcutil", "--bus", String(root.ddcBusNumbers[name]), "getvcp", "10", "--brief"]
        ddcGetProcess.running = false
        ddcGetProcess.running = true
    }

    function applyBrightness() {
        const names = Object.keys(root.pendingBrightness)
        // Set regardless of whether brightness was actually touched
        // this Apply, so a cycle that didn't change any brightness
        // correctly leaves nothing excluded from the next requery.
        root.skipNextBrightnessQuery = names
        if (names.length === 0) return

        const commands = []
        for (const name of names) {
            const busNum = root.ddcBusNumbers[name]
            if (busNum === undefined) continue
            // --noverify skips ddcutil's default post-write readback
            // that confirms the value actually took - roughly halves
            // the round-trip, and we don't need it since the UI already
            // optimistically assumes success (liveBrightness is updated
            // below regardless).
            commands.push(`ddcutil --bus ${busNum} --noverify setvcp 10 ${root.pendingBrightness[name]}`)
        }

        if (commands.length > 0) {
            const updated = Object.assign({}, root.liveBrightness)
            for (const name of names) {
                updated[name] = root.pendingBrightness[name]
            }
            root.liveBrightness = updated

            ddcApplyProcess.command = ["sh", "-c", commands.join(" ; ")]
            ddcApplyProcess.running = false
            ddcApplyProcess.running = true
        }

        root.pendingBrightness = ({})
    }

    Process {
        id: ddcDetectProcess
        command: ["ddcutil", "detect"]

        stdout: StdioCollector {
            onStreamFinished: {
                // Each block (one per detected display) contains both an
                // "I2C bus: /dev/i2c-N" line and a "DRM connector:"/
                // "DRM_connector:" line (separator varies by ddcutil
                // version, confirmed live) - captures the bus number
                // when seen, then attaches it to the connector name once
                // that line follows. "Invalid display" blocks (a monitor
                // that doesn't support DDC/CI at all, e.g. a TV) are
                // skipped entirely rather than mapped, since ddcutil can
                // never actually talk to them anyway.
                const map = {}
                let currentBus = null
                let skipBlock = false
                for (const line of text.split("\n")) {
                    if (/^Invalid display/.test(line)) {
                        currentBus = null
                        skipBlock = true
                        continue
                    }
                    if (/^Display \d+/.test(line)) {
                        currentBus = null
                        skipBlock = false
                        continue
                    }
                    if (skipBlock) continue

                    const busMatch = line.match(/I2C bus:\s*\/dev\/i2c-(\d+)/)
                    if (busMatch) {
                        currentBus = parseInt(busMatch[1], 10)
                        continue
                    }
                    const connectorMatch = line.match(/DRM[ _]connector:\s*card\d+-(.+)$/)
                    if (connectorMatch && currentBus !== null) {
                        map[connectorMatch[1].trim()] = currentBus
                    }
                }
                root.ddcBusNumbers = map
                root.queueBrightnessQueries()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ScreenSettings: ddcutil detect error(s) (brightness sliders may not work):\n" + text)
                }
            }
        }
    }

    Process {
        id: ddcGetProcess
        property string currentName: ""
        command: ["true"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/VCP\s+10\s+C\s+(\d+)/)
                if (match) {
                    const updated = Object.assign({}, root.liveBrightness)
                    updated[ddcGetProcess.currentName] = Math.max(0, Math.min(100, parseInt(match[1], 10)))
                    root.liveBrightness = updated
                }
                root.ddcQueryQueue = root.ddcQueryQueue.slice(1)
                root.runNextBrightnessQuery()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ScreenSettings: ddcutil getvcp error for " + ddcGetProcess.currentName + ":\n" + text)
                }
            }
        }
    }

    Process {
        id: ddcApplyProcess
        command: ["true"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("ScreenSettings: ddcutil setvcp reply:\n" + text)
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ScreenSettings: ddcutil setvcp error(s):\n" + text)
                }
            }
        }
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
            readonly property real listMaxHeight: Config.scaled(340, root.uiScale)
            // Taller than before to fit the brightness slider + its
            // separator under the icon/label row.
            readonly property real cardHeight: Config.scaled(84, root.uiScale)

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
                        brightness: root.brightnessFor(modelData.name)

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
                        onBrightnessEdited: (value) => root.setPendingBrightness(modelData.name, value)
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
                            text: root.preferredModes[root.selectedName] ? "Preferred" : "Manual"
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
                    opacity: root.preferredModes[root.selectedName] ? 0 : 1
                    enabled: !root.preferredModes[root.selectedName]

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

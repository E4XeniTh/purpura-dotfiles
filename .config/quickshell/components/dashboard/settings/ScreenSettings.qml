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
// Quickshell.Hyprland module (see WorkspaceOsd.qml for where this panel
// instead reaches for its reactive Hyprland.monitors/workspaces data)
// only exposes dispatch() for the write side - no keyword or eval - and
// its own monitor list doesn't appear to include disabled monitors
// either, so shelling out to the real binary is still what covers both
// read and write needs here with one consistent data source.
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
// shows whatever was last remembered for it in ~/.config/quickshell/
// monitors.json, written on every Apply - this is purely so re-enabling
// a monitor doesn't force retyping its position/resolution from
// scratch. An enabled monitor always shows its real, live hyprctl state
// instead, monitors.json or not. That same file also carries a
// precomputed hl.monitor({...}) "line" per monitor, which is all
// scripts/apply-monitors.sh needs to replay the whole layout at login -
// one combined file instead of the previous monitors.conf/screens.json
// split, since this panel was the only thing reading or writing either.
SettingsPanel {
    id: root

    namespaceName: "screenSettings"

    // Layer-shell surfaces default to no keyboard input at all (see
    // SettingsPanel.qml) - without this, the resolution/position/scale
    // fields below could never actually receive typed input at all, no
    // matter what QML-level focus() they had.
    wantsKeyboardFocus: true

    // ddcutil detect is only worth re-running when the set of monitors
    // ddcutil can actually see might have changed - once here at
    // startup (this instance is created once, eagerly, when quickshell
    // starts - see Dashboard.qml's dashWindow Variants), and again in
    // applyChanges() below whenever an Apply actually changes a
    // monitor's enabled/disabled state. Not on every panel open/close
    // and not on every Apply in general - those don't change which
    // physical displays exist.
    Component.onCompleted: root.detectDdcDisplays()

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
    // monitors.json on load (see screensStoreProcess) for monitors not
    // touched yet this session.
    property var preferredModes: ({})

    function setPreferredMode(name, value) {
        const updated = Object.assign({}, root.preferredModes)
        updated[name] = value
        root.preferredModes = updated
    }

    // Workspace numbers (1-5) pinned to each monitor, keyed by name -
    // staged across multiple monitors like pendingEnabled (not discarded
    // when a different monitor is selected), applied and persisted into
    // monitors.json's per-monitor "workspaces" array on Apply. Toggling
    // one off here only stops it from being reasserted on future logins
    // - Hyprland has no "unbind" for an already-running session, so an
    // open workspace may need a manual move (or a restart) to actually
    // leave its old monitor immediately.
    property var pendingWorkspaces: ({})

    function workspacesFor(name) {
        if (root.pendingWorkspaces[name] !== undefined) return root.pendingWorkspaces[name]
        const stored = root.screensStore[name]
        return (stored && stored.workspaces) ? stored.workspaces : []
    }

    function toggleWorkspace(name, num) {
        if (!name) return
        const updated = Object.assign({}, root.pendingWorkspaces)
        const current = root.workspacesFor(name).slice()
        const idx = current.indexOf(num)

        if (idx >= 0) {
            current.splice(idx, 1)
            updated[name] = current
        } else {
            // Pinning a workspace that's currently owned by a different
            // monitor moves it here instead of being a no-op - only one
            // monitor may hold a given workspace number at a time (see
            // ownerOf()/boundElsewhere), and previously the button for
            // an owned-elsewhere workspace was just disabled outright,
            // leaving no way to actually reassign it short of first
            // hunting down whichever monitor owned it and unpinning it
            // there.
            const owner = root.ownerOf(num, name)
            if (owner) {
                const ownerList = root.workspacesFor(owner).slice()
                const ownerIdx = ownerList.indexOf(num)
                if (ownerIdx >= 0) {
                    ownerList.splice(ownerIdx, 1)
                    updated[owner] = ownerList
                }
            }
            current.push(num)
            updated[name] = current
        }

        root.pendingWorkspaces = updated
    }

    // Which monitor other than `exceptName` currently has workspace
    // `num` pinned, if any - used so the workspace-pin buttons can flag
    // a workspace that's already claimed elsewhere (red border) and so
    // toggleWorkspace() knows which monitor to unpin it from when
    // reassigning it.
    function ownerOf(num, exceptName) {
        for (const m of root.monitors) {
            if (m.name === exceptName) continue
            if (root.workspacesFor(m.name).includes(num)) return m.name
        }
        return ""
    }

    // Fail-safe run at the top of every applyChanges(): toggleWorkspace()
    // already reassigns (rather than duplicates) a workspace pinned
    // elsewhere for clicks made through this session, but a monitors.json
    // left over from before that existed, or edited by hand, could still
    // have the same workspace number pinned to two monitors. If so, keep
    // it only on whichever of those monitors sits closest to (0, 0) and
    // drop it from the rest, rather than sending
    // Hyprland a workspace_rule for the same workspace pointed at
    // several outputs.
    function resolveWorkspaceCollisions() {
        const owners = {}
        for (const m of root.monitors) {
            for (const num of root.workspacesFor(m.name)) {
                if (!owners[num]) owners[num] = []
                owners[num].push(m.name)
            }
        }

        const updated = Object.assign({}, root.pendingWorkspaces)
        let changed = false

        for (const numStr in owners) {
            const names = owners[numStr]
            if (names.length <= 1) continue
            const num = parseInt(numStr, 10)

            let keepName = names[0]
            let keepDist = Infinity
            for (const name of names) {
                const state = root.effectiveStateFor(name)
                const dist = state ? Math.hypot(state.x || 0, state.y || 0) : Infinity
                if (dist < keepDist) {
                    keepDist = dist
                    keepName = name
                }
            }

            for (const name of names) {
                if (name === keepName) continue
                const list = (updated[name] !== undefined ? updated[name] : root.workspacesFor(name)).slice()
                const idx = list.indexOf(num)
                if (idx >= 0) {
                    list.splice(idx, 1)
                    updated[name] = list
                    changed = true
                }
            }
        }

        if (changed) root.pendingWorkspaces = updated
    }

    // Fail-safe for a monitor that ends up with zero workspaces pinned
    // to it after this Apply (e.g. every one of its 1-5 pins just got
    // toggled off) - without anything bound to it, that monitor is
    // unreachable via workspace switching until Hyprland happens to
    // hand it a spare number on its own, and even then that assignment
    // never makes it into monitors.json/apply-monitors.sh, so it
    // doesn't survive a restart. Gives it the lowest number > 5 that no
    // other monitor already uses (1-5 stays reserved for deliberate
    // pins), so an enabled monitor is never left with nothing at all.
    function resolveEmptyWorkspaceFailsafe() {
        const used = new Set()
        for (const m of root.monitors) {
            for (const num of root.workspacesFor(m.name)) used.add(num)
        }

        const updated = Object.assign({}, root.pendingWorkspaces)
        let nextSpare = 6

        for (const m of root.monitors) {
            if (!root.enabledFor(m.name)) continue
            if (root.workspacesFor(m.name).length > 0) continue

            while (used.has(nextSpare)) nextSpare++
            used.add(nextSpare)
            updated[m.name] = [nextSpare]
        }

        root.pendingWorkspaces = updated
    }

    // One-shot x/y override applied only during applyChanges() (see
    // resolveOriginFailsafe below), never persisted as staged UI state
    // the way pendingEnabled/edited are - cleared again the moment
    // Apply finishes building its output.
    property var positionOverrides: ({})

    // Fail-safe for the exact bug reported live: resetting
    // hyprland.lua's monitor config and then disabling every display
    // except one that's been moved away from (0, 0) leaves nothing
    // anchored at the origin - the bar/wallpaper/dashboard (all of
    // which live on primaryMonitor, see Bar.qml/effectivePrimaryName)
    // then vanish until something else forces a relayout (e.g. opening
    // rofi). If no enabled monitor already sits at (0, 0) after this
    // Apply, force the primary monitor there - it's guaranteed enabled
    // (MonitorCard's own onToggleEnabled refuses to disable it), so
    // it's always a safe thing to anchor at the origin. Falls back to
    // whichever monitor is enabled if primaryMonitor itself is stale/
    // missing.
    function resolveOriginFailsafe(touched) {
        const anyAtOrigin = root.monitors.some(m => {
            const state = root.effectiveStateFor(m.name)
            return state && !state.disabled && state.x === 0 && state.y === 0
        })
        if (anyAtOrigin) return

        // Has to actually be enabled - overriding a disabled monitor's
        // position would do nothing (effectiveStateFor never reports an
        // explicit position for a disabled monitor, and buildMonitorLine
        // sends a plain disabled=true line for it regardless).
        let fallbackName = (root.baseFor(root.primaryMonitor) && root.enabledFor(root.primaryMonitor))
            ? root.primaryMonitor
            : ""
        if (!fallbackName) {
            const firstEnabled = root.monitors.find(m => root.enabledFor(m.name))
            fallbackName = firstEnabled ? firstEnabled.name : ""
        }
        if (!fallbackName) return

        const overrides = Object.assign({}, root.positionOverrides)
        overrides[fallbackName] = { x: 0, y: 0 }
        root.positionOverrides = overrides
        touched.add(fallbackName)
    }

    readonly property bool dirty: root.selectedDirty
        || Object.keys(root.pendingEnabled).length > 0
        || Object.keys(root.pendingBrightness).length > 0
        || Object.keys(root.pendingWorkspaces).length > 0

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
    // for a disabled monitor, its remembered monitors.json values) for
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
        root.pendingWorkspaces = ({})
        root.pendingStrictWorkspaceWidget = undefined
        root.pendingShowEmptyWidget = undefined
        root.pendingShowEmptyOsd = undefined
        root.refreshMonitors()
    }

    function refreshMonitors() {
        monitorsProcess.running = false
        monitorsProcess.running = true
    }

    // Resolves what a monitor's width/height/refresh/x/y/scale/mode
    // "should" be right now - the single source of truth used both to
    // build the hl.monitor() line for Apply and to populate the input
    // boxes/monitors.json snapshot, so those three things can never
    // disagree with each other.
    //
    // For a disabled monitor, hyprctl's own geometry may be a stale
    // placeholder (0x0, etc.) since nothing's actually driving it -
    // falls back to whatever monitors.json remembers for it instead.
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
        const override = root.positionOverrides[name]

        const width = e.width !== undefined ? e.width : remembered.width
        const height = e.height !== undefined ? e.height : remembered.height
        const refresh = e.refresh !== undefined
            ? e.refresh
            : (remembered.refreshRate !== undefined ? remembered.refreshRate : remembered.refresh)
        const x = override ? override.x : (e.x !== undefined ? e.x : remembered.x)
        const y = override ? override.y : (e.y !== undefined ? e.y : remembered.y)
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
        // A monitor being (re-)enabled with a monitors.json entry has
        // trustworthy remembered geometry too, same as one that was
        // already active - without this, re-enabling a disabled
        // monitor without editing anything fell back to
        // "preferred"/"auto" and silently discarded exactly the
        // remembered values the input boxes were already showing.
        const hasRememberedGeometry = wasActive || !!stored
        const usesExplicitMode = isSelected
            ? (!root.preferredModes[name] && (hasRememberedGeometry || e.width !== undefined || e.height !== undefined))
            : hasRememberedGeometry
        const usesExplicitPosition = !!override || hasRememberedGeometry || e.x !== undefined || e.y !== undefined

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

        // Commit any staged checkbox changes (see effectiveStrict.../
        // effectiveShowEmpty* above) into the real properties first -
        // everything below (and storeSnapshot's __-prefixed keys) reads
        // the real property, not the pending/effective one.
        if (root.pendingStrictWorkspaceWidget !== undefined) root.strictWorkspaceWidget = root.pendingStrictWorkspaceWidget
        if (root.pendingShowEmptyWidget !== undefined) root.showEmptyWidget = root.pendingShowEmptyWidget
        if (root.pendingShowEmptyOsd !== undefined) root.showEmptyOsd = root.pendingShowEmptyOsd

        // Resolve any workspace pinned to more than one monitor before
        // anything else below reads pendingWorkspaces/workspacesFor().
        root.resolveWorkspaceCollisions()

        // Then make sure nothing was left with zero workspaces at all.
        root.resolveEmptyWorkspaceFailsafe()

        // Only touched monitors are actually sent live - the selected
        // one (if edited) plus any right-clicked enable/disable
        // toggles - not every monitor every time, which used to
        // trigger Hyprland's layout reflow for displays nobody asked to
        // change.
        const touched = new Set(Object.keys(root.pendingEnabled))
        if (root.selectedDirty && root.selectedName) {
            touched.add(root.selectedName)
        }

        // Make sure this Apply doesn't leave every enabled monitor away
        // from the origin - may add the primary monitor to `touched`
        // and stage an x/y override for it.
        root.resolveOriginFailsafe(touched)

        const sendLines = []
        for (const name of touched) {
            const line = root.buildMonitorLine(name)
            if (line) sendLines.push(line)
        }

        // Workspace-button toggles resend that monitor's whole current
        // workspace list (not just the number just clicked) - same
        // "touched monitor gets its full effective state resent"
        // approach buildMonitorLine already uses.
        for (const name of Object.keys(root.pendingWorkspaces)) {
            for (const num of root.workspacesFor(name)) {
                sendLines.push(`hl.workspace_rule({ workspace = "${num}", monitor = "${name}" })`)
            }
        }

        // monitors.json persists the *whole* layout, not just what
        // changed this time, since apply-monitors.sh replays every
        // entry's "line" from scratch at login (hyprland.lua only
        // defines DP-1) - and doubles as the remembered per-monitor
        // state, so re-enabling a monitor later shows exactly what it
        // was just set to (or, if untouched, whatever it already
        // remembered).
        //
        // The "__"-prefixed global flags (committed from pending* just
        // above, if this Apply changed any) live in this same file under
        // non-monitor-name keys - carried over
        // explicitly here since this rebuild only otherwise iterates
        // root.monitors, and would silently drop them on every Apply
        // for anything else (a resolution change, enabling a display,
        // etc.) otherwise.
        const storeSnapshot = {
            __strictWorkspaceWidget: root.strictWorkspaceWidget,
            __showEmptyWidget: root.showEmptyWidget,
            __showEmptyOsd: root.showEmptyOsd
        }
        for (const m of root.monitors) {
            const line = root.buildMonitorLine(m.name)
            const state = root.effectiveStateFor(m.name)
            if (state && line) {
                storeSnapshot[m.name] = {
                    disabled: state.disabled,
                    width: state.width,
                    height: state.height,
                    refresh: state.refresh,
                    x: state.x,
                    y: state.y,
                    scale: state.scale,
                    mode: state.mode,
                    workspaces: root.workspacesFor(m.name),
                    line
                }
            }
        }

        root.screensStore = storeSnapshot
        monitorsFile.setText(JSON.stringify(storeSnapshot, null, 2) + "\n")

        if (sendLines.length > 0) {
            const script = sendLines.map(l => `hyprctl eval '${l}'`).join(" ; ")
            console.log("ScreenSettings: applying:\n" + script)
            applyProcess.command = ["sh", "-c", script]
            applyProcess.running = false
            applyProcess.running = true
        }

        root.applyBrightness()

        // Re-detect only when this Apply actually changed some
        // monitor's enabled/disabled state - a newly enabled (or
        // physically powered on) monitor needs a fresh ddcBusNumbers
        // entry to be reachable at all, but nothing else applied here
        // (position/resolution/brightness) changes which displays
        // ddcutil can see.
        if (Object.keys(root.pendingEnabled).length > 0) {
            root.detectDdcDisplays()
        }

        root.pendingEnabled = ({})
        root.pendingWorkspaces = ({})
        root.positionOverrides = ({})
        root.edited = ({})
        root.selectedDirty = false
        // preferredMode intentionally left as-is - Apply shouldn't flip
        // the toggle back to "Manual" for the monitor you just applied.
    }

    // ddcutil detection deliberately does NOT run here (i.e. not on
    // every panel open) - see Component.onCompleted and applyChanges()
    // below for the only two triggers.
    onActiveChanged: {
        if (root.active) {
            root.pendingEnabled = ({})
            root.pendingWorkspaces = ({})
            root.pendingStrictWorkspaceWidget = undefined
            root.pendingShowEmptyWidget = undefined
            root.pendingShowEmptyOsd = undefined
            root.positionOverrides = ({})
            root.edited = ({})
            root.selectedDirty = false
            root.pendingBrightness = ({})
            root.refreshMonitors()
            root.loadScreensStore()
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

    // ---------------- combined monitor state (monitors.json) ----------------
    // One file now covers both of what used to be two: the hl.monitor()
    // eval lines scripts/apply-monitors.sh replays at login, and the
    // remembered width/height/refresh/x/y/scale/mode geometry
    // effectiveStateFor() above falls back to for a disabled monitor
    // (whose own hyprctl geometry is a stale placeholder). Lives under
    // the quickshell config dir rather than hypr's, since this panel is
    // the only thing that ever reads or writes it - hyprland.lua's
    // autostart block only shells out to apply-monitors.sh, which reads
    // this file itself.
    property var screensStore: ({})

    function loadScreensStore() {
        screensStoreProcess.running = false
        screensStoreProcess.running = true
    }

    // Global (not per-monitor) toggles, all stored in this same
    // monitors.json under "__"-prefixed keys so none are mistaken for a
    // monitor name by anything that iterates the file's other keys, and
    // all take effect immediately on click - they're display
    // preferences for other components (WorkspaceRow.qml/WorkspaceOsd.qml),
    // not live Hyprland/hardware changes, so none need the staged
    // edit + Apply flow the rest of this panel uses.
    //
    // strictWorkspaceWidget: whether WorkspaceRow.qml's bar widget shows
    // workspaces past id 5 at all - the "unmanaged" spare numbers
    // Hyprland hands a monitor with nothing explicitly pinned to it (see
    // resolveEmptyWorkspaceFailsafe above).
    //
    // showEmptyWidget/showEmptyOsd: whether workspaces 1-5 pinned to a
    // monitor but not currently existing in Hyprland (nobody's switched
    // to them yet this session, so Hyprland hasn't created them) still
    // show as an empty placeholder box in WorkspaceRow.qml/WorkspaceOsd.qml,
    // instead of only appearing once they're actually visited.
    property bool strictWorkspaceWidget: false
    property bool showEmptyWidget: false
    property bool showEmptyOsd: false

    // Staged like `edited`/pendingWorkspaces above now, not written
    // through immediately - undefined means "no pending change, use the
    // real property as-is". Cleared (back to undefined) on selectMonitor()
    // and panel reopen, same as the workspace pins, so clicking a
    // checkbox and then switching monitors before Apply discards it
    // instead of persisting.
    property var pendingStrictWorkspaceWidget: undefined
    property var pendingShowEmptyWidget: undefined
    property var pendingShowEmptyOsd: undefined

    readonly property bool effectiveStrictWorkspaceWidget: root.pendingStrictWorkspaceWidget !== undefined
        ? root.pendingStrictWorkspaceWidget : root.strictWorkspaceWidget
    readonly property bool effectiveShowEmptyWidget: root.pendingShowEmptyWidget !== undefined
        ? root.pendingShowEmptyWidget : root.showEmptyWidget
    readonly property bool effectiveShowEmptyOsd: root.pendingShowEmptyOsd !== undefined
        ? root.pendingShowEmptyOsd : root.showEmptyOsd

    function toggleStrictWorkspaceWidget() {
        root.pendingStrictWorkspaceWidget = !root.effectiveStrictWorkspaceWidget
        root.selectedDirty = true
    }

    function toggleShowEmptyWidget() {
        root.pendingShowEmptyWidget = !root.effectiveShowEmptyWidget
        root.selectedDirty = true
    }

    function toggleShowEmptyOsd() {
        root.pendingShowEmptyOsd = !root.effectiveShowEmptyOsd
        root.selectedDirty = true
    }

    Process {
        id: screensStoreProcess
        // Read via `cat` (like every other read in this file goes
        // through Process/hyprctl) rather than FileView, so a missing
        // file (first run) just yields empty stdout instead of needing
        // to reason about FileView's own missing-file behavior.
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/monitors.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.screensStore = parsed
                    root.strictWorkspaceWidget = !!parsed.__strictWorkspaceWidget
                    root.showEmptyWidget = !!parsed.__showEmptyWidget
                    root.showEmptyOsd = !!parsed.__showEmptyOsd
                    // Seed preferredModes from what was last saved, for
                    // any monitor not already touched this session -
                    // otherwise a disabled monitor remembered as
                    // "preferred" would show "Manual" until reselected
                    // once quickshell restarts. "__"-prefixed keys
                    // (__strictWorkspaceWidget) aren't monitor names -
                    // skipped here rather than seeding a stray,
                    // meaningless preferredModes entry for them.
                    const seeded = Object.assign({}, root.preferredModes)
                    for (const name in parsed) {
                        if (name.startsWith("__")) continue
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
        id: monitorsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/monitors.json"
        // Write-only from here (screensStoreProcess above is what reads
        // it back, and apply-monitors.sh is what replays it at login) -
        // no need to preload/read it back through this FileView too.
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

    function queueBrightnessQueries() {
        root.ddcQueryQueue = Object.keys(root.ddcBusNumbers)
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
            + hintSeparator.anchors.topMargin + hintSeparator.height
            + hintRow.anchors.topMargin + hintRow.height

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
                        text: (root.selectedName.length > 0 ? root.selectedName : "Display") + " mode:"
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

                // Reduced to root.uiScale * 0.75 (both these rows and
                // their "x"/"@"/","  separators) so the workspace pins,
                // strict-widget and show-empty rows below all still fit
                // without pushing the panel past the max-height clamp
                // (see SettingsPanel.qml's maxAvailableHeight).
                readonly property real geometryUiScale: root.uiScale * 0.75

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(10, root.uiScale)
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
                        uiScale: root.geometryUiScale
                        label: "Width"
                        value: root.displayFor.width !== undefined ? String(root.displayFor.width) : ""
                        onEdited: (text) => root.setEdited("width", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(8, root.geometryUiScale)
                        text: "x"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.geometryUiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.geometryUiScale
                        label: "Height"
                        value: root.displayFor.height !== undefined ? String(root.displayFor.height) : ""
                        onEdited: (text) => root.setEdited("height", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(8, root.geometryUiScale)
                        text: "@"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.geometryUiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.geometryUiScale
                        label: "Refresh Rate"
                        value: root.displayFor.refresh !== undefined ? String(root.displayFor.refresh) : ""
                        onEdited: (text) => root.setEdited("refresh", parseFloat(text) || 60)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(6, root.uiScale)
                    spacing: Config.scaled(6, root.uiScale)

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.geometryUiScale
                        label: "X Pos"
                        value: root.displayFor.x !== undefined ? String(root.displayFor.x) : ""
                        onEdited: (text) => root.setEdited("x", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(8, root.geometryUiScale)
                        text: "x"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.geometryUiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.geometryUiScale
                        label: "Y Pos"
                        value: root.displayFor.y !== undefined ? String(root.displayFor.y) : ""
                        onEdited: (text) => root.setEdited("y", parseInt(text, 10) || 0)
                    }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Config.scaled(8, root.geometryUiScale)
                        text: ","
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.geometryUiScale)
                        font.bold: true
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.geometryUiScale
                        label: "Scale"
                        value: root.displayFor.scale !== undefined ? String(root.displayFor.scale) : ""
                        onEdited: (text) => root.setEdited("scale", parseFloat(text) || 1)
                    }
                }

                // ---------------- workspace pins (1-5) ----------------
                // Binds the selected monitor to any of workspaces 1-5
                // (hl.workspace_rule({ workspace, monitor })) - several
                // can be lit at once, since Hyprland allows more than
                // one workspace defaulting to the same monitor. Below
                // the geometry rows now, its own row.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(10, root.uiScale)
                    spacing: Config.scaled(8, root.uiScale)

                    Repeater {
                        model: [1, 2, 3, 4, 5]

                        DashCard {
                            id: wsButton
                            required property int modelData

                            readonly property bool bound: root.workspacesFor(root.selectedName).includes(modelData)
                            // Non-empty when some *other* monitor already
                            // claims this workspace number - shown red as
                            // a warning, but still clickable: clicking it
                            // reassigns the workspace to this monitor
                            // instead (see toggleWorkspace()), rather than
                            // being a dead end that only the owning
                            // monitor's own card could undo.
                            readonly property string ownerElsewhere: root.ownerOf(modelData, root.selectedName)
                            readonly property bool boundElsewhere: wsButton.ownerElsewhere !== ""

                            Layout.preferredWidth: Config.scaled(28, root.uiScale)
                            Layout.preferredHeight: Config.scaled(28, root.uiScale)
                            uiScale: root.uiScale
                            color: wsMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                            border.color: wsButton.boundElsewhere
                                ? Config.fgcolorred
                                : (wsButton.bound ? Config.fgcolor : Config.fgcolordark)

                            Text {
                                anchors.centerIn: parent
                                text: String(wsButton.modelData)
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            MouseArea {
                                id: wsMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    contentWrapper.forceActiveFocus()
                                    root.toggleWorkspace(root.selectedName, wsButton.modelData)
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ---------------- strict workspace widget toggle ----------------
                // Global, not per-monitor - controls whether
                // WorkspaceRow.qml's bar widget shows workspaces past
                // id 5 at all. Staged like the workspace pins above -
                // only takes effect on Apply, discarded if a different
                // monitor is selected first (see
                // effectiveStrictWorkspaceWidget/toggleStrictWorkspaceWidget()
                // above).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(16, root.uiScale)
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Strict widget:"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.toggleStrictWorkspaceWidget()
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.effectiveStrictWorkspaceWidget ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.toggleStrictWorkspaceWidget()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ---------------- show empty toggle (widget + osd) ----------------
                // Also global - whether a workspace 1-5 pinned to a
                // monitor but not yet existing in Hyprland (nobody's
                // switched to it this session, so Hyprland hasn't
                // created it) still shows as an empty placeholder box in
                // WorkspaceRow.qml/WorkspaceOsd.qml, rather than only
                // appearing once actually visited. Two independent
                // checkboxes since the bar widget and the OSD are
                // separate pieces of UI someone may only want one of.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(8, root.uiScale)
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Show Empty:"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.effectiveShowEmptyWidget ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.toggleShowEmptyWidget()
                            }
                        }
                    }

                    Text {
                        text: "Widget"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.toggleShowEmptyWidget()
                            }
                        }
                    }

                    Item { Layout.preferredWidth: Config.scaled(16, root.uiScale) }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.effectiveShowEmptyOsd ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.toggleShowEmptyOsd()
                            }
                        }
                    }

                    Text {
                        text: "OSD"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.toggleShowEmptyOsd()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ---------------- bottom of right pane: identify + apply ----------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(14, root.uiScale)

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

        // ---------------- separator ----------------
        // Stops at the same margins as contentRow above, not its own
        // separate fixed inset.
        Rectangle {
            id: hintSeparator
            anchors {
                left: parent.left
                right: parent.right
                top: contentRow.bottom
                topMargin: Config.scaled(14, root.uiScale)
                margins: contentRow.margins
            }
            height: Config.scaled(2, root.uiScale)
            color: Config.fgcolor
        }

        // ---------------- hint row ----------------
        RowLayout {
            id: hintRow

            anchors {
                left: parent.left
                right: parent.right
                top: hintSeparator.bottom
                topMargin: Config.scaled(10, root.uiScale)
                margins: contentRow.margins
            }
            spacing: Config.scaled(16, root.uiScale)

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-right-symbolic")
                label: "Enable/Disable"
            }

            HintItem {
                uiScale: root.uiScale
                prefix: "Dbl"
                iconSource: Quickshell.iconPath("input-mouse-click-left-symbolic")
                label: "Set as Primary"
            }

            Item { Layout.fillWidth: true }
        }
    }

    Timer {
        id: identifyTimer
        interval: 3000
        repeat: false
        onTriggered: root.identifying = false
    }
}

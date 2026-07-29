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

    // Dashboard.qml's shared root Scope - ddcutil/brightnessctl
    // detection and every monitor's live/pending brightness now live
    // there instead of on this instance (brightness is a property of
    // the physical monitor, not of whichever screen's dashboard is
    // open, and Bar.qml's BrightnessControl widget needs to reach it
    // too). See Dashboard.qml's own brightness section for what this
    // actually holds.
    property var dashboardRoot: null

    // loadScreensStore() needs to run eagerly here, not just on panel
    // open (see onActiveChanged below) - seedDefaultWorkspacesIfFresh()
    // (see effectivePrimaryName/screensStoreProcess further down) has to
    // fire the moment quickshell starts on a brand new setup, so the
    // primary monitor already shows all five workspaces preselected the
    // very first time Screen Settings gets opened, rather than only
    // after it's been opened once already.
    Component.onCompleted: root.loadScreensStore()

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
    onPrimaryMonitorChanged: root.seedDefaultWorkspacesIfFresh()

    // primaryMonitor itself defaults to a hardcoded output name
    // ("DP-1", see Dashboard.qml) and isn't persisted to disk, so on a
    // genuinely fresh setup (or a different machine entirely) it can
    // easily point at a name nothing is actually connected to. Same
    // "resolve to whichever screen is actually there" fallback Bar.qml/
    // LockScreen.qml already use, so seedDefaultWorkspacesIfFresh()
    // below seeds the monitor Quickshell will actually treat as primary
    // instead of a name that might not exist at all.
    readonly property string effectivePrimaryName: {
        const preferred = root.primaryMonitor
        if (preferred && Quickshell.screens.some(s => s.name === preferred)) return preferred
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

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

    // Width/height/refresh/x/y/scale edits, keyed by monitor name -
    // staged across monitor switches like pendingEnabled/pendingBrightness
    // below (not discarded until Apply runs or the panel is reopened),
    // so editing several displays in a row and applying once actually
    // sends all of them. Keyed per-name deliberately, not a single flat
    // {width, height, ...} blob for "whichever monitor is selected" -
    // that was tried once already and broke: with only one shared blob,
    // switching monitors made the input boxes show leftover values
    // typed for the *previous* monitor instead of that monitor's own
    // real state, since nothing distinguished which monitor a value
    // actually belonged to. effectiveStateFor() below only ever reads
    // root.edited[name], so a value can never leak onto a different
    // monitor's fields this way.
    property var edited: ({})
    // Still monitor-selection-scoped (discarded on selectMonitor()) -
    // used for things that are genuinely tied to "whatever's currently
    // selected in this panel" rather than a specific monitor's own
    // state: the checkbox toggles below (toggleStrictWorkspaceWidget
    // etc.) and togglePreferredMode(). Geometry edits no longer rely on
    // this for correctness (see effectiveStateFor()) - only for also
    // marking the then-selected monitor as touched, alongside the
    // dedicated edited-keys loop in applyChanges().
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
    // monitors.json's per-monitor "workspaces" array on Apply. A
    // workspace can only ever be *reassigned* to a different monitor
    // through the buttons below (see toggleWorkspace()), never fully
    // unbound - every workspace 1-5 always belongs to exactly one
    // monitor (see seedDefaultWorkspacesIfFresh() and
    // resolveDisabledMonitorWorkspaces() for how that stays true on a
    // fresh setup or when a monitor gets disabled).
    property var pendingWorkspaces: ({})

    function workspacesFor(name) {
        if (root.pendingWorkspaces[name] !== undefined) return root.pendingWorkspaces[name]
        const stored = root.screensStore[name]
        return (stored && stored.workspaces) ? stored.workspaces : []
    }

    // Reassigns workspace `num` to monitor `name`, stealing it from
    // whichever monitor currently owns it if any (only one monitor may
    // hold a given number at a time - see ownerOf()) - never a plain
    // toggle-off. A workspace already bound to `name` is a no-op:
    // deactivating a workspace entirely (leaving it owned by nobody)
    // isn't something the buttons allow anymore, since every workspace
    // 1-5 is meant to always be reachable from some monitor.
    function toggleWorkspace(name, num) {
        if (!name) return
        if (root.workspacesFor(name).includes(num)) return

        const updated = Object.assign({}, root.pendingWorkspaces)
        const current = root.workspacesFor(name).slice()

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

        root.pendingWorkspaces = updated
    }

    // Which monitor other than `exceptName` currently has workspace
    // `num` pinned, if any - used so the workspace-pin buttons can flag
    // a workspace that's already claimed elsewhere (dimmed border) and
    // so toggleWorkspace() knows which monitor to unpin it from when
    // reassigning it.
    function ownerOf(num, exceptName) {
        for (const m of root.monitors) {
            if (m.name === exceptName) continue
            if (root.workspacesFor(m.name).includes(num)) return m.name
        }
        return ""
    }

    // Fail-safe run at the top of every applyChanges(), before anything
    // else that reads workspacesFor() - a monitor being disabled this
    // Apply (pendingEnabled, right-click enable/disable, distinct from
    // toggleWorkspace()'s per-workspace reassignment) would otherwise
    // leave whatever workspaces it owned pinned to a monitor nobody can
    // switch to anymore, unreachable until it's re-enabled. Moved to the
    // primary monitor instead - guaranteed enabled (see
    // resolveOriginFailsafe below) so always a safe place to land them.
    function resolveDisabledMonitorWorkspaces() {
        const updated = Object.assign({}, root.pendingWorkspaces)
        let changed = false

        for (const m of root.monitors) {
            if (root.enabledFor(m.name)) continue
            if (m.name === root.primaryMonitor) continue

            const current = root.workspacesFor(m.name)
            if (current.length === 0) continue

            const primaryList = (updated[root.primaryMonitor] !== undefined
                ? updated[root.primaryMonitor]
                : root.workspacesFor(root.primaryMonitor)).slice()
            for (const num of current) {
                if (!primaryList.includes(num)) primaryList.push(num)
            }

            updated[root.primaryMonitor] = primaryList
            updated[m.name] = []
            changed = true
        }

        if (changed) root.pendingWorkspaces = updated
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

    // Numbers > 5 only ever end up in a monitor's pinned list through
    // resolveEmptyWorkspaceFailsafe() below - never through the 1-5
    // pin buttons - so they're derived/ephemeral, not a real saved
    // choice. Run before that fail-safe (and before
    // resolveWorkspaceCollisions(), so a stale spare can't count as a
    // "collision" against anything): without this, a spare handed to a
    // monitor while it had nothing else pinned (e.g. mid-reset) stuck
    // around forever afterwards even once the monitor was later given
    // real 1-5 pins, since toggleWorkspace() only ever appends to
    // whatever was already stored - reported live as a monitor ending
    // up with more workspaces pinned than were ever clicked, one of
    // them an unreachable number with no button to remove it.
    function stripSpareWorkspaces() {
        const updated = Object.assign({}, root.pendingWorkspaces)
        let changed = false

        for (const m of root.monitors) {
            const current = root.workspacesFor(m.name)
            const stripped = current.filter(num => num <= 5)
            if (stripped.length !== current.length) {
                updated[m.name] = stripped
                changed = true
            }
        }

        if (changed) root.pendingWorkspaces = updated
    }

    // Fail-safe for a monitor that ends up with zero workspaces pinned
    // to it after this Apply (e.g. every one of its 1-5 pins just got
    // toggled off, or reassigned to another monitor - since
    // seedDefaultWorkspacesIfFresh() pins all five to the primary
    // monitor on a fresh install, every *other* monitor starts out
    // exactly this "unmanaged" from the very first Apply onward, not
    // just after some later edit) - without anything bound to it, that
    // monitor is unreachable via workspace switching until Hyprland
    // happens to hand it a spare number on its own, and even then that
    // assignment never makes it into monitors.json/apply-monitors.sh,
    // so it doesn't survive a restart. Gives it the lowest number > 5
    // that no other monitor already uses (1-5 stays reserved for
    // deliberate pins), so an enabled monitor is never left stuck on
    // whatever it happened to be showing before this Apply.
    //
    // Runs unconditionally now (previously skipped for a monitor with
    // no prior real monitors.json entry at all - reverted after this
    // read live as DP-2 staying stuck on a workspace 1-5 had just
    // reassigned away to DP-1, only fixable by disabling and
    // re-enabling DP-2 by hand): assigning it a rule AND actually
    // moving it there (see the moveworkspacetomonitor dispatch below,
    // which fires for every monitor in pendingWorkspaces - this
    // included) is exactly what makes an unmanaged monitor immediately
    // reachable instead of silently correct-on-paper-only until
    // something else forces Hyprland to reassign it.
    //
    // Populated fresh by resolveEmptyWorkspaceFailsafe() every time it
    // runs, with whichever monitor names it just handed a brand new
    // spare number this Apply - read afterward in applyChanges() to
    // force those specific monitors onto their new workspace
    // immediately (see the focus dispatch pair there), since a spare
    // number that's never existed before has nothing for
    // moveworkspacetomonitor to actually relocate.
    property var freshSpareMonitors: []

    function resolveEmptyWorkspaceFailsafe() {
        const used = new Set()
        for (const m of root.monitors) {
            for (const num of root.workspacesFor(m.name)) used.add(num)
        }

        const updated = Object.assign({}, root.pendingWorkspaces)
        const fresh = []
        let nextSpare = 6

        for (const m of root.monitors) {
            if (!root.enabledFor(m.name)) continue
            if (root.workspacesFor(m.name).length > 0) continue

            while (used.has(nextSpare)) nextSpare++
            used.add(nextSpare)
            updated[m.name] = [nextSpare]
            fresh.push(m.name)
        }

        root.pendingWorkspaces = updated
        root.freshSpareMonitors = fresh
    }

    // One-shot x/y override applied only during applyChanges() (see
    // resolveOriginFailsafe below), never persisted as staged UI state
    // the way pendingEnabled/edited are - cleared again the moment
    // Apply finishes building its output.
    property var positionOverrides: ({})

    // Fail-safe for two related ways a monitor's *actual* live position
    // can drift out from under what this panel believes it should be -
    // both only ever affecting a monitor this Apply didn't itself
    // explicitly resend a position for, since hyprland.lua's own
    // top-level rule is a blanket `hl.monitor({ output = "auto" })`
    // wildcard: any monitor never (yet) given its own specific
    // per-output override is still governed by that wildcard, not
    // pinned anywhere in particular.
    //
    // 1. Resetting hyprland.lua's monitor config, then disabling every
    //    display except one that's been moved away from (0, 0), leaves
    //    nothing anchored at the origin - the bar/wallpaper/dashboard
    //    (all of which live on primaryMonitor, see Bar.qml/
    //    effectivePrimaryName) then vanish until something else forces
    //    a relayout (e.g. opening rofi).
    //
    // 2. Repositioning *other* monitors without ever re-typing the
    //    primary's own already-correct numbers - so it was never added
    //    to `touched` in the first place - can still move the primary:
    //    confirmed live, Hyprland silently re-runs its own "auto"
    //    placement for a monitor still under that wildcard the moment
    //    some *other* monitor's position changes, even though nothing
    //    in monitors.json/this panel ever asked for that. Reported
    //    live: repositioning two secondary monitors into a real
    //    (non-side-by-side) physical layout, without ever re-typing the
    //    primary's already-correct (0, 0) - so it stayed on "auto" the
    //    whole time - silently kicked the primary over to x=1920 (right
    //    past one of the other two's new width) once those were
    //    explicitly sent.
    //
    // Both are fixed the same way: whenever this Apply is touching
    // anything at all, the primary monitor always gets its own
    // explicit hl.monitor() line too - forced to (0, 0) if nothing else
    // already claims the origin (case 1), otherwise just re-asserting
    // wherever it currently, correctly, already is (case 2, via
    // effectiveStateFor()'s ordinary remembered/live fallback - no
    // override needed since nothing's actually wrong with its intended
    // value, only with it being left unpinned). Skipped entirely when
    // nothing else is touched this Apply either - a checkbox-only or
    // workspace-pin-only Apply isn't perturbing Hyprland's layout at
    // all, so there's nothing for the primary to drift *because of*.
    function resolveOriginFailsafe(touched) {
        if (touched.size === 0) return

        const anyAtOrigin = root.monitors.some(m => {
            const state = root.effectiveStateFor(m.name)
            return state && !state.disabled && state.x === 0 && state.y === 0
        })

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

        if (!anyAtOrigin) {
            const overrides = Object.assign({}, root.positionOverrides)
            overrides[fallbackName] = { x: 0, y: 0 }
            root.positionOverrides = overrides
        }

        touched.add(fallbackName)
    }

    readonly property bool dirty: root.selectedDirty
        || Object.keys(root.pendingEnabled).length > 0
        || (root.dashboardRoot ? Object.keys(root.dashboardRoot.pendingBrightness).length > 0 : false)
        || Object.keys(root.pendingWorkspaces).length > 0
        || Object.keys(root.edited).some(name => Object.keys(root.edited[name]).length > 0)
        // Checked directly (not just via selectedDirty) for the same
        // reason edited/pendingWorkspaces are above - these persist
        // across selectMonitor() now, so relying solely on selectedDirty
        // (which selectMonitor() does reset) would make the Apply
        // button stop glowing after switching monitors despite a
        // checkbox change still being staged.
        || root.pendingStrictWorkspaceWidget !== undefined
        || root.pendingShowEmptyWidget !== undefined
        || root.pendingShowEmptyOsd !== undefined

    function setEdited(key, value) {
        const updated = Object.assign({}, root.edited)
        const forSelected = Object.assign({}, updated[root.selectedName] || {})
        forSelected[key] = value
        updated[root.selectedName] = forSelected
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

    // Always re-queries hyprctl fresh right then - never trusts a
    // cached copy. root.edited is deliberately NOT cleared here anymore
    // (see its own declaration above) - a monitor's staged geometry
    // edit survives switching away and back, only selectedDirty (the
    // checkbox/preferredMode signal, not geometry) resets. Same for
    // root.pendingWorkspaces (workspace-pin buttons) - already keyed
    // per monitor name (never the flat-blob shape edited used to be),
    // so persisting it across switches carries none of that same risk;
    // only the checkbox pending* properties actually need discarding on
    // reselect.
    function selectMonitor(name) {
        root.selectedName = name
        root.selectedDirty = false
        root.displayFor = ({})
        // Deliberately NOT resetting pendingStrictWorkspaceWidget/
        // pendingShowEmptyWidget/pendingShowEmptyOsd here - they're
        // global (not per-monitor) settings, so a checkbox toggle
        // should survive switching to a different monitor's view the
        // same way edited/pendingWorkspaces already do, rather than
        // being silently discarded. Still reset on an actual panel
        // close/reopen (see onActiveChanged below), same as those.
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

        // Per-name lookup, not gated on this being the *currently
        // selected* monitor - see root.edited's own declaration for why
        // that gate used to exist and why it's gone now.
        const e = root.edited[name] || {}
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
        const usesExplicitMode = !root.preferredModes[name]
            && (hasRememberedGeometry || e.width !== undefined || e.height !== undefined)
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

    // writeToDisk (default true - the Set Init button always passes true
    // explicitly, Apply always passes false) controls whether this
    // Apply's *monitor* geometry/workspace-pin data gets written to
    // monitors.json, i.e. whether it's part of what
    // scripts/apply-monitors.sh replays at the next login. Everything
    // else about this function is identical either way - both buttons
    // run the exact same live hyprctl eval calls/fail-safes below, and
    // the Strict Workspace Widget/Show Empty checkboxes always sync to
    // the file regardless of writeToDisk (see near the bottom) since
    // they have no live hyprctl equivalent at all - reading
    // monitors.json is the only way WorkspaceRow.qml/WorkspaceOsd.qml
    // ever learn about them.
    function applyChanges(writeToDisk) {
        if (writeToDisk === undefined) writeToDisk = true
        if (!root.dirty) return

        // Commit any staged checkbox changes (see effectiveStrict.../
        // effectiveShowEmpty* above) into the real properties first -
        // everything below (and storeSnapshot's __-prefixed keys) reads
        // the real property, not the pending/effective one.
        if (root.pendingStrictWorkspaceWidget !== undefined) root.strictWorkspaceWidget = root.pendingStrictWorkspaceWidget
        if (root.pendingShowEmptyWidget !== undefined) root.showEmptyWidget = root.pendingShowEmptyWidget
        if (root.pendingShowEmptyOsd !== undefined) root.showEmptyOsd = root.pendingShowEmptyOsd

        // Snapshot which monitors have no real (1-5) workspace at all in
        // the last-applied config, before any of this Apply's own
        // fail-safes below touch pendingWorkspaces - used after
        // sendLines is built to detect one that's about to gain its
        // first real pin this Apply (see the rescues array further
        // down), so whatever it's currently showing can be rescued
        // rather than left stranded on an now-orphaned unmanaged
        // workspace.
        const wasUnmanaged = new Set()
        for (const m of root.monitors) {
            const stored = root.screensStore[m.name]
            const storedList = (stored && stored.workspaces) ? stored.workspaces : []
            if (!storedList.some(n => n <= 5)) wasUnmanaged.add(m.name)
        }

        // Move any workspace a monitor being disabled this Apply still
        // owns over to the primary monitor first - see
        // resolveDisabledMonitorWorkspaces() above.
        root.resolveDisabledMonitorWorkspaces()

        // Drop any leftover fail-safe spare (> 5) a monitor no longer
        // needs before anything else below reads pendingWorkspaces/
        // workspacesFor() - see stripSpareWorkspaces() above.
        root.stripSpareWorkspaces()

        // Resolve any workspace pinned to more than one monitor before
        // anything else below reads pendingWorkspaces/workspacesFor().
        root.resolveWorkspaceCollisions()

        // Then make sure nothing was left with zero workspaces at all.
        root.resolveEmptyWorkspaceFailsafe()

        // Only touched monitors are actually sent live - any monitor
        // with a staged geometry edit (root.edited, now persisting
        // across monitor switches - see its declaration above), any
        // right-clicked enable/disable toggle, plus whichever monitor
        // is currently selected if selectedDirty (covers
        // togglePreferredMode(), which doesn't touch root.edited at
        // all) - not every monitor every time, which used to trigger
        // Hyprland's layout reflow for displays nobody asked to change.
        const touched = new Set(Object.keys(root.pendingEnabled))
        for (const name of Object.keys(root.edited)) {
            if (Object.keys(root.edited[name]).length > 0) touched.add(name)
        }
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
        // approach buildMonitorLine already uses. Each one also gets an
        // hl.dispatch(hl.dsp.workspace.move(...)) call alongside its
        // workspace_rule - the rule alone only steers where a workspace
        // goes at *creation* (or whenever Hyprland next reassigns it on
        // its own), not one that's already live and sitting on its old
        // monitor with real windows open (e.g. rebinding workspace 2 to
        // DP-1 while Discord's still open on it over on DP-2 - reported
        // live as the pin appearing to do nothing at all). Harmless
        // no-op if that workspace doesn't exist yet.
        //
        // This is the hl.dsp.* equivalent of plain `hyprctl dispatch
        // moveworkspacetomonitor <ws> <monitor>` - confirmed against
        // hyprlang2lua's own dispatcher table (the same converter used
        // to build hyprland.lua from a stock hyprland.conf in the first
        // place). hl.dsp.workspace.move({...}) alone only builds the
        // dispatcher descriptor - hl.dispatch(...) is what actually
        // fires it, same as this hyprland.lua's own keybinds do for any
        // dynamically-built dispatcher (see e.g. its focus-last-monitor
        // submap function).
        for (const name of Object.keys(root.pendingWorkspaces)) {
            for (const num of root.workspacesFor(name)) {
                sendLines.push(`hl.workspace_rule({ workspace = "${num}", monitor = "${name}" })`)
                sendLines.push(`hl.dispatch(hl.dsp.workspace.move({ workspace = "${num}", monitor = "${name}" }))`)
            }
        }

        // Monitors that just got a fresh spare (> 5) from
        // resolveEmptyWorkspaceFailsafe() above need forcing onto it
        // right now, not just a workspace_rule for whenever Hyprland
        // next reassigns them on its own - that spare number has never
        // existed before, so the moveworkspacetomonitor dispatch above
        // has nothing real to relocate for it. Focusing the monitor
        // first, then the workspace, creates it fresh there
        // specifically rather than wherever happens to be focused right
        // now - this is what actually fixes a monitor staying stuck on
        // whatever it showed before this Apply once its old workspace
        // got reassigned elsewhere (reported live: DP-2 stuck showing
        // workspace 2 after it was reassigned entirely to DP-1, only
        // fixable by disabling and re-enabling DP-2 by hand).
        for (const name of root.freshSpareMonitors) {
            const num = root.workspacesFor(name)[0]
            if (num === undefined) continue
            sendLines.push(`hl.dispatch(hl.dsp.focus({ monitor = "${name}" }))`)
            sendLines.push(`hl.dispatch(hl.dsp.focus({ workspace = "${num}" }))`)
        }

        // Monitors that just went from having no real (1-5) workspace at
        // all (wasUnmanaged, snapshotted before this function's own
        // fail-safes ran) to having one or more this Apply - always
        // switched onto the lowest-numbered one just assigned (e.g.
        // workspace 4 if both 4 and 5 got pinned in the same Apply),
        // exactly the same "force it, don't just leave a rule for
        // whenever Hyprland gets around to it" reasoning
        // freshSpareMonitors above uses - otherwise the monitor keeps
        // showing its old unmanaged workspace (with or without windows
        // open on it) until someone manually switches away from it.
        const newlyManaged = []
        for (const name of wasUnmanaged) {
            const managed = root.workspacesFor(name).filter(n => n <= 5)
            if (managed.length === 0) continue
            newlyManaged.push({ monitor: name, newWorkspace: managed.reduce((a, b) => Math.min(a, b)) })
        }
        for (const entry of newlyManaged) {
            sendLines.push(`hl.dispatch(hl.dsp.focus({ monitor = "${entry.monitor}" }))`)
            sendLines.push(`hl.dispatch(hl.dsp.focus({ workspace = "${entry.newWorkspace}" }))`)
        }

        // Any of those same monitors that also had a real window open
        // on their old (live, pre-Apply) active workspace gets that
        // window rescued onto the new one too, via clientsQueryProcess
        // below, rather than left stranded on the now-orphaned
        // workspace only reachable through WorkspaceRow.
        // root.baseFor(name) is the last hyprctl monitors read this
        // panel did - not re-fetched fresh here, same acceptable
        // staleness tradeoff already made elsewhere in this file (e.g.
        // resolveOriginFailsafe's anyAtOrigin check).
        const rescues = []
        for (const entry of newlyManaged) {
            const base = root.baseFor(entry.monitor)
            const oldId = (base && base.activeWorkspace) ? base.activeWorkspace.id : undefined
            if (oldId === undefined || oldId === entry.newWorkspace) continue
            rescues.push({ monitor: entry.monitor, oldWorkspace: oldId, newWorkspace: entry.newWorkspace })
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

        if (writeToDisk) {
            root.screensStore = storeSnapshot
            monitorsFile.setText(JSON.stringify(storeSnapshot, null, 2) + "\n")
        } else {
            // The Strict Workspace Widget/Show Empty checkboxes have no
            // live hyprctl equivalent at all - unlike monitor position/
            // workspace pins (sent straight to Hyprland via the eval
            // calls above regardless of which button this is),
            // WorkspaceRow.qml/WorkspaceOsd.qml only ever learn about
            // these by reading monitors.json. Skipping the write
            // entirely, the same way the rest of an Apply does, would
            // silently make this button never actually apply them.
            //
            // Synced on their own here instead, merged onto whatever's
            // actually on disk right now (root.screensStore, only ever
            // updated by Set Init/here - never by the temporary monitor
            // geometry an Apply computes above) rather than storeSnapshot,
            // which also has this Apply's own temporary per-monitor
            // entries mixed in - those specifically must NOT reach the
            // file.
            const flagsOnly = Object.assign({}, root.screensStore, {
                __strictWorkspaceWidget: root.strictWorkspaceWidget,
                __showEmptyWidget: root.showEmptyWidget,
                __showEmptyOsd: root.showEmptyOsd
            })
            root.screensStore = flagsOnly
            monitorsFile.setText(JSON.stringify(flagsOnly, null, 2) + "\n")
        }

        // Rescuing needs a fresh window list first - deferred through
        // clientsQueryProcess/runApplyScript() rather than sent
        // immediately, so the rescue dispatches land in the same script
        // (and thus the same capture/restore-wrapped run) instead of a
        // separate, later Apply.
        if (rescues.length > 0) {
            root.pendingSendLines = sendLines
            root.pendingRescues = rescues
            clientsQueryProcess.running = false
            clientsQueryProcess.running = true
        } else {
            root.runApplyScript(sendLines)
        }

        root.applyBrightness()

        // Re-detect only when this Apply actually changed some
        // monitor's enabled/disabled state - a newly enabled (or
        // physically powered on) monitor needs a fresh ddcBusNumbers
        // entry to be reachable at all, but nothing else applied here
        // (position/resolution/brightness) changes which displays
        // ddcutil/brightnessctl can see.
        if (Object.keys(root.pendingEnabled).length > 0 && root.dashboardRoot) {
            root.dashboardRoot.detectBrightnessControllers()
        }

        root.pendingEnabled = ({})
        root.pendingWorkspaces = ({})
        root.positionOverrides = ({})
        root.edited = ({})
        root.selectedDirty = false
        // Reset back to undefined now that they've been committed into
        // the real properties above - otherwise dirty (which checks
        // these directly, not just selectedDirty, so a checkbox change
        // survives switching monitors) would keep reporting true and
        // the Apply button would never stop glowing after actually
        // applying.
        root.pendingStrictWorkspaceWidget = undefined
        root.pendingShowEmptyWidget = undefined
        root.pendingShowEmptyOsd = undefined
        // preferredMode intentionally left as-is - Apply shouldn't flip
        // the toggle back to "Manual" for the monitor you just applied.
    }

    // ddcutil/brightnessctl detection deliberately does NOT run here
    // (i.e. not on every panel open) - see Dashboard.qml's own
    // Component.onCompleted and applyChanges() below for the only two
    // triggers.
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
            if (root.dashboardRoot) root.dashboardRoot.pendingBrightness = ({})
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

    // Carries applyChanges()'s already-built sendLines and rescues
    // array across the async hyprctl clients query below - only
    // actually populated when applyChanges() found at least one
    // monitor to rescue windows for.
    property var pendingSendLines: []
    property var pendingRescues: []

    Process {
        id: clientsQueryProcess
        command: ["hyprctl", "-j", "clients"]

        stdout: StdioCollector {
            onStreamFinished: {
                const sendLines = root.pendingSendLines.slice()
                try {
                    const clients = JSON.parse(text)
                    // Every open window still sitting on a monitor's old,
                    // now-orphaned unmanaged workspace gets silently
                    // (follow = false, so focus isn't disturbed) relocated
                    // onto whichever workspace that monitor was just
                    // assigned - see the rescues array built in
                    // applyChanges().
                    for (const rescue of root.pendingRescues) {
                        for (const c of clients) {
                            if (c.workspace && c.workspace.id === rescue.oldWorkspace) {
                                sendLines.push(`hl.dispatch(hl.dsp.window.move({ workspace = "${rescue.newWorkspace}", window = "address:${c.address}", follow = false }))`)
                            }
                        }
                    }
                } catch (e) {
                    console.warn("ScreenSettings: hyprctl clients query failed, skipping unmanaged-window rescue:\n" + text)
                }
                root.pendingSendLines = []
                root.pendingRescues = []
                root.runApplyScript(sendLines)
            }
        }
    }

    // Actually sends this Apply's built-up Lua lines to Hyprland -
    // split out from applyChanges() itself since the window-rescue
    // dispatches need a fresh hyprctl clients query first, deferring
    // this call, whenever applyChanges() found a monitor to rescue
    // windows for (clientsQueryProcess above).
    //
    // Wraps the real lines with a capture/restore pair so Apply never
    // leaves the cursor/focus wherever the *last* dispatch in the chain
    // happened to land (e.g. on whichever monitor just got a fresh spare
    // workspace forced onto it, or the TV a rescue above just moved
    // windows onto) - reported live as every Apply visibly yanking focus
    // over to some other monitor entirely. hl.get_active_workspace()
    // captures whatever's actually focused (wherever the dashboard/this
    // panel was opened) before any of this Apply's own dispatches run,
    // into a plain Lua global - relies on every hyprctl eval call in
    // this chain sharing one persistent Lua state for the whole
    // Hyprland session (the same reason hl.dsp.* is even resolvable
    // this way at all, called bare with no keybind context), so a
    // global set in the first eval call is still readable in the last
    // one. Restored as the very last dispatch in the chain - untested
    // live (no way to run Hyprland from here), so if the cursor still
    // ends up somewhere unexpected after Apply, this global-persistence
    // assumption is the first thing to check.
    function runApplyScript(sendLines) {
        if (sendLines.length === 0) return

        const captureLine = "do local w = hl.get_active_workspace(); if w then _PurpuraRestoreWorkspace = tostring(w.id) end end"
        const restoreLine = "if _PurpuraRestoreWorkspace then hl.dispatch(hl.dsp.focus({ workspace = _PurpuraRestoreWorkspace })) end"
        const finalLines = [captureLine].concat(sendLines).concat([restoreLine])

        const script = finalLines.map(l => `hyprctl eval '${l}'`).join(" ; ")
        console.log("ScreenSettings: applying:\n" + script)
        applyProcess.command = ["sh", "-c", script]
        applyProcess.running = false
        applyProcess.running = true
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

    // Whether monitors.json currently has at least one real (non-"__")
    // monitor entry - live, re-evaluated from root.screensStore on
    // every read, NOT captured once and frozen. An earlier version
    // captured this only on the very first read of the session and
    // never again, on the theory that a monitor's own workspace
    // fail-safe needed "brand new setup" to keep meaning that for the
    // rest of the session - but nothing here still needs that (see
    // resolveEmptyWorkspaceFailsafe, unconditional now), and freezing
    // it broke exactly the workflow it was meant to support: deleting
    // monitors.json and letting Hyprland auto-place everything again
    // mid-session, while quickshell itself (and this property) had
    // already lived through the *old* monitors.json existing earlier
    // in the same session, and would stay stuck believing a real
    // config still existed even after it was deleted.
    readonly property bool hasRealMonitorsConfig: Object.keys(root.screensStore).some(k => !k.startsWith("__"))

    // Seeds all five workspaces onto whichever monitor will actually be
    // treated as primary (effectivePrimaryName, not the raw
    // primaryMonitor property - see its own declaration for why)
    // whenever monitors.json currently has no real config at all -
    // every workspace 1-5 always belongs to exactly one monitor now
    // (see toggleWorkspace()'s no-op-if-already-bound guard), so a
    // fresh setup needs a starting owner for all of them rather than
    // none. Guarded on pendingWorkspaces not already having an entry
    // for that monitor, rather than a separate one-shot flag, so this
    // can re-seed after a later reopen/Apply reset pendingWorkspaces
    // back to {} while still genuinely fresh, but never overwrites an
    // in-progress edit the user's already made this same session.
    // Called both from screensStoreProcess below (every read, not just
    // the first) and onPrimaryMonitorChanged above, in case the primary
    // changes while still on a fresh, unconfigured setup.
    function seedDefaultWorkspacesIfFresh() {
        if (root.hasRealMonitorsConfig) return
        if (!root.effectivePrimaryName) return
        if (root.pendingWorkspaces[root.effectivePrimaryName] !== undefined) return

        const updated = Object.assign({}, root.pendingWorkspaces)
        updated[root.effectivePrimaryName] = [1, 2, 3, 4, 5]
        root.pendingWorkspaces = updated
    }

    function loadScreensStore() {
        screensStoreProcess.running = false
        screensStoreProcess.running = true
    }

    // Global (not per-monitor) toggles, all stored in this same
    // monitors.json under "__"-prefixed keys so none are mistaken for a
    // monitor name by anything that iterates the file's other keys -
    // display preferences for other components (WorkspaceRow.qml/
    // WorkspaceOsd.qml), not live Hyprland/hardware changes, but staged
    // through the same pending/effective + Apply flow as everything else
    // in this panel now (see pendingStrictWorkspaceWidget etc. below).
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

                    // Every read, not just the first - see
                    // hasRealMonitorsConfig/seedDefaultWorkspacesIfFresh()
                    // above for why this needs to keep re-checking
                    // rather than trusting whatever it saw the first
                    // time this session.
                    root.seedDefaultWorkspacesIfFresh()
                } catch (e) {
                    root.screensStore = {}
                    root.seedDefaultWorkspacesIfFresh()
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

    // ---------------- DDC/CI + brightnessctl brightness ----------------
    // All actual state/detection/apply now lives on Dashboard.qml's
    // shared root Scope (see dashboardRoot above) - these are thin
    // pass-throughs so the rest of this file (and MonitorCard's
    // bindings below) didn't need to change shape.
    function setPendingBrightness(name, value) {
        if (root.dashboardRoot) root.dashboardRoot.setPendingBrightness(name, value)
    }

    function brightnessFor(name) {
        return root.dashboardRoot ? root.dashboardRoot.brightnessFor(name) : 50
    }

    function supportsBrightness(name) {
        return root.dashboardRoot ? root.dashboardRoot.supportsBrightness(name) : false
    }

    function applyBrightness() {
        if (root.dashboardRoot) root.dashboardRoot.applyBrightness()
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
                        supportsBrightness: root.supportsBrightness(modelData.name)

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
                        text: "&"
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
                        text: "@"
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

                            // Every workspace 1-5 always belongs to
                            // exactly one monitor (see
                            // seedDefaultWorkspacesIfFresh()/
                            // resolveDisabledMonitorWorkspaces() below,
                            // and toggleWorkspace()'s no-op-if-already-
                            // bound guard) - so only two states are ever
                            // meaningful here: bound to the monitor
                            // currently selected in this panel (fgcolor),
                            // or not (fgcolordark), whether that's
                            // because it's owned elsewhere or - in
                            // principle only - unowned entirely. Clicking
                            // it either way still reassigns it here (see
                            // toggleWorkspace()); this used to warn red
                            // for "owned elsewhere" specifically, but
                            // reassigning is the normal, expected way to
                            // use these now, not something to flag.
                            readonly property bool bound: root.workspacesFor(root.selectedName).includes(modelData)

                            Layout.preferredWidth: Config.scaled(28, root.uiScale)
                            Layout.preferredHeight: Config.scaled(28, root.uiScale)
                            uiScale: root.uiScale
                            color: wsMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                            border.color: wsButton.bound ? Config.fgcolor : Config.fgcolordark

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
                        text: "Only managed workspaces in widget:"
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
                        text: "Show empty workspaces:"
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
                        text: "In widget"
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
                        text: "In OSD"
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

                    // ---------------- bottom right: set init + apply ----------------
                    // Set Init is what "Apply" used to be, unconditionally
                    // - it writes the whole layout to monitors.json (what
                    // scripts/apply-monitors.sh replays at login) as well
                    // as sending it live. Apply, to its right, sends the
                    // exact same live hyprctl eval calls but skips writing
                    // any *monitor* geometry to monitors.json - for a
                    // change you only want for the rest of this session
                    // (e.g. temporarily swapping to a single TV output for
                    // the night) without it becoming what boots next time.
                    // The Strict Workspace Widget/Show Empty checkboxes
                    // are the one exception - they still sync to the file
                    // either way (see applyChanges()), since that's the
                    // only way WorkspaceRow.qml/WorkspaceOsd.qml ever
                    // learn about them at all.
                    DashCard {
                        id: setInitButton

                        Layout.preferredWidth: Config.scaled(100, root.uiScale)
                        Layout.preferredHeight: Config.scaled(32, root.uiScale)
                        uiScale: root.uiScale

                        property color blinkColor: Config.fgcolor
                        border.color: root.dirty ? setInitButton.blinkColor : Config.fgcolordark

                        SequentialAnimation {
                            running: root.dirty
                            loops: Animation.Infinite
                            ColorAnimation { target: setInitButton; property: "blinkColor"; to: Config.fgcolorlight; duration: 800 }
                            ColorAnimation { target: setInitButton; property: "blinkColor"; to: Config.fgcolor; duration: 800 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Set Init"
                            color: root.dirty ? Config.fgcolor : Config.fgcolordark
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.dirty
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.applyChanges(true)
                            }
                        }
                    }

                    Item { Layout.preferredWidth: Config.scaled(8, root.uiScale) }

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
                                root.applyChanges(false)
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

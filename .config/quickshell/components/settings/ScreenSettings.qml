import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Config.js" as Config
import "../common"
import "cards"
import "controls"

// Monitor list (left, 35%) + arrangement view and selected-display form
// (right, 65%) - one tab ("Display") of SettingsScreen.qml's fullscreen
// tabbed panel (see there for the tab bar/coordinator, and for where the
// typed-input keyboard focus this used to request itself now comes
// from). Embeddable Item instead of a standalone SettingsPanel popup:
// panelWidth/uiScale/active are plain properties fed in from the tab
// host instead of coming from a PanelWindow.
//
// The right side: every monitor drawn to scale where it sits in
// Hyprland's layout (MonitorLayout.qml - click to pick, drag to move);
// under it, the
// selected display's resolution and refresh rate (dropdowns of the modes
// it reports, or the Preferred button beside them - the monitor's
// preferred resolution at the fastest refresh rate it offers there), scale
// (a slider that only stops on
// scales Hyprland accepts at that resolution), rotation, workspaces and
// exact position. Resizing a display moves the ones beside and below it
// along (keepNeighbours()), so displays that touched keep touching.
// Show Default swaps the view for the arrangement Set Default saved,
// read-only, with every editing control hidden or switched off.
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
// monitors.json - this is purely so re-enabling a monitor doesn't force
// retyping its position/resolution from scratch. An enabled monitor
// always shows its real, live hyprctl state instead, monitors.json or
// not. That same file also carries a precomputed hl.monitor({...})
// "line" per monitor, which is all scripts/apply-monitors.sh needs to
// replay the whole layout at login - one combined file instead of the
// previous monitors.conf/screens.json split, since this panel was the
// only thing reading or writing either.
//
// Apply and Set Default are deliberately two separate actions now, not
// one. Apply (applyChanges() below) only ever dispatches the current
// staged/edited state live via `hyprctl eval` - it no longer writes
// monitors.json at all, so trying out a layout (or a monitor you don't
// even want enabled by default, like an occasional TV) can never
// silently become what happens on the next login. Set Default
// (setDefault() below) is the only thing that writes monitors.json - it
// snapshots the exact same effectiveStateFor()/resolveWorkspaceAssignment()
// state Apply would have sent, but purely to disk, with no live dispatch
// of its own. The two are meant to be used independently: configure a
// monitor's position once, Set Default while it's disabled (so it's
// remembered for later), and from then on just flipping it enabled and
// hitting Apply reuses that remembered position with nothing to retype.
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false

    // Sized by whatever container SettingsScreen.qml gives this tab -
    // not self-measured from content anymore, so the monitor list
    // stretches to fill it and the hint row stays pinned to the true
    // bottom instead of trailing right behind however many monitors
    // happen to be connected.
    anchors.fill: parent

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
    // ("DP-1", see Dashboard.qml) until Set Default has saved one (see
    // setDefault()'s "__primary"), so on a genuinely fresh setup (or a
    // different machine entirely) it can
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

    // The names given to displays here (middle-click a card), kept by
    // output name - everything else still goes by the port.
    AliasStore {
        id: monitorNames
        file: "monitoraliases.json"
    }

    function displayName(name) {
        return monitorNames.name(name, name)
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
    // state: switching Preferred on or off (togglePreferred()). Geometry edits no longer rely on
    // this for correctness (see effectiveStateFor()) - only for also
    // marking the then-selected monitor as touched, alongside the
    // dedicated edited-keys loop in applyChanges().
    property bool selectedDirty: false

    // Whether each monitor's resolution is set to "Preferred", keyed by
    // name - unlike `edited` above, this *is* remembered across
    // switching monitors (and across Apply): hyprctl's own monitor JSON
    // has no way to report "this is running in preferred mode" after
    // the fact, so there's nothing to re-derive it from on reselect -
    // this has to remember the choice itself. Also seeded from
    // monitors.json on load (see screensStoreProcess) for monitors not
    // touched yet this session.
    property var preferredModes: ({})

    function setPreferredMode(name, value) {
        const updated = Object.assign({}, root.preferredModes)
        updated[name] = value
        root.preferredModes = updated
    }

    // Workspace numbers (1-5) explicitly pinned via the buttons below,
    // keyed by name - staged across multiple monitors like pendingEnabled
    // (not discarded when a different monitor is selected), only ever
    // written through toggleWorkspace(). This is raw UI staging state,
    // not the guaranteed-exclusive result - resolveWorkspaceAssignment()
    // (called fresh from applyChanges(), never mutating this property)
    // is what actually guarantees every workspace belongs to exactly one
    // monitor on a fresh setup or once a monitor gets disabled.
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

    // Single, pure, from-scratch resolver - replaces what used to be
    // four separate incremental fixups (resolveDisabledMonitorWorkspaces/
    // resolveWorkspaceCollisions/stripSpareWorkspaces/
    // resolveEmptyWorkspaceFailsafe), each of which only patched its own
    // slice of root.pendingWorkspaces in sequence. That was the actual
    // source of this feature's whole history of "still doesn't work"
    // reports: an edge case falling between two passes (one fixup
    // assuming a monitor was already handled by another, an order
    // dependency, a case none of the four individually anticipated).
    // This instead recomputes the ENTIRE exclusive workspace-to-monitor
    // mapping in one deterministic pass every single Apply, with no
    // shared mutable state threaded through several functions - and,
    // critically, it never writes to root.pendingWorkspaces at all
    // (that's UI staging state bound to the 1-5 buttons; mutating it
    // mid-Apply used to make button state visibly change as a side
    // effect of clicking Apply). Called once from applyChanges() and
    // used purely to build the dispatch lines and monitors.json
    // snapshot.
    //
    // Returns { name -> sorted [nums] } for every monitor in
    // root.monitors, active or not. Every number appearing anywhere in
    // the return value belongs to EXACTLY one entry - the hard
    // exclusivity invariant this whole rewrite exists to guarantee.
    function resolveWorkspaceAssignment() {
        // Numbers past 5 (the explicit-pin range - see the workspace
        // buttons below) are stripped from every monitor's remembered
        // list right up front, before anything else runs - they're never
        // durable state, only ever recomputed fresh by step 3 below,
        // whenever some monitor genuinely still needs an auto-assigned
        // filler this Apply. Skipping this used to let them accumulate
        // forever: orphan-recapture (step 2) moves a disabled monitor's
        // numbers onto the primary one at a time, and if that primary
        // already had a real 1-5 pin of its own, it never had a reason
        // to reconsider whether it still needed a *previous* auto-spare
        // it had picked up the same way earlier - reported live as a
        // monitor ending up with e.g. "workspaces": [1, 6, 7] after
        // several enable/disable cycles of some other display, with no
        // way to ever release 6 or 7 again (no button exists for
        // anything past 5) even though nothing needed either any more.
        const desired = {}
        for (const m of root.monitors) {
            desired[m.name] = root.workspacesFor(m.name).filter(num => num <= 5)
        }

        const activeNames = root.monitors.filter(m => root.enabledFor(m.name)).map(m => m.name)
        const activeSet = new Set(activeNames)

        // 1. Collisions among ACTIVE monitors only - toggleWorkspace()
        // already reassigns (rather than duplicates) for clicks made
        // this session, but monitors.json left over from before that
        // existed, or edited by hand, could still have the same number
        // desired by two enabled monitors. Kept on whichever sits
        // closest to (0, 0) - deterministic, no iteration-order
        // dependency - dropped from the rest. A disabled monitor's own
        // stale desire for that number is left alone here (harmless,
        // unreachable while it's inactive); see step 2 for what happens
        // to ITS numbers instead.
        const owners = {}
        for (const name of activeNames) {
            for (const num of desired[name]) {
                if (!owners[num]) owners[num] = []
                owners[num].push(name)
            }
        }
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
                desired[name] = desired[name].filter(n => n !== num)
            }
        }

        // 2. A number an INACTIVE monitor still remembers isn't
        // reachable while it's disabled/disconnected - recapture it
        // onto the primary monitor (guaranteed active, see
        // resolveOriginFailsafe) unless an active monitor has already
        // explicitly claimed it. Removed from the inactive monitor's own
        // desired list once recaptured - leaving it there was a real bug
        // caught by testing this against a standalone simulation before
        // ever touching Hyprland: a disabled monitor would keep
        // "remembering" numbers that had already been handed to another
        // monitor, so re-enabling it later would immediately re-collide
        // with whoever it had been given to instead of landing on a
        // clean, unclaimed number of its own.
        const claimedByActive = new Set()
        for (const name of activeNames) {
            for (const num of desired[name]) claimedByActive.add(num)
        }
        if (root.primaryMonitor && activeSet.has(root.primaryMonitor)) {
            for (const m of root.monitors) {
                if (activeSet.has(m.name)) continue
                const orphaned = desired[m.name].filter(num => !claimedByActive.has(num))
                if (orphaned.length === 0) continue

                const primaryList = desired[root.primaryMonitor].slice()
                for (const num of orphaned) {
                    if (!primaryList.includes(num)) primaryList.push(num)
                    claimedByActive.add(num)
                }
                desired[root.primaryMonitor] = primaryList
                desired[m.name] = desired[m.name].filter(num => !orphaned.includes(num))
            }
        }

        // 3. Any active monitor left with nothing at all gets the lowest
        // positive integer no other ACTIVE monitor is using -
        // claimedByActive already covers anything just recaptured in
        // step 2, so this stays accurate without rebuilding it. NOT
        // reserving whatever a disabled/inactive monitor still remembers
        // - an earlier version of this function used a set built from
        // every monitor (active or not) here instead, on the theory that
        // it'd avoid a re-enabled monitor's number getting stolen out
        // from under it. That created a worse, permanent problem in
        // practice: a monitor that just stays disabled (a second display
        // only turned on occasionally, say) would forever keep whatever
        // it last remembered off-limits, pushing every other monitor's
        // auto-assigned spare higher and higher (6, 7, 8...) even though
        // 1-5 are sitting completely unused - reported live as always
        // seeing spare workspaces 6 and 7 in the OSD despite nothing
        // active actually claiming 1-5. If that monitor is later
        // re-enabled and collides with whoever took its old number in
        // the meantime, step 1 above already resolves that
        // deterministically on that later Apply - not worth permanently
        // reserving against. No more ">5 reserved for real pins"
        // distinction either - every number is equally real now, so this
        // can (and normally will) land within 1-5 if those aren't all
        // already claimed by another active monitor.
        let nextSpare = 1
        for (const name of activeNames) {
            if (desired[name].length > 0) continue
            while (claimedByActive.has(nextSpare)) nextSpare++
            desired[name] = [nextSpare]
            claimedByActive.add(nextSpare)
        }

        for (const name in desired) {
            desired[name] = desired[name].slice().sort((a, b) => a - b)
        }
        return desired
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

    function setEdited(key, value) {
        const updated = Object.assign({}, root.edited)
        const forSelected = Object.assign({}, updated[root.selectedName] || {})
        forSelected[key] = value
        updated[root.selectedName] = forSelected
        root.edited = updated
        root.selectedDirty = true
    }

    // setEdited() for any monitor, not just the selected one - the
    // arrangement view moves whichever monitor gets dragged, and resizing
    // one monitor can shift its neighbours (see keepNeighbours()).
    function setEditedFor(name, key, value) {
        if (!name) return
        const updated = Object.assign({}, root.edited)
        const forName = Object.assign({}, updated[name] || {})
        forName[key] = value
        updated[name] = forName
        root.edited = updated
    }

    // Enable/disable, with the fail-safes the bar and dashboard rely on:
    // disabling the current primary first hands primary off to whichever
    // OTHER monitor is still enabled (first match in root.monitors order) -
    // they always need exactly one enabled monitor to live on, so this
    // can't just leave primary pointing at something about to go dark. If
    // this is the only enabled monitor left, there's no other one to hand
    // it to, so disabling is refused outright rather than leaving nothing
    // enabled at all. The monitor cards' right-click.
    function toggleEnabled(name) {
        if (!name) return
        const enabling = !root.enabledFor(name)
        if (!enabling && name === root.primaryMonitor) {
            const nextPrimary = root.monitors.find(m => m.name !== name && root.enabledFor(m.name))
            if (!nextPrimary) return
            root.primarySelected(nextPrimary.name)
        }
        root.setPendingEnabled(name, enabling)
    }

    // A disabled monitor still can't be made primary.
    function makePrimary(name) {
        if (name && root.enabledFor(name)) root.primarySelected(name)
    }

    // ---------------- modes, scales and the arrangement ----------------
    // hyprctl lists the modes a monitor offers as "2560x1440@143.99Hz", its
    // own preferred mode first (the kernel sorts that one to the front),
    // which is what Hyprland's "preferred" picks.
    function parseMode(text) {
        const m = /^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)@(\d+(?:\.\d+)?)Hz$/.exec(String(text).trim())
        return m ? { w: Math.round(parseFloat(m[1])), h: Math.round(parseFloat(m[2])), refresh: parseFloat(m[3]) } : null
    }

    function modesFor(name) {
        const base = root.baseFor(name)
        if (!base || !Array.isArray(base.availableModes)) return []
        return base.availableModes.map(root.parseMode).filter(m => m !== null)
    }

    function preferredModeFor(name) {
        const modes = root.modesFor(name)
        return modes.length > 0 ? modes[0] : null
    }

    // What Preferred runs: the monitor's preferred resolution at the
    // fastest refresh rate it offers there - Hyprland's own "preferred"
    // often settles for 60 Hz on a faster monitor. Null while hyprctl
    // lists no modes for it.
    function preferredRunModeFor(name) {
        const preferred = root.preferredModeFor(name)
        if (!preferred) return null
        let refresh = preferred.refresh
        for (const m of root.modesFor(name)) {
            if (m.w === preferred.w && m.h === preferred.h && m.refresh > refresh) refresh = m.refresh
        }
        return { w: preferred.w, h: preferred.h, refresh }
    }

    // Whether this monitor runs (or, while off, would run once enabled)
    // Hyprland's own "preferred" mode - the exact opposite of what
    // effectiveStateFor() calls usesExplicitMode for an enabled monitor:
    // Preferred chosen, or nothing typed, remembered or live to give a
    // mode from (a display that's never been set up). The form and the
    // arrangement view go by this, so they show what Apply will send.
    function runsPreferredMode(name) {
        if (root.preferredModes[name]) return true
        const base = root.baseFor(name)
        if (!base) return false
        const e = root.edited[name] || {}
        return !(!base.disabled || !!root.screensStore[name] || e.width !== undefined || e.height !== undefined)
    }

    // The mode a monitor actually runs (or will, once applied) - in
    // Preferred mode that's the monitor's own preferred one, whatever was
    // last typed or remembered for it.
    function modeSizeFor(name, state) {
        const preferred = root.preferredModeFor(name)
        if (root.runsPreferredMode(name) && preferred) return { w: preferred.w, h: preferred.h }
        if (state && state.width > 0 && state.height > 0) return { w: state.width, h: state.height }
        return preferred ? { w: preferred.w, h: preferred.h } : { w: 1920, h: 1080 }
    }

    // Each distinct resolution on offer, biggest first - plus the monitor's
    // current one, should that be a custom mode the list doesn't have.
    function resolutionsFor(name) {
        const seen = {}
        const list = []
        const add = (w, h) => {
            const key = w + "x" + h
            if (w > 0 && h > 0 && !seen[key]) {
                seen[key] = true
                list.push({ w, h })
            }
        }
        for (const m of root.modesFor(name)) add(m.w, m.h)
        const state = root.effectiveStateFor(name)
        if (state && !root.runsPreferredMode(name)) add(state.width, state.height)
        return list.sort((a, b) => (b.w * b.h - a.w * a.h) || (b.w - a.w))
    }

    // The refresh rates on offer at one resolution, fastest first - plus
    // the current one if it isn't among them (a custom mode).
    function refreshRatesFor(name, w, h) {
        const rates = []
        for (const m of root.modesFor(name)) {
            if (m.w === w && m.h === h && !rates.some(r => Math.abs(r - m.refresh) < 0.005)) rates.push(m.refresh)
        }
        const state = root.effectiveStateFor(name)
        if (state && state.width === w && state.height === h && state.refresh > 0
                && !rates.some(r => Math.abs(r - state.refresh) < 0.5)) {
            rates.push(state.refresh)
        }
        return rates.sort((a, b) => b - a)
    }

    // Every scale Hyprland takes as it is at this resolution, from 0.5 to
    // 3: a multiple of 1/120 (what the fractional-scale protocol can
    // express) that divides the mode into whole logical pixels. Anything
    // else it swaps for the nearest scale that does, with a warning - this
    // is the same floating-point check it makes (Monitor.cpp).
    function scalesFor(w, h) {
        if (!(w > 0 && h > 0)) return [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
        const scales = []
        for (let k = 60; k <= 360; k++) {
            const s = k / 120
            const lw = w / s
            const lh = h / s
            if (lw === Math.round(lw) && lh === Math.round(lh)) scales.push(s)
        }
        return scales.length > 0 ? scales : [1]
    }

    function nearestIndex(list, value) {
        let best = 0
        for (let i = 1; i < list.length; i++) {
            if (Math.abs(list[i] - value) < Math.abs(list[best] - value)) best = i
        }
        return best
    }

    function formatRefresh(rate) {
        return String(Math.round(rate * 100) / 100)
    }

    function formatScale(scale) {
        return String(Math.round(scale * 100) / 100)
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w - 0.5 && b.x < a.x + a.w - 0.5
            && a.y < b.y + b.h - 0.5 && b.y < a.y + a.h - 0.5
    }

    // What each monitor's box in the arrangement view says under its name.
    function rectLines(name, state, size) {
        const lines = []
        if (state.disabled) lines.push("OFF")
        lines.push(size.w + " x " + size.h)
        // The refresh rate it runs at, Preferred or not.
        const run = root.runsPreferredMode(name) ? root.preferredRunModeFor(name) : null
        const refresh = run ? run.refresh : state.refresh
        let detail = refresh > 0 ? root.formatRefresh(refresh) + " Hz" : ""
        detail += (detail.length > 0 ? " · " : "") + root.formatScale(state.scale) + "x"
        if (state.transform & 3) detail += " · " + ((state.transform & 3) * 90) + "°"
        lines.push(detail)
        const ws = root.workspacesFor(name).filter(n => n <= 5).slice().sort((a, b) => a - b)
        if (ws.length > 0) lines.push("ws " + ws.join(" "))
        return lines
    }

    // The arrangement view's model: each monitor's rectangle in Hyprland's
    // layout (logical pixels - its mode divided by its scale, on its side
    // when rotated), from the same effectiveStateFor() Apply sends, so the
    // picture can't disagree with what Apply does. A monitor Hyprland will
    // place by itself ("auto": newly enabled, never positioned) is drawn
    // where that puts it, to the right of everything else - and so is a
    // disabled one that has never had a position, instead of piled on top
    // of another. Those are flagged `auto`; dragging one gives it a real
    // position.
    readonly property var arrangement: {
        const placed = []
        const parked = []
        for (const m of root.monitors) {
            const state = root.effectiveStateFor(m.name)
            if (!state) continue
            const size = root.modeSizeFor(m.name, state)
            const turned = (state.transform & 1) === 1
            const e = root.edited[m.name] || {}
            const known = state.disabled
                ? (!m.disabled || !!root.screensStore[m.name] || e.x !== undefined || e.y !== undefined)
                : state.usesExplicitPosition
            const rect = {
                name: m.name,
                x: state.x || 0,
                y: state.y || 0,
                w: (turned ? size.h : size.w) / state.scale,
                h: (turned ? size.w : size.h) / state.scale,
                enabled: !state.disabled,
                primary: root.primaryMonitor === m.name,
                selected: root.selectedName === m.name,
                auto: !known,
                warn: false,
                lines: root.rectLines(m.name, state, size)
            }
            if (known) placed.push(rect)
            else parked.push(rect)
        }
        let right = 0
        for (const r of placed) right = Math.max(right, r.x + r.w)
        for (const r of parked) {
            r.x = right
            r.y = 0
            right += r.w
        }
        const all = placed.concat(parked)
        const live = all.filter(r => r.enabled)
        for (let i = 0; i < live.length; i++) {
            for (let j = i + 1; j < live.length; j++) {
                if (root.overlaps(live[i], live[j])) {
                    live[i].warn = true
                    live[j].warn = true
                }
            }
        }
        return all
    }

    readonly property var overlapping: root.arrangement.filter(r => r.warn).map(r => r.name)

    function rectFor(name) {
        return root.arrangement.find(r => r.name === name) || null
    }

    // The same picture of what Set Default last saved (monitors.json), for
    // Show Default.
    readonly property var savedArrangement: {
        const rects = []
        for (const name of root.defaultMonitorNames) {
            const e = root.screensStore[name]
            if (!e) continue
            const preferred = root.preferredModeFor(name)
            const run = e.mode === "preferred" ? root.preferredRunModeFor(name) : null
            const size = run ? { w: run.w, h: run.h }
                : (e.width > 0 && e.height > 0) ? { w: e.width, h: e.height }
                : (preferred ? { w: preferred.w, h: preferred.h } : { w: 1920, h: 1080 })
            const transform = Number.isInteger(e.transform) ? e.transform : 0
            const scale = e.scale > 0 ? e.scale : 1
            const turned = (transform & 1) === 1
            const lines = []
            if (e.disabled) lines.push("OFF")
            lines.push(size.w + " x " + size.h)
            const refresh = run ? run.refresh : e.refresh
            let detail = refresh > 0 ? root.formatRefresh(refresh) + " Hz" : ""
            detail += (detail.length > 0 ? " · " : "") + root.formatScale(scale) + "x"
            if (transform & 3) detail += " · " + ((transform & 3) * 90) + "°"
            lines.push(detail)
            if (e.workspaces && e.workspaces.length > 0) lines.push("ws " + e.workspaces.join(" "))
            rects.push({
                name,
                x: e.x || 0,
                y: e.y || 0,
                w: (turned ? size.h : size.w) / scale,
                h: (turned ? size.w : size.h) / scale,
                enabled: !e.disabled,
                primary: root.screensStore.__primary === name,
                selected: false,
                auto: false,
                warn: false,
                lines
            })
        }
        return rects
    }

    // Which arrangement the view shows - the staged one you can drag around,
    // or the saved default. Back to the staged one every time the tab opens.
    property bool showingDefaults: false

    // A monitor that changes size (mode, scale, rotation) keeps its top-left
    // corner, and everything that was to its right moves with its right
    // edge, everything below it with its bottom edge - so displays that
    // touched still touch, and the gaps between the rest stay as they were.
    // Only for a monitor that's on: one being set up while disabled
    // shouldn't shove the displays actually in use around.
    function keepNeighbours(name, before) {
        const after = root.rectFor(name)
        if (!before || !after || !after.enabled || before.auto) return
        const dw = after.w - before.w
        const dh = after.h - before.h
        if (Math.abs(dw) < 0.5 && Math.abs(dh) < 0.5) return
        const others = root.arrangement.filter(r => r.name !== name && !r.auto)
        for (const r of others) {
            if (Math.abs(dw) >= 0.5 && r.x >= before.x + before.w - 0.5) root.setEditedFor(r.name, "x", Math.round(r.x + dw))
            if (Math.abs(dh) >= 0.5 && r.y >= before.y + before.h - 0.5) root.setEditedFor(r.name, "y", Math.round(r.y + dh))
        }
    }

    // A new mode can rule out the current scale (see scalesFor()) - moved
    // to the nearest one it allows, rather than left for Hyprland to swap
    // with a warning.
    function fitScaleToMode() {
        const state = root.effectiveStateFor(root.selectedName)
        if (!state) return
        const size = root.modeSizeFor(root.selectedName, state)
        const scales = root.scalesFor(size.w, size.h)
        const nearest = scales[root.nearestIndex(scales, state.scale)]
        if (Math.abs(nearest - state.scale) > 0.005) root.setEdited("scale", nearest)
    }

    // The selected monitor's resolution dropdown: an index into
    // root.selectedResolutions. Picking a resolution keeps the current
    // refresh rate if the new one offers it, and otherwise takes its
    // fastest.
    function chooseResolution(index) {
        const name = root.selectedName
        if (!name) return
        const res = root.selectedResolutions[index]
        if (!res) return
        const before = root.rectFor(name)
        const state = root.effectiveStateFor(name)
        const rates = root.refreshRatesFor(name, res.w, res.h)
        const current = state ? state.refresh : 0
        const keep = rates.find(r => Math.abs(r - current) < 0.5)
        root.setPreferredMode(name, false)
        root.selectedDirty = true
        root.setEdited("width", res.w)
        root.setEdited("height", res.h)
        if (rates.length > 0) root.setEdited("refresh", keep !== undefined ? keep : rates[0])
        root.fitScaleToMode()
        root.keepNeighbours(name, before)
    }

    // The Preferred button. Either way it stages the numbers Preferred runs
    // at (the preferred resolution, fastest refresh rate), so the
    // arrangement view and Set Default see what it'll really be - and
    // switching it off leaves the dropdowns on that same mode, to change
    // from there.
    function togglePreferred() {
        const name = root.selectedName
        if (!name) return
        const before = root.rectFor(name)
        const run = root.preferredRunModeFor(name)
        root.setPreferredMode(name, !root.selectedPreferred)
        root.selectedDirty = true
        if (run) {
            root.setEdited("width", run.w)
            root.setEdited("height", run.h)
            root.setEdited("refresh", run.refresh)
        }
        root.fitScaleToMode()
        root.keepNeighbours(name, before)
    }

    function chooseRefresh(index) {
        const rate = root.selectedRates[index]
        if (rate === undefined || root.selectedPreferred) return
        root.setEdited("refresh", rate)
    }

    function chooseScale(scale) {
        const name = root.selectedName
        if (!name || Math.abs(scale - root.selectedScale) < 0.0001) return
        const before = root.rectFor(name)
        root.setEdited("scale", scale)
        root.keepNeighbours(name, before)
    }

    // Quarter turns clockwise; a flipped transform (4-7) keeps its flip.
    function chooseRotation(quarterTurns) {
        const state = root.effectiveStateFor(root.selectedName)
        if (!state) return
        const next = (state.transform & 4) | (quarterTurns & 3)
        if (next === state.transform) return
        const before = root.rectFor(root.selectedName)
        root.setEdited("transform", next)
        root.keepNeighbours(root.selectedName, before)
    }

    // A drag in the arrangement view - the X/Y boxes follow it when it's
    // the selected monitor.
    function moveMonitor(name, x, y) {
        // Let go where it started: nothing to stage.
        const rect = root.rectFor(name)
        if (rect && Math.round(rect.x) === x && Math.round(rect.y) === y) return
        root.setEditedFor(name, "x", x)
        root.setEditedFor(name, "y", y)
        if (name === root.selectedName) root.displayFor = Object.assign({}, root.displayFor, { x, y })
    }

    // ---------------- the selected monitor, for the form ----------------
    readonly property var selectedState: root.effectiveStateFor(root.selectedName)
    readonly property var selectedBase: root.baseFor(root.selectedName)
    readonly property string selectedDescription: {
        const b = root.selectedBase
        if (!b) return ""
        const makeModel = [b.make, b.model].filter(s => s && String(s).length > 0).join(" ")
        return makeModel.length > 0 ? makeModel : (b.description || "")
    }
    readonly property bool selectedPreferred: root.runsPreferredMode(root.selectedName)
    readonly property var selectedSize: root.selectedState ? root.modeSizeFor(root.selectedName, root.selectedState) : ({ w: 0, h: 0 })
    readonly property var selectedResolutions: root.resolutionsFor(root.selectedName)
    // The dropdowns (hidden while Preferred is on).
    readonly property var resolutionOptions: root.selectedResolutions.length > 0
        ? root.selectedResolutions.map(r => r.w + " x " + r.h)
        : ["-"]
    readonly property int resolutionIndex: {
        const s = root.selectedSize
        const i = root.selectedResolutions.findIndex(r => r.w === s.w && r.h === s.h)
        return i >= 0 ? i : 0
    }
    readonly property var selectedRates: root.refreshRatesFor(root.selectedName, root.selectedSize.w, root.selectedSize.h)
    readonly property var refreshOptions: root.selectedRates.length > 0
        ? root.selectedRates.map(r => root.formatRefresh(r) + " Hz")
        : ["-"]
    readonly property int refreshIndex: (!root.selectedState || root.selectedRates.length === 0
                                         || !(root.selectedState.refresh > 0))
        ? 0
        : root.nearestIndex(root.selectedRates, root.selectedState.refresh)
    readonly property real selectedScale: root.selectedState ? root.selectedState.scale : 1
    readonly property var scaleOptions: root.scalesFor(root.selectedSize.w, root.selectedSize.h)
    readonly property int scaleIndex: root.nearestIndex(root.scaleOptions, root.selectedScale)
    readonly property int selectedTransform: root.selectedState ? root.selectedState.transform : 0
    // What apps on it get to work with: the mode divided by the scale, on
    // its side when rotated.
    readonly property string selectedLogicalSize: {
        const turned = (root.selectedTransform & 1) === 1
        const w = Math.round((turned ? root.selectedSize.h : root.selectedSize.w) / root.selectedScale)
        const h = Math.round((turned ? root.selectedSize.w : root.selectedSize.h) / root.selectedScale)
        return w + " x " + h
    }

    // What the X/Y boxes actually show - a live hyprctl snapshot (or,
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
    // so persisting it across switches carries none of that same risk.
    function selectMonitor(name) {
        root.selectedName = name
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
        // Hyprland's transform index: 0 = normal, 1/2/3 = 90/180/270
        // degrees (4-7 are the flipped variants, never set from here but
        // passed through untouched if hyprctl or monitors.json reports
        // one). Old monitors.json entries from before this field existed
        // have no transform, so they count as 0.
        const rawTransform = e.transform !== undefined ? e.transform : remembered.transform
        const transform = Number.isInteger(rawTransform) ? rawTransform : 0

        if (!root.enabledFor(name)) {
            return {
                disabled: true,
                width, height, refresh, x, y, scale, transform,
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
            width, height, refresh, x, y, scale, transform,
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

        // Preferred goes out as its own numbers (preferredRunModeFor()),
        // for the fastest refresh rate - and so does what Set Default
        // saves, which apply-monitors.sh replays at login. Hyprland's own
        // "preferred" only when hyprctl lists no modes to go by.
        const run = state.usesExplicitMode ? null : root.preferredRunModeFor(name)
        const mode = state.usesExplicitMode ? `${state.width}x${state.height}@${state.refresh}`
            : (run ? `${run.w}x${run.h}@${run.refresh}` : "preferred")
        const position = state.usesExplicitPosition ? `${state.x}x${state.y}` : "auto"

        // disabled = false has to be explicit - hl.monitor() only
        // touches the fields you pass, so a monitor that was previously
        // disabled would otherwise stay disabled even with a full
        // mode/position/scale given (confirmed live: applying without
        // this left a re-enabled monitor off despite hyprctl replying
        // "ok" to every call).
        return `hl.monitor({ output = "${name}", disabled = false, mode = "${mode}", position = "${position}", scale = "${state.scale}", transform = ${state.transform} })`
    }

    function applyChanges() {
        if (!root.dirty) return

        // Wrapped in try/finally - an uncaught exception partway
        // through used to skip the pending* resets at the bottom
        // entirely, leaving Apply glowing (root.dirty stuck true) with
        // no way to tell anything had gone wrong short of checking
        // quickshell's own log. finally guarantees the staged edits
        // always get cleared and the button always stops glowing, and
        // the catch below logs whatever actually broke instead of
        // failing silently.
        try {

        // The one authoritative, from-scratch, collision-free mapping -
        // see resolveWorkspaceAssignment() above for why this replaced
        // four separate incremental fixups.
        const resolved = root.resolveWorkspaceAssignment()
        const activeNames = root.monitors.filter(m => root.enabledFor(m.name)).map(m => m.name)

        // Only touched monitors get their geometry/enable line resent -
        // any monitor with a staged geometry edit (root.edited, now
        // persisting across monitor switches - see its declaration
        // above), any right-clicked enable/disable toggle, plus
        // whichever monitor is currently selected if selectedDirty
        // (covers switching to Preferred, which needn't touch
        // root.edited at all) - not every monitor every time, which
        // used to trigger Hyprland's layout reflow for displays nobody
        // asked to change. (Workspace bindings below are NOT gated this
        // way - see the always-resend comment further down.)
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

        const monitorLines = []
        for (const name of touched) {
            const line = root.buildMonitorLine(name)
            if (line) monitorLines.push(line)
        }

        // Every active monitor's FULL resolved workspace list is resent
        // in full on EVERY Apply - not just the ones this Apply's UI
        // edits touched, and not just a diff against what was there
        // before. This is deliberately more than the strict minimum:
        // resending an already-correct workspace_rule/move is a cheap,
        // idempotent no-op, and always fully re-asserting the entire
        // exclusive mapping is what actually guarantees Hyprland's live
        // rule table can never silently drift out of sync with
        // monitors.json, regardless of what specifically changed this
        // time - the previous, more "targeted" incremental approach is
        // exactly what kept leaving edge cases unhandled. Each
        // workspace_rule is paired with an explicit
        // hl.dispatch(hl.dsp.workspace.move(...)) - the rule alone only
        // steers where a workspace goes at *creation*, not one that's
        // already live and sitting on a different monitor with real
        // windows open.
        const workspaceLines = []
        for (const name of activeNames) {
            for (const num of resolved[name] || []) {
                workspaceLines.push(`hl.workspace_rule({ workspace = "${num}", monitor = "${name}" })`)
                workspaceLines.push(`hl.dispatch(hl.dsp.workspace.move({ workspace = "${num}", monitor = "${name}" }))`)
            }
        }

        // Monitors whose CURRENT LIVE active workspace (root.baseFor(name),
        // the last hyprctl fetch this panel did) isn't part of its newly
        // resolved set at all - forced onto their new lowest workspace
        // immediately (focus monitor, then workspace) rather than left
        // showing whatever they were on until someone manually switches
        // away from it. Deliberately keyed off LIVE reality, not
        // monitors.json's previously-persisted list - an earlier version
        // used "the persisted list was empty" as the trigger instead,
        // which silently never fired for a monitor whose monitors.json
        // still remembered some stale entry from long before (e.g. an old
        // auto-assigned spare number that had nothing to do with this
        // Apply) even though its actual live workspace was never part of
        // this Apply's newly-resolved set either - reported live as a
        // monitor given fresh workspace pins not getting switched off
        // its old unmanaged workspace at all, only fixable by hand.
        const newlyManaged = []
        for (const name of activeNames) {
            const targets = resolved[name] || []
            if (targets.length === 0) continue
            const base = root.baseFor(name)
            const currentLive = (base && base.activeWorkspace) ? base.activeWorkspace.id : undefined
            if (currentLive !== undefined && targets.includes(currentLive)) continue
            newlyManaged.push({
                monitor: name,
                oldWorkspace: currentLive,
                newWorkspace: targets.reduce((a, b) => Math.min(a, b))
            })
        }

        for (const entry of newlyManaged) {
            workspaceLines.push(`hl.dispatch(hl.dsp.focus({ monitor = "${entry.monitor}" }))`)
            workspaceLines.push(`hl.dispatch(hl.dsp.focus({ workspace = "${entry.newWorkspace}" }))`)
        }

        // Every workspace number that belongs to ANY active monitor after
        // this Apply - used right below to tell "this old workspace was
        // truly orphaned" apart from "this old workspace still exists,
        // just reassigned to a different monitor". Reassigning a pinned
        // workspace elsewhere (e.g. moving workspace 2 from DP-2 to
        // DP-1 while Discord's open on it) already gets its windows
        // carried along for free by the ordinary workspace_rule/move
        // pair above, which moves the whole workspace (and everything on
        // it) as a unit - the same thing happens when a monitor gets
        // disabled and its pinned numbers get recaptured onto the
        // primary. Individually rescuing windows off that same old
        // workspace id here would fight that move instead of
        // complementing it - both dispatches would target windows
        // sitting on "workspace 2", one relocating them as part of the
        // whole workspace to DP-1, the other yanking them individually
        // onto DP-2's own new filler workspace - reported live as
        // Discord left behind on an unmanaged filler after explicitly
        // reassigning its workspace elsewhere, or after disabling the
        // monitor it was on entirely.
        const allResolvedNumbers = new Set()
        for (const name of activeNames) {
            for (const num of resolved[name] || []) allResolvedNumbers.add(num)
        }

        // Any of those same monitors that also had a real window open on
        // their old (live, pre-Apply) active workspace gets that window
        // rescued onto the new one too, via clientsQueryProcess below,
        // rather than left stranded on the now-orphaned workspace only
        // reachable through WorkspaceRow - but only when that old
        // workspace is genuinely orphaned (see allResolvedNumbers above),
        // not merely reassigned to a different monitor.
        const rescues = []
        for (const entry of newlyManaged) {
            if (entry.oldWorkspace === undefined || entry.oldWorkspace === entry.newWorkspace) continue
            if (allResolvedNumbers.has(entry.oldWorkspace)) continue
            rescues.push({ monitor: entry.monitor, oldWorkspace: entry.oldWorkspace, newWorkspace: entry.newWorkspace })
        }

        // A monitor being newly DISABLED this Apply never goes through
        // newlyManaged above at all - that loop only ever looks at
        // monitors still ACTIVE after this Apply. If its old (live,
        // pre-Apply) workspace was genuinely unmanaged, left alone here
        // Hyprland's own default disable-a-monitor behavior takes over
        // instead, which knows nothing about this panel's managed
        // numbers - it just shoves the orphaned workspace (and every
        // window on it) onto whatever monitor absorbs it, creating a
        // brand new unmanaged workspace there too - reported live as
        // windows from a disabled monitor's unmanaged workspace landing
        // on another fresh unmanaged workspace on the primary, even
        // though all 5 real workspaces were managed and available.
        // Rescued onto the lowest managed number still available
        // anywhere post-Apply instead, same mechanism as the loop above.
        for (const name of Object.keys(root.pendingEnabled)) {
            if (root.pendingEnabled[name] !== false) continue
            const base = root.baseFor(name)
            if (!base || base.disabled) continue
            const oldWorkspace = base.activeWorkspace ? base.activeWorkspace.id : undefined
            if (oldWorkspace === undefined || allResolvedNumbers.has(oldWorkspace)) continue
            if (allResolvedNumbers.size === 0) continue
            const newWorkspace = Array.from(allResolvedNumbers).reduce((a, b) => Math.min(a, b))
            rescues.push({ monitor: name, oldWorkspace, newWorkspace })
        }

        // No monitors.json write here anymore - Apply is purely a live,
        // this-boot-only dispatch now. See setDefault() below for the
        // only thing that persists a layout as what happens on the next
        // Hyprland login.
        //
        // liveworkspaces.json is different - it's not a "default", it's
        // this Apply's own just-dispatched workspace-to-monitor mapping,
        // and WorkspaceRow.qml/WorkspaceOsd.qml need to see it update
        // every single Apply (not just a Set Default) to know which
        // pins/placeholders are actually live right now. Same shape as
        // monitors.json's own per-entry "workspaces" list (only that
        // field - no geometry) so those two files' existing `stored.
        // workspaces` reads need no changes of their own, only their
        // file path. apply-monitors.sh seeds this same file fresh at
        // every login from whatever it just replayed off monitors.json,
        // so it's never stale even before this session's first Apply.
        const liveWorkspacesSnapshot = {}
        for (const name in resolved) {
            liveWorkspacesSnapshot[name] = { workspaces: resolved[name] }
        }
        liveWorkspacesFile.setText(JSON.stringify(liveWorkspacesSnapshot, null, 2) + "\n")

        // Monitor enable/disable/geometry lines go out first. If any
        // touched monitor is transitioning disabled -> enabled this
        // Apply, the workspace rule/move/focus/rescue lines wait for it
        // to actually report ready (a poll, not a blind delay - see
        // monitorSettleTimer/monitorSettleQueryProcess below) rather
        // than racing an async DRM/Wayland commit: hyprctl eval
        // replying "ok" to the enable line doesn't mean Hyprland has
        // actually finished bringing a newly-connected/re-enabled
        // output online yet, and a workspace move sent in the same
        // immediate batch can silently no-op if it isn't. Skipped
        // (immediate, single batch) when nothing's newly enabling -
        // the common geometry/workspace-pin-only Apply doesn't gain a
        // pointless wait.
        const newlyEnabledMonitors = Array.from(touched).filter(name => {
            const base = root.baseFor(name)
            const wasDisabled = !base || base.disabled
            return wasDisabled && root.enabledFor(name)
        })

        if (newlyEnabledMonitors.length > 0 && monitorLines.length > 0) {
            root.runApplyScript(monitorLines)
            root.pendingWorkspaceLines = workspaceLines
            root.pendingRescues = rescues
            root.pendingSettleMonitors = newlyEnabledMonitors
            root.monitorSettleAttempts = 0
            monitorSettleTimer.restart()
        } else {
            const sendLines = monitorLines.concat(workspaceLines)
            // Rescuing needs a fresh window list first - deferred
            // through clientsQueryProcess/runApplyScript() rather than
            // sent immediately, so the rescue dispatches land in the
            // same script (and thus the same capture/restore-wrapped
            // run) instead of a separate, later Apply.
            if (rescues.length > 0) {
                root.pendingSendLines = sendLines
                root.pendingRescues = rescues
                clientsQueryProcess.running = false
                clientsQueryProcess.running = true
            } else {
                root.runApplyScript(sendLines)
            }
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

        } catch (e) {
            console.warn("ScreenSettings: applyChanges() threw: " + e + (e && e.stack ? ("\n" + e.stack) : ""))
        } finally {
            root.pendingEnabled = ({})
            root.pendingWorkspaces = ({})
            root.positionOverrides = ({})
            root.edited = ({})
            root.selectedDirty = false
            // preferredMode intentionally left as-is - Apply shouldn't
            // flip the resolution back off Preferred for the monitor you just
            // applied.
        }
    }

    // The exact per-monitor snapshot Set Default would write - shared by
    // setDefault() itself and defaultsOutOfSync below, so "what Set
    // Default would save" and "whether there's anything new for it to
    // save" can never disagree with each other.
    function computeCurrentSnapshot() {
        const resolved = root.resolveWorkspaceAssignment()

        const snapshot = {}
        for (const m of root.monitors) {
            const line = root.buildMonitorLine(m.name)
            const state = root.effectiveStateFor(m.name)
            if (state && line) {
                snapshot[m.name] = {
                    disabled: state.disabled,
                    width: state.width,
                    height: state.height,
                    refresh: state.refresh,
                    x: state.x,
                    y: state.y,
                    scale: state.scale,
                    transform: state.transform,
                    mode: state.mode,
                    workspaces: resolved[m.name] || [],
                    line
                }
            }
        }
        return snapshot
    }

    // Whether computeCurrentSnapshot() actually differs from what's
    // already saved in monitors.json - Set Default's own blink (see the
    // button below) is gated on this, not root.dirty, since those aren't
    // the same thing: reselecting a monitor and toggling its mode
    // straight back to what it already was, or a pending workspace
    // reassignment that resolves right back to what's already saved, is
    // "dirty" (something was touched this session) but has nothing new
    // for Set Default to actually persist - blinking anyway would just
    // be a false "you should click this" signal. Deliberately a plain
    // per-field comparison, not JSON.stringify(...) equality - key
    // ordering inside each entry is fixed by computeCurrentSnapshot()
    // itself so it'd likely still work, but this is explicit about
    // exactly which fields matter (matching monitors.json's own schema)
    // rather than leaning on incidental object-key order.
    readonly property bool defaultsOutOfSync: {
        const current = root.computeCurrentSnapshot()
        const defaultNames = root.defaultMonitorNames
        const currentNames = Object.keys(current)

        if (currentNames.length !== defaultNames.length) return true

        // Primary changed (or was never saved) - see setDefault().
        if (root.effectivePrimaryName && root.screensStore.__primary !== root.effectivePrimaryName) return true

        for (const name of currentNames) {
            const c = current[name]
            const d = root.screensStore[name]
            if (!d) return true
            if (c.disabled !== !!d.disabled) return true
            if (c.mode !== d.mode) return true
            if (c.width !== d.width || c.height !== d.height || c.refresh !== d.refresh) return true
            if (c.x !== d.x || c.y !== d.y || c.scale !== d.scale) return true
            if (c.transform !== (Number.isInteger(d.transform) ? d.transform : 0)) return true

            const cw = (c.workspaces || []).slice().sort((a, b) => a - b)
            const dw = (d.workspaces || []).slice().sort((a, b) => a - b)
            if (cw.length !== dw.length) return true
            for (let i = 0; i < cw.length; i++) {
                if (cw[i] !== dw[i]) return true
            }
        }
        return false
    }

    // "Set Default" - the only thing that still writes monitors.json
    // (see this file's own top comment for why that's no longer Apply's
    // job). Snapshots the exact same effectiveStateFor()/
    // resolveWorkspaceAssignment() state applyChanges() dispatches live,
    // straight to disk, with no live dispatch of its own - unlike Apply,
    // this is meaningful to invoke even when nothing's currently
    // dirty/staged (e.g. locking in whatever Hyprland just auto-arranged
    // on its own), so it never early-returns the way applyChanges() does
    // on !root.dirty. Every entry's "workspaces" comes straight from
    // resolved[name] - the same already-exclusive mapping, so the file
    // on disk can never disagree with what the workspace-pin buttons
    // show.
    //
    // Deliberately does NOT clear pendingEnabled/pendingWorkspaces/
    // edited/selectedDirty the way applyChanges()'s own finally block
    // does - reported live as making "Set Default, then Apply" the same
    // edits impossible (Set Default wiped the staging before Apply ever
    // got a chance to dispatch it, leaving Apply with nothing left to
    // send). Leaving the staged edits alone means either order works -
    // edit, Set Default, Apply, or edit, Apply, Set Default - and each
    // button still only ever consumes the staging it actually needs
    // (Apply clears it in its own finally block once IT runs).
    //
    // Also saves which monitor is primary (double-click a card) as the
    // "__primary" key - kept out of computeCurrentSnapshot() itself
    // since everything else treats that snapshot as monitor-name keys
    // only. effectivePrimaryName rather than the raw primaryMonitor, so
    // what gets saved is the screen actually acting as primary right
    // now, never a name that isn't connected. Dashboard.qml reads it
    // back once at startup (see its savedPrimaryProcess);
    // apply-monitors.sh already skips every "__" key.
    function setDefault() {
        const storeSnapshot = root.computeCurrentSnapshot()
        if (root.effectivePrimaryName) storeSnapshot.__primary = root.effectivePrimaryName

        root.screensStore = storeSnapshot
        monitorsFile.setText(JSON.stringify(storeSnapshot, null, 2) + "\n")
    }

    // ddcutil/brightnessctl detection deliberately does NOT run here
    // (i.e. not on every panel open) - see Dashboard.qml's own
    // Component.onCompleted and applyChanges() below for the only two
    // triggers.
    onActiveChanged: {
        if (root.active) {
            root.showingDefaults = false
            root.pendingEnabled = ({})
            root.pendingWorkspaces = ({})
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

    // ---------------- switching a monitor from elsewhere ----------------
    // The bar's brightness menu switches monitors on and off by loading this
    // file out of sight (BrightnessControl.qml) and calling setEnabledNow():
    // the same as opening this tab, right-clicking the monitor and pressing
    // Apply, so its workspace pins, rescued windows and remembered mode come
    // out the same. Nothing else goes out with it - brightness staged here
    // and never applied is dropped first, as opening the tab would.
    //
    // A request waits for a read of the monitors started after it, a read
    // of monitors.json, and for an Apply still under way to finish and be
    // read back, so two switches in a row never trample each other. A read
    // already running is never restarted for monitors.json, and one that was
    // restarted for the monitors doesn't count: Quickshell hands a stopped
    // read's partial output to its handlers all the same.
    property bool monitorsRead: false
    property bool storeRead: false
    property var queuedEnable: ({})
    property int monitorsWanted: 0
    property int monitorsStartedFor: 0

    function setEnabledNow(name, enabled) {
        const queued = Object.assign({}, root.queuedEnable)
        queued[name] = enabled
        root.queuedEnable = queued
        root.readMonitorsAfresh()
        if (!screensStoreProcess.running) {
            root.storeRead = false
            root.loadScreensStore()
        }
    }

    function readMonitorsAfresh() {
        root.monitorsWanted++
        root.monitorsRead = false
        root.refreshMonitors()
    }

    function flushQueuedEnable() {
        if (!root.monitorsRead || !root.storeRead || root.applyBusy) return
        const queued = root.queuedEnable
        const names = Object.keys(queued)
        if (names.length === 0) return
        root.queuedEnable = ({})

        let any = false
        for (const name of names) {
            const base = root.baseFor(name)
            // Gone, or already that way - switched off and straight back on
            // before the first got anywhere.
            if (!base || !base.disabled === queued[name]) continue
            root.setPendingEnabled(name, queued[name])
            any = true
        }
        if (!any) return

        if (root.dashboardRoot) root.dashboardRoot.pendingBrightness = ({})
        root.applyChanges()
    }

    // An Apply still sending its lines, waiting for a monitor to come up,
    // rescuing windows or reading the result back.
    readonly property bool applyBusy: applyProcess.running || applySettleTimer.running
        || clientsQueryProcess.running
        || monitorSettleTimer.running || monitorSettleQueryProcess.running
        || root.pendingSettleMonitors.length > 0 || root.pendingRescues.length > 0

    onApplyBusyChanged: {
        if (!root.applyBusy && Object.keys(root.queuedEnable).length > 0) root.readMonitorsAfresh()
    }

    // Whether a request or an Apply still has steps to run. The bar keeps
    // its copy of this file loaded until it's false.
    readonly property bool applying: Object.keys(root.queuedEnable).length > 0 || root.applyBusy

    Process {
        id: monitorsProcess
        command: ["hyprctl", "-j", "monitors", "all"]

        onStarted: root.monitorsStartedFor = root.monitorsWanted

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.monitors = parsed
                    root.monitorsRead = root.monitorsStartedFor === root.monitorsWanted
                    root.flushQueuedEnable()
                    if (root.selectedName === "" || !root.baseFor(root.selectedName)) {
                        root.selectedName = parsed.length > 0 ? parsed[0].name : ""
                    }
                    // The X/Y boxes show where the arrangement view draws
                    // it - for a monitor Hyprland places by itself, the
                    // spot that puts it, not hyprctl's placeholder.
                    const state = root.effectiveStateFor(root.selectedName)
                    const rect = root.rectFor(root.selectedName)
                    root.displayFor = state
                        ? {
                            width: state.width, height: state.height, refresh: state.refresh, scale: state.scale,
                            x: rect ? rect.x : state.x,
                            y: rect ? rect.y : state.y
                        }
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

    // Holds applyChanges()'s workspace_rule/move/focus/rescue-focus
    // lines while waiting for a newly-enabled monitor to actually come
    // online - see newlyEnabledMonitors in applyChanges(). Only
    // populated when at least one touched monitor is transitioning from
    // disabled to enabled this Apply.
    property var pendingWorkspaceLines: []
    // Names newlyEnabledMonitors flagged this Apply - polled below via
    // monitorSettleQueryProcess until every one of them reports
    // disabled: false, rather than trusting a fixed delay (a blind
    // timer either wastes time on a monitor that comes up fast, or
    // isn't long enough for one that's genuinely slow to negotiate a
    // mode).
    property var pendingSettleMonitors: []
    property int monitorSettleAttempts: 0

    function checkMonitorsSettled() {
        monitorSettleQueryProcess.running = false
        monitorSettleQueryProcess.running = true
    }

    function dispatchPendingWorkspaceLines() {
        const sendLines = root.pendingWorkspaceLines
        root.pendingWorkspaceLines = []
        root.pendingSettleMonitors = []
        if (root.pendingRescues.length > 0) {
            root.pendingSendLines = sendLines
            clientsQueryProcess.running = false
            clientsQueryProcess.running = true
        } else {
            root.runApplyScript(sendLines)
        }
    }

    Timer {
        id: monitorSettleTimer
        // Poll cadence (via checkMonitorsSettled), not a one-shot delay.
        interval: 250
        repeat: false
        onTriggered: root.checkMonitorsSettled()
    }

    Process {
        id: monitorSettleQueryProcess
        command: ["hyprctl", "-j", "monitors", "all"]

        stdout: StdioCollector {
            onStreamFinished: {
                let ready = false
                try {
                    const parsed = JSON.parse(text)
                    ready = root.pendingSettleMonitors.every(name => {
                        const m = parsed.find(mm => mm.name === name)
                        return !!m && !m.disabled
                    })
                } catch (e) {
                    ready = false
                }

                root.monitorSettleAttempts++
                // Cap at 8 tries (~2s including the poll interval above)
                // rather than polling forever if a monitor never reports
                // ready - dispatches anyway past that point as a best
                // effort.
                if (ready || root.monitorSettleAttempts >= 8) {
                    root.dispatchPendingWorkspaceLines()
                } else {
                    monitorSettleTimer.restart()
                }
            }
        }
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

    // Every real (non-"__") monitor name Set Default has ever
    // remembered, alphabetical - used by Show Default
    // (savedArrangement). Alphabetical rather than root.monitors' own
    // (hyprctl-reported, connection-order-dependent) ordering so the
    // list doesn't reshuffle itself around whenever monitors get
    // plugged in/out in a different order, and so it still lists a
    // currently-disconnected monitor's remembered default in a stable
    // position rather than dropping it off the end.
    readonly property var defaultMonitorNames: Object.keys(root.screensStore).filter(k => !k.startsWith("__")).sort()

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
                    // Seed preferredModes from what was last saved, for
                    // any monitor not already touched this session -
                    // otherwise a disabled monitor remembered as
                    // "preferred" would show a fixed resolution until reselected
                    // once quickshell restarts. Any leftover "__"-prefixed
                    // key from before the workspace-widget toggles moved
                    // to their own barsettings.json (see ShellSettings.qml)
                    // isn't a monitor name either - skipped here rather
                    // than seeding a stray, meaningless preferredModes
                    // entry for it.
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
                root.storeRead = true
                root.flushQueuedEnable()
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

    // Write-only from here too - WorkspaceRow.qml/WorkspaceOsd.qml each
    // read this file back themselves via their own watchChanges
    // FileView, same split as monitorsFile/barSettingsFile above. See
    // applyChanges()'s own comment on liveWorkspacesSnapshot for why
    // this is a genuinely separate file from monitors.json now.
    FileView {
        id: liveWorkspacesFile
        path: Quickshell.env("HOME") + "/.config/quickshell/liveworkspaces.json"
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

    // Fills the whole tab (root is anchors.fill'd by its container).
    // contentRow fills everything above the hint row - the monitor list
    // stretches to use whatever's left instead of capping at a fixed
    // height, so the hint row always sits at the true bottom of the tab
    // regardless of how many monitors are connected.
    Item {
        id: contentWrapper

        anchors.fill: parent

        RowLayout {
            id: contentRow

            readonly property real margins: Config.scaled(18, root.uiScale)

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: hintSeparator.top
                bottomMargin: Config.scaled(14, root.uiScale)
                margins: contentRow.margins
            }
            spacing: Config.scaled(12, root.uiScale)

            readonly property real dividerWidth: Config.scaled(2, root.uiScale)
            readonly property real availableWidth: width - spacing * 2 - dividerWidth
            readonly property real leftWidth: availableWidth * 0.35
            readonly property real rightWidth: availableWidth * 0.65
            // Taller than before to fit the brightness slider + its
            // separator under the icon/label row.
            readonly property real cardHeight: Config.scaled(84, root.uiScale)

            // ---------------- LEFT: monitor list ----------------
            ColumnLayout {
                id: leftColumn

                Layout.preferredWidth: contentRow.leftWidth
                Layout.fillHeight: true
                spacing: Config.scaled(8, root.uiScale)

                Text {
                    text: "Displays"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                // Off while the right side shows the saved default, so
                // nothing gets staged that isn't on screen.
                ListView {
                    id: monitorList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    enabled: !root.showingDefaults
                    opacity: enabled ? 1 : 0.5
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
                        names: monitorNames
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
                        // See toggleEnabled()/makePrimary() for the
                        // fail-safes.
                        onToggleEnabled: root.toggleEnabled(modelData.name)
                        onMakePrimary: root.makePrimary(modelData.name)
                        onBrightnessEdited: (value) => root.setPendingBrightness(modelData.name, value)
                    }
                }
            }

            // ---------------- divider ----------------
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.fillHeight: true
                color: Config.fgcolor
            }

            // ---------------- RIGHT: arrangement + the selected display ----------------
            // The arrangement view takes whatever height the form below
            // leaves it; the form itself is a fixed set of rows.
            ColumnLayout {
                id: rightColumn

                Layout.preferredWidth: contentRow.rightWidth
                Layout.fillHeight: true
                spacing: Config.scaled(10, root.uiScale)

                // ---------------- show default ----------------
                // Swaps the arrangement view over to what Set Default saved
                // (and every login puts back), read-only: everything that
                // edits is hidden or switched off until it's pressed again.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(10, root.uiScale)

                    DashCard {
                        id: showDefaultButton

                        Layout.preferredWidth: showDefaultText.implicitWidth + Config.scaled(24, root.uiScale)
                        Layout.preferredHeight: Config.scaled(28, root.uiScale)
                        uiScale: root.uiScale
                        color: (showDefaultMouse.containsMouse || root.showingDefaults) ? Config.fgcolorhover : Config.fillcolor
                        border.color: root.showingDefaults ? Config.fgcolorlight : Config.fgcolor

                        Text {
                            id: showDefaultText
                            anchors.centerIn: parent
                            text: root.showingDefaults ? "Hide Default" : "Show Default"
                            color: root.showingDefaults ? Config.fgcolorlight : Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        MouseArea {
                            id: showDefaultMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.showingDefaults = !root.showingDefaults
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: !root.showingDefaults
                            ? "Click to pick, drag to move - snaps to the other displays"
                            : (root.defaultMonitorNames.length === 0 ? ""
                                : (root.defaultsOutOfSync ? "Saved default - not what's set now" : "Saved default - same as what's set now"))
                        color: Config.fgcolorhint
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(12, root.uiScale)
                    }
                }

                // ---------------- arrangement view ----------------
                DashCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Config.scaled(150, root.uiScale)
                    uiScale: root.uiScale
                    border.color: Config.fgcolordark

                    MonitorLayout {
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        uiScale: root.uiScale
                        displayNames: monitorNames
                        monitors: root.showingDefaults ? root.savedArrangement : root.arrangement
                        interactive: !root.showingDefaults
                        emptyText: root.showingDefaults
                            ? "Nothing saved yet. Set Default saves the arrangement you set up here, and every login puts it back."
                            : "No displays found."

                        // Steals keyboard focus from the X/Y boxes, and
                        // re-reads hyprctl like picking a card does (see
                        // selectMonitor()) - only for a different monitor,
                        // so dragging the selected one doesn't refetch.
                        onPicked: (name) => {
                            contentWrapper.forceActiveFocus()
                            if (name !== root.selectedName) root.selectMonitor(name)
                        }
                        onMoved: (name, x, y) => root.moveMonitor(name, x, y)
                        // The same as on the cards - see toggleEnabled()/
                        // makePrimary() for the fail-safes.
                        onToggleEnabled: (name) => root.toggleEnabled(name)
                        onMakePrimary: (name) => root.makePrimary(name)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !root.showingDefaults && root.overlapping.length > 0
                    wrapMode: Text.WordWrap
                    text: root.overlapping.map(n => root.displayName(n)).join(", ") + " overlap. Drag them apart so they only touch."
                    color: Config.fgcolorred
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, root.uiScale)
                    font.bold: true
                }

                // ---------------- selected display ----------------
                // Enabling and making primary are the cards' and the
                // arrangement view's (right-click, double-click) - see the
                // hint row.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(4, root.uiScale)
                    visible: !root.showingDefaults
                    spacing: Config.scaled(10, root.uiScale)

                    Text {
                        text: root.selectedName.length > 0 ? root.displayName(root.selectedName) : "No display selected"
                        textFormat: Text.PlainText
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(16, root.uiScale)
                        font.bold: true
                    }

                    // The port too, once it's been renamed.
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (root.selectedName.length > 0 && monitorNames.hasAlias(root.selectedName)
                            ? root.selectedName + (root.selectedDescription.length > 0 ? " · " : "") : "")
                            + root.selectedDescription
                        color: Config.fgcolorhint
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                    }
                }

                // ---------------- settings form ----------------
                // Two label/control pairs per row where there's room, one
                // below the other where there isn't (a large UI Scale): the
                // pairs are listed in reading order either way.
                GridLayout {
                    id: displayForm

                    Layout.fillWidth: true
                    visible: !root.showingDefaults
                    columns: rightColumn.width >= Config.scaled(840, root.uiScale) ? 4 : 2
                    columnSpacing: Config.scaled(14, root.uiScale)
                    rowSpacing: Config.scaled(10, root.uiScale)
                    enabled: root.selectedName.length > 0 && !!root.selectedState
                    opacity: displayForm.enabled ? 1 : 0.5

                    // ---------------- resolution + refresh rate ----------------
                    Text {
                        text: "Resolution"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(8, root.uiScale)

                        // The dropdowns go while Preferred's on, leaving the
                        // Preferred button right by the label.
                        DropdownBox {
                            Layout.preferredWidth: Config.scaled(230, root.uiScale)
                            visible: !root.selectedPreferred
                            enabled: root.selectedResolutions.length > 0
                            uiScale: root.uiScale
                            maxVisibleRows: 10
                            options: root.resolutionOptions
                            currentIndex: root.resolutionIndex
                            onActivated: (index) => {
                                contentWrapper.forceActiveFocus()
                                root.chooseResolution(index)
                            }
                        }

                        DropdownBox {
                            Layout.preferredWidth: Config.scaled(110, root.uiScale)
                            visible: !root.selectedPreferred
                            uiScale: root.uiScale
                            maxVisibleRows: 10
                            enabled: root.selectedRates.length > 0
                            opacity: enabled ? 1 : 0.5
                            options: root.refreshOptions
                            currentIndex: root.refreshIndex
                            onActivated: (index) => {
                                contentWrapper.forceActiveFocus()
                                root.chooseRefresh(index)
                            }
                        }

                        // On/off, lit like the Rotation buttons when on.
                        DashCard {
                            id: preferredButton

                            Layout.preferredWidth: Config.scaled(100, root.uiScale)
                            Layout.preferredHeight: Config.scaled(28, root.uiScale)
                            uiScale: root.uiScale
                            color: (preferredMouse.containsMouse || root.selectedPreferred) ? Config.fgcolorhover : Config.fillcolor
                            border.color: root.selectedPreferred ? Config.fgcolorlight : Config.fgcolor

                            Text {
                                anchors.centerIn: parent
                                text: "Preferred"
                                color: root.selectedPreferred ? Config.fgcolorlight : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            MouseArea {
                                id: preferredMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    contentWrapper.forceActiveFocus()
                                    root.togglePreferred()
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // ---------------- rotation ----------------
                    Text {
                        text: "Rotation"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    RowLayout {
                        spacing: Config.scaled(6, root.uiScale)

                        Repeater {
                            model: [0, 1, 2, 3]

                            DashCard {
                                id: turnButton

                                required property int modelData
                                readonly property bool chosen: (root.selectedTransform & 3) === turnButton.modelData

                                Layout.preferredWidth: Config.scaled(52, root.uiScale)
                                Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                uiScale: root.uiScale
                                color: (turnMouse.containsMouse || turnButton.chosen) ? Config.fgcolorhover : Config.fillcolor
                                border.color: turnButton.chosen ? Config.fgcolorlight : Config.fgcolor

                                Text {
                                    anchors.centerIn: parent
                                    text: (turnButton.modelData * 90) + "°"
                                    color: turnButton.chosen ? Config.fgcolorlight : Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                MouseArea {
                                    id: turnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        contentWrapper.forceActiveFocus()
                                        root.chooseRotation(turnButton.modelData)
                                    }
                                }
                            }
                        }

                        // A mirrored transform (4-7) is only ever passed
                        // through from hyprctl or monitors.json, never set
                        // here - the buttons keep it.
                        Text {
                            visible: (root.selectedTransform & 4) !== 0
                            text: "flipped"
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(12, root.uiScale)
                        }
                    }

                    // ---------------- scale ----------------
                    // Only stops on scales Hyprland takes as they are at
                    // this resolution (see scalesFor()), so a scale never
                    // gets swapped for another behind your back. Changes
                    // live in the arrangement view while dragging.
                    Text {
                        text: "Scale"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(12, root.uiScale)

                        DeviceSlider {
                            Layout.fillWidth: true
                            Layout.minimumWidth: Config.scaled(120, root.uiScale)
                            Layout.preferredHeight: implicitHeight
                            uiScale: root.uiScale
                            value: root.scaleOptions.length > 1 ? root.scaleIndex / (root.scaleOptions.length - 1) : 0.5
                            onMoved: (newValue) => {
                                const options = root.scaleOptions
                                const i = Math.max(0, Math.min(options.length - 1, Math.round(newValue * (options.length - 1))))
                                root.chooseScale(options[i])
                            }
                        }

                        // Fixed width, so the slider doesn't shift as the
                        // numbers change length.
                        Text {
                            Layout.preferredWidth: Config.scaled(190, root.uiScale)
                            text: root.formatScale(root.selectedScale) + "x  ·  " + root.selectedLogicalSize
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }
                    }

                    // ---------------- workspace pins (1-5) ----------------
                    // Binds the selected monitor to any of workspaces 1-5
                    // (hl.workspace_rule({ workspace, monitor })) - several
                    // can be lit at once, since Hyprland allows more than
                    // one workspace defaulting to the same monitor.
                    Text {
                        text: "Workspaces"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    RowLayout {
                        spacing: Config.scaled(8, root.uiScale)

                        Repeater {
                            model: [1, 2, 3, 4, 5]

                            DashCard {
                                id: wsButton
                                required property int modelData

                                // Every workspace 1-5 always belongs to
                                // exactly one monitor once Apply resolves it
                                // (see seedDefaultWorkspacesIfFresh()/
                                // resolveWorkspaceAssignment() above, and
                                // toggleWorkspace()'s no-op-if-already-
                                // bound guard) - so only two states are ever
                                // meaningful here: bound to the monitor
                                // currently selected in this panel (fgcolor),
                                // or not (fgcolordark). Clicking an unbound
                                // one reassigns it here (see
                                // toggleWorkspace()).
                                readonly property bool bound: root.workspacesFor(root.selectedName).includes(modelData)

                                Layout.preferredWidth: Config.scaled(28, root.uiScale)
                                Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                uiScale: root.uiScale
                                color: wsMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                border.color: wsButton.bound ? Config.fgcolor : Config.fgcolordark

                                Text {
                                    anchors.centerIn: parent
                                    text: String(wsButton.modelData)
                                    color: wsButton.bound ? Config.fgcolor : Config.fgcolordark
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
                    }

                    // ---------------- position ----------------
                    // For exact numbers - dragging in the arrangement view
                    // fills these in. Hyprland's layout coordinates, in
                    // logical pixels.
                    Text {
                        text: "Position"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    RowLayout {
                        spacing: Config.scaled(8, root.uiScale)

                        Text {
                            text: "X"
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        LabeledField {
                            Layout.preferredWidth: Config.scaled(90, root.uiScale)
                            uiScale: root.uiScale * 0.875
                            showLabel: false
                            value: root.displayFor.x !== undefined ? String(root.displayFor.x) : ""
                            onEdited: (text) => root.setEdited("x", parseInt(text, 10) || 0)
                        }

                        Text {
                            Layout.leftMargin: Config.scaled(6, root.uiScale)
                            text: "Y"
                            color: Config.fgcolorhint
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        LabeledField {
                            Layout.preferredWidth: Config.scaled(90, root.uiScale)
                            uiScale: root.uiScale * 0.875
                            showLabel: false
                            value: root.displayFor.y !== undefined ? String(root.displayFor.y) : ""
                            onEdited: (text) => root.setEdited("y", parseInt(text, 10) || 0)
                        }
                    }
                }

                // ---------------- identify / set default / apply ----------------
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.showingDefaults
                    Layout.topMargin: Config.scaled(6, root.uiScale)

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

                    // Set Default writes monitors.json (what replays at
                    // the next Hyprland login) - see setDefault()'s own
                    // comment. Left of Apply (which only ever dispatches
                    // live), same reading order as the two actions' own
                    // scope: "what should happen every time" before "what
                    // should happen right now".
                    DashCard {
                        id: setDefaultButton

                        Layout.preferredWidth: Config.scaled(120, root.uiScale)
                        Layout.preferredHeight: Config.scaled(32, root.uiScale)
                        Layout.rightMargin: Config.scaled(8, root.uiScale)
                        uiScale: root.uiScale

                        property color blinkColor: Config.fgcolor
                        // defaultsOutOfSync, not root.dirty - see its own
                        // comment for why "something's staged" and
                        // "there's actually something new to persist"
                        // aren't the same thing.
                        border.color: root.defaultsOutOfSync ? setDefaultButton.blinkColor : Config.fgcolordark
                        color: setDefaultMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor

                        SequentialAnimation {
                            running: root.defaultsOutOfSync
                            loops: Animation.Infinite
                            ColorAnimation { target: setDefaultButton; property: "blinkColor"; to: Config.fgcolorlight; duration: 800 }
                            ColorAnimation { target: setDefaultButton; property: "blinkColor"; to: Config.fgcolor; duration: 800 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Set Default"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                        }

                        MouseArea {
                            id: setDefaultMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contentWrapper.forceActiveFocus()
                                root.setDefault()
                            }
                        }
                    }

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
        // Anchored up from hintRow at the bottom now, not down from
        // contentRow - contentRow's own bottom anchors to this
        // Rectangle's top (see above), so anchoring this the other way
        // around would be circular. Stops at the same margins as
        // contentRow above, not its own separate fixed inset.
        Rectangle {
            id: hintSeparator
            anchors {
                left: parent.left
                right: parent.right
                bottom: hintRow.top
                bottomMargin: Config.scaled(10, root.uiScale)
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
                bottom: parent.bottom
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

            HintItem {
                uiScale: root.uiScale
                prefix: "Drag"
                iconSource: Quickshell.iconPath("input-mouse-click-left-symbolic")
                label: "Arrange Displays"
            }

            HintItem {
                uiScale: root.uiScale
                iconSource: Quickshell.iconPath("input-mouse-click-middle-symbolic", "input-mouse-symbolic")
                label: "Rename (here only)"
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

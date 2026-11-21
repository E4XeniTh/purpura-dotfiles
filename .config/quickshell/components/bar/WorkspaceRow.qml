import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import "../../Config.js" as Config
import "../common"
import "../common/WorkspaceRegistryLogic.js" as RegistryLogic

// One rectangle per current Hyprland workspace, sorted by owning
// monitor position first and workspace number second - meant to sit
// directly to the left of Bar.qml's clock (the dashboard-open button),
// which sets this Row's own height from the outside. Each box is
// width-only aspect-ratio scaled to its own monitor
// (HyprlandMonitor.width/height) and draws a live miniature grid of
// that workspace's actual windows underneath a faint workspace-number
// label.
Row {
    id: root

    // Fed in by Bar.qml (the per-screen Config.uiScale).
    property real uiScale: 1.0
    // The output this row's bar is on, also from Bar.qml - a dropped window
    // is only taken by the bar it was dropped on.
    property string screenName: ""

    // ---------------- dropping a dragged window on a workspace ----------------
    // purpura.lua (~/.config/hypr/purpura.lua) follows a window dragged with
    // the "Drag window" bind (mainMod + LMB unless it's been moved) and tells
    // the shell about it through custom events on Hyprland's socket - the bar
    // itself never sees the cursor during a drag, as Hyprland keeps the
    // pointer on the dragged window:
    //   purpura-drag,start,<address>            a drag of that window began
    //   purpura-drag,over,<monitor>,<workspace> the cursor is on that
    //                                           workspace's box, on that
    //                                           monitor's bar
    //   purpura-drag,between,<monitor>          on a separator between two
    //                                           monitors' boxes there
    //   purpura-drag,at,<monitor>,<x>,<y>       where on that monitor it is,
    //                                           while it's on either
    //   purpura-drag,off                        it's on neither
    //   purpura-drag,monitor,<monitor>          the cursor's on that monitor
    //                                           (from the start, then on
    //                                           every change)
    //   purpura-drag,end                        it's over
    // purpura.lua knows where this row's boxes are (sendDropTargets below),
    // finds the cursor in them, and sends the window to the workspace of the
    // box it's let go on, by itself - and picks up a window drawn in a box
    // pressed with the drag's combo, for Hyprland to drag from there. Here,
    // the box under the cursor just lights up.
    property bool windowDragging: false
    // Whether this row hands purpura.lua its boxes: one row per monitor -
    // the bar's while it's shown, Bar.qml's floating copy's whenever it
    // isn't (shown or not, so they're there the moment it appears). A
    // hidden bar's row would otherwise send its own, wrong, spans for the
    // same monitor.
    property bool sendsDropTargets: true
    // Bar.qml's floating copy only: where on the screen its window sits,
    // { x, y, w, h } - handed over with the boxes, so purpura.lua can grab from
    // it before Hyprland's even mapped the window (a META + click as quick as
    // the META).
    property var floatingRect: null
    // The box under the cursor on this bar, by workspaceSelector() - only
    // ever compared, never run.
    property string dragOver: ""
    // The monitor the cursor's on during a drag - Bar.qml shows its floating
    // copy of the widget only there.
    property string dragMonitor: ""
    // The monitor the cursor's on while the drag's modifier is held (META, for
    // META + LMB), drag or not - Bar.qml gets its floating copy ready there at
    // once, and shows it once modShown (a moment later).
    property string modMonitor: ""
    property bool modShown: false
    // The cursor's on this bar's widget - a box or a separator - where the
    // window itself is hidden, so Bar.qml shows its icon instead.
    property bool dragHere: false
    // The cursor's on a box or a separator on some bar - this one or another.
    property bool dragOverAnywhere: false
    // The dragged window, by address, and where the cursor is on this row's
    // monitor while it's on the widget - for Bar.qml's icon of the window
    // under the cursor, which shows dragIconSource (see iconSourceFor()).
    property string dragAddress: ""
    property point dragPointer: Qt.point(0, 0)
    readonly property var draggedToplevel: {
        const wanted = root.dragAddress.replace(/^0x0*/, "").toLowerCase()
        if (!wanted) return null
        return Hyprland.toplevels.values.find(t => String(t.address).replace(/^0*/, "").toLowerCase() === wanted) || null
    }
    readonly property string dragIconSource: root.draggedToplevel && root.draggedToplevel.lastIpcObject
        ? root.iconSourceFor(String(root.draggedToplevel.lastIpcObject.class || ""))
        : ""

    // Should an end never arrive (the shell restarted mid-drag), the
    // highlight doesn't stay on for good.
    Timer {
        id: dragSafetyTimer
        interval: 120000
        onTriggered: {
            root.windowDragging = false
            root.dragOver = ""
            root.dragHere = false
            root.dragMonitor = ""
        }
    }

    function handleDragEvent(data) {
        const parts = String(data).split(",")
        if (parts[0] !== "purpura-drag") return
        if (parts[1] === "start") {
            root.windowDragging = true
            root.dragOver = ""
            root.dragHere = false
            root.dragMonitor = ""
            root.dragAddress = /^0x[0-9a-fA-F]{1,16}$/.test(parts[2] || "") ? parts[2] : ""
            root.dragOverAnywhere = false
            dragSafetyTimer.restart()
            root.sendDropTargets(true)
        } else if (parts[1] === "over") {
            root.dragOver = parts[2] === root.screenName ? (parts[3] || "") : ""
            root.dragHere = parts[2] === root.screenName
            root.dragOverAnywhere = true
        } else if (parts[1] === "mod") {
            root.modMonitor = /^[A-Za-z0-9_.-]{1,64}$/.test(parts[2] || "") ? parts[2] : ""
            root.modShown = root.modMonitor !== "" && parts[3] === "1"
        } else if (parts[1] === "monitor") {
            root.dragMonitor = /^[A-Za-z0-9_.-]{1,64}$/.test(parts[2] || "") ? parts[2] : ""
        } else if (parts[1] === "between") {
            root.dragOver = ""
            root.dragHere = parts[2] === root.screenName
            root.dragOverAnywhere = true
        } else if (parts[1] === "at") {
            const integer = /^-?\d{1,6}$/
            if (parts.length === 5 && parts[2] === root.screenName && integer.test(parts[3]) && integer.test(parts[4]))
                root.dragPointer = Qt.point(parseInt(parts[3], 10), parseInt(parts[4], 10))
        } else if (parts[1] === "off") {
            root.dragOver = ""
            root.dragHere = false
            root.dragOverAnywhere = false
        } else if (parts[1] === "end") {
            root.windowDragging = false
            root.dragOver = ""
            root.dragHere = false
            root.dragMonitor = ""
            root.dragOverAnywhere = false
            root.dragAddress = ""
            dragSafetyTimer.stop()
        }
    }

    // A window's icon, from its class - for each window drawn in the boxes
    // below, and for Bar.qml's icon of the window being dragged.
    //
    // Real per-app icon, the same way Tray.qml gets one - its Image binds
    // straight to SystemTray's own already-resolved .icon rather than
    // guessing an icon-theme name. There's no such direct icon on a Hyprland
    // toplevel, but DesktopEntries.heuristicLookup() matches a window's WM
    // class to its installed .desktop file and returns that entry's real icon
    // name, which resolves correctly far more often than assuming the icon
    // theme has an entry literally named after the raw class string (the
    // fallback below, for whatever heuristicLookup can't match).
    //
    // heuristicLookup() itself only ever tries an exact desktop-file-id match
    // or an exact (case-insensitive) StartupWMClass match (confirmed against
    // Quickshell's own source) - it has no substring/fuzzy matching at all.
    // Flatpak apps commonly report a short runtime class ("waterfox") that
    // matches neither their reverse-DNS desktop file id nor StartupWMClass
    // ("net.waterfox.waterfox"), so heuristicLookup comes back empty and this
    // fell all the way through to the generic fallback icon. Falls back here
    // to a substring search over every installed .desktop entry's own id for
    // one that contains the window's class, so Waterfox (and anything else
    // shaped the same way) still resolves to its real icon.
    //
    // The plain single-arg iconPath() renders "a missing texture" image when
    // the name doesn't resolve in the current icon theme (documented
    // behavior, not a bug) rather than failing quietly - the two-arg fallback
    // form loads a generic icon instead whenever the specific app/class name
    // isn't a real theme icon, same fallback pattern the shell uses elsewhere.
    function substringLookup(cls) {
        const lower = cls.toLowerCase()
        const apps = DesktopEntries.applications.values
        for (const app of apps) {
            if (app.id.toLowerCase().includes(lower)) return app
        }
        return null
    }

    function iconSourceFor(cls) {
        const entry = cls.length > 0 ? (DesktopEntries.heuristicLookup(cls) ?? root.substringLookup(cls)) : null
        const name = entry && entry.icon.length > 0 ? entry.icon : cls
        return name.length > 0
            ? Quickshell.iconPath(name, "application-x-executable")
            : Quickshell.iconPath("application-x-executable")
    }

    // A workspace by its Hyprland id (purpura.lua's selectors go by those, not
    // by purpura's numbers), or by name when it has one (no quotes or anything
    // else that could end the Lua string).
    function workspaceSelector(workspace) {
        if (workspace.id > 0) return String(workspace.id)
        const name = workspace.name || ""
        return /^[A-Za-z0-9 _.-]{1,64}$/.test(name) ? "name:" + name : ""
    }

    // Each box's span across the bar, in the bar's own coordinates (the gap
    // after a box counts as half its own, half the next's), its workspace,
    // the area of the monitor that's on - for purpura.lua to land a
    // floating window inside - and the box itself (bx/by/bw/bh), which
    // draws that area scaled down: from it, purpura.lua finds the window
    // drawn under a press of the drag's combo in a box and picks that window
    // up, then and there, for Hyprland to drag like any other. Then the
    // separators' spans between monitors' boxes, where the window stays
    // hidden though there's nothing to drop it on. Handed over as
    // Lua, through hyprctl eval: the only strings in it are the checked
    // monitor name and workspaceSelector()s, the rest are whole numbers.
    //
    // The press needs them there already, so they're handed over whenever
    // they'd come out different - looked at on any change the row knows of
    // and once a second besides (dropTargetsCheck) - and again at a drag's
    // start, and after a config reload, which starts purpura.lua over
    // without them.
    property string sentDropTargets: ""

    function sendDropTargets(force) {
        if (!root.sendsDropTargets) return
        const lua = root.dropTargetsLua()
        if (!lua || (!force && lua === root.sentDropTargets)) return
        root.sentDropTargets = lua
        Quickshell.execDetached(["hyprctl", "eval", lua])
    }

    function refreshDropTargets() {
        root.sendDropTargets(false)
    }

    function dropTargetsLua() {
        if (!/^[A-Za-z0-9_.-]{1,64}$/.test(root.screenName)) return ""
        // A row that's only just been put on screen (Bar.qml's floating
        // copy), or just changed, may not have placed its boxes yet.
        root.forceLayout()
        const half = root.spacing / 2
        const boxes = []
        const between = []
        for (const child of root.children) {
            const entry = child.modelData
            const box = child.item
            if (entry && entry.kind === "separator" && box) {
                const span = [child.mapToItem(null, -half, 0).x, child.mapToItem(null, child.width + half, 0).x]
                if (span.every(n => Number.isFinite(n)))
                    between.push(`{ from = ${Math.floor(span[0])}, to = ${Math.floor(span[1])} }`)
                continue
            }
            if (!entry || entry.kind !== "workspace" || !box) continue
            const workspace = root.workspaceSelector(entry.ws)
            const mon = entry.ws.monitor
            if (!workspace || !mon || !(mon.scale > 0)) continue
            const corner = box.mapToItem(null, 0, 0)
            const numbers = [
                child.mapToItem(null, -half, 0).x,
                child.mapToItem(null, child.width + half, 0).x,
                mon.x, mon.y, mon.width / mon.scale, mon.height / mon.scale,
                corner.x, corner.y, box.width, box.height
            ]
            if (!numbers.every(n => Number.isFinite(n))) continue
            const [from, to, x, y, w, h, bx, by, bw, bh] = numbers.map(n => Math.floor(n))
            boxes.push(`{ from = ${from}, to = ${to}, workspace = "${workspace}", x = ${x}, y = ${y}, w = ${w}, h = ${h}, `
                + `bx = ${bx}, by = ${by}, bw = ${bw}, bh = ${bh} }`)
        }
        const rect = root.floatingRect
        const at = rect && [rect.x, rect.y, rect.w, rect.h].every(n => Number.isFinite(n))
            ? `, { x = ${Math.round(rect.x)}, y = ${Math.round(rect.y)}, w = ${Math.round(rect.w)}, h = ${Math.round(rect.h)} }`
            : ""
        return `purpura.dropTargets("${root.screenName}", { ${boxes.join(", ")} }, { ${between.join(", ")} }${at})`
    }

    // Catches the boxes moving without the row hearing of it - the row
    // shifting along the bar as the clock beside it changes width, say.
    // Nothing's sent unless they've changed.
    Timer {
        id: dropTargetsCheck
        interval: 1000
        repeat: true
        running: root.sendsDropTargets
        triggeredOnStart: true
        onTriggered: root.refreshDropTargets()
    }

    // Once laid out again, rather than at the next check. A row just put on
    // screen sends them whatever it sent before: another row may have sent
    // its own for the same monitor meanwhile.
    onSendsDropTargetsChanged: {
        root.sentDropTargets = ""
        if (root.sendsDropTargets) Qt.callLater(root.refreshDropTargets)
    }
    onSettledEntriesChanged: Qt.callLater(root.refreshDropTargets)
    onFloatingRectChanged: Qt.callLater(root.refreshDropTargets)
    onXChanged: Qt.callLater(root.refreshDropTargets)
    onYChanged: Qt.callLater(root.refreshDropTargets)
    onWidthChanged: Qt.callLater(root.refreshDropTargets)
    onHeightChanged: Qt.callLater(root.refreshDropTargets)

    spacing: Config.scaled(4, root.uiScale)

    // Every connected screen, left-to-right by x - ties (side-by-side
    // monitors stacked vertically instead) broken by whichever is
    // closest to y = 0, so a monitor placed above the reference point
    // sorts before one placed further below it. Only used below to
    // rank which monitor each workspace belongs to.
    readonly property var sortedMonitors: Quickshell.screens.slice().sort((a, b) => {
        if (a.x !== b.x) return a.x - b.x
        return Math.abs(a.y) - Math.abs(b.y)
    })

    // Show Empty Workspaces In Widget (Settings > General > Shell > Main Bar): a
    // workspace that's empty and not on screen gets a box too. Display settings'
    // pins are kept by Hyprland (persistent - purpura.lua's WORKSPACES), so they're
    // there whether anything's on them or not; without this, the empty ones not
    // shown are left out, as when Hyprland let them go.
    readonly property bool showEmptyWidget: !!root.barSettingsStore.showEmptyWidget

    // purpura.lua's book of the workspaces - each one's purpura number and type
    // (WorkspaceRegistry.qml).
    WorkspaceRegistry {
        id: registry
        onBookChanged: renderSettleTimer.restart()
    }

    readonly property var sortedWorkspaces: {
        const monitorRank = {}
        root.sortedMonitors.forEach((s, i) => { monitorRank[s.name] = i })

        // Hyprland.workspaces.values can briefly hold two entries for
        // the same id when switching creates a brand new workspace
        // (e.g. onto a number nobody's visited this session) - the
        // old/about-to-be-pruned object and the new one, the new one
        // sometimes surfacing with .monitor still null for a tick
        // before Hyprland finishes assigning it. Deduped by id here
        // (globally unique) rather than trusting the raw list
        // untouched, preferring whichever copy already has a resolved
        // monitor - this is what let an extra/duplicate box flash for
        // ~20ms during a workspace swap.
        const byId = new Map()
        for (const w of Hyprland.workspaces.values) {
            const prev = byId.get(w.id)
            if (!prev || (!prev.monitor && w.monitor)) byId.set(w.id, w)
        }

        // Which of them get a box, in what order (WorkspaceRegistryLogic.js's
        // rowWorkspaces): by monitor, left to right, then by purpura number; an
        // empty one not on screen only with Show Empty Workspaces In Widget; a
        // monitor's unmanaged ones (anything not pinned - an app's own, a new one,
        // a spare) only when it has two or more, unless Show Single Workspace
        // Monitors.
        const records = Array.from(byId.values()).map(w => ({
            id: w.id,
            monitor: w.monitor ? w.monitor.name : "",
            rank: (w.monitor && monitorRank[w.monitor.name] !== undefined) ? monitorRank[w.monitor.name] : 999,
            empty: w.toplevels.values.length === 0,
            shown: !!w.monitor && !!w.monitor.activeWorkspace && w.monitor.activeWorkspace.id === w.id,
            ws: w
        }))
        return RegistryLogic.rowWorkspaces(registry.book, records, {
            showEmpty: root.showEmptyWidget,
            showSingle: root.showSingleWorkspaceMonitors
        }).map(r => r.ws)
    }

    // sortedWorkspaces with a "separator" marker spliced in wherever the
    // owning monitor changes between one entry and the next, so the Row
    // below can draw a small divider between each monitor's group of
    // workspace boxes instead of one continuous, ungrouped run of them.
    //
    // This is the "live" computation - re-evaluates the instant any
    // dependency changes (Hyprland.workspaces, the book, etc).
    // Deliberately NOT what the Repeater below renders directly - see
    // settledEntries.
    readonly property var rowEntries: {
        const list = []
        let lastMonitorName = null
        for (const ws of root.sortedWorkspaces) {
            const monName = ws.monitor ? ws.monitor.name : ""
            if (lastMonitorName !== null && monName !== lastMonitorName) {
                list.push({ kind: "separator" })
            }
            list.push({ kind: "workspace", ws: ws })
            lastMonitorName = monName
        }
        return list
    }

    // What the Repeater below actually renders - a debounced snapshot of
    // rowEntries, not rowEntries itself. A single Apply dispatches many
    // sequential hyprctl eval calls (one monitor line, then a
    // workspace_rule + move pair per workspace, then focus dispatches -
    // see ScreenSettings.qml), and Hyprland fires a raw event after each
    // one lands, live, immediately - rowEntries being a plain reactive
    // binding meant every one of those intermediate, mid-transition
    // states got rendered for a frame before the next one arrived
    // (reported live as boxes jittering/repositioning during a
    // workspace/display swap, and a workspace appearing to blink in and
    // back out - most likely a workspace object's own .monitor
    // momentarily reporting null or its old owner while Hyprland was
    // still mid-reassignment). renderSettleTimer coalesces the burst of
    // raw events from one Apply into a single render of the FINAL state
    // once they stop, rather than one render per intermediate event.
    property var settledEntries: []

    Timer {
        id: renderSettleTimer
        interval: 120
        repeat: false
        onTriggered: root.settledEntries = root.rowEntries
    }

    // A toplevel's lastIpcObject (the only place its at/size/class live
    // - see WindowBox below) is only ever as fresh as the last
    // refreshToplevels() call, unlike title/activated/workspace which
    // update live - re-requested on every Hyprland event so the little
    // per-window rectangles track real opens/closes/moves/resizes
    // instead of a one-off snapshot from whenever quickshell started.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom") {
                root.handleDragEvent(event.data)
                return
            }
            // purpura.lua starts over without the boxes (see sendDropTargets()).
            if (event.name === "configreloaded") {
                // Its release won't be posted by the purpura.lua there is now.
                root.modMonitor = ""
                root.modShown = false
                root.sentDropTargets = ""
                Qt.callLater(root.refreshDropTargets)
            }
            Hyprland.refreshToplevels()
            renderSettleTimer.restart()
        }
    }
    Component.onCompleted: {
        Hyprland.refreshToplevels()
        // Seed the very first render immediately - no reason to wait out
        // a settle delay before anything has been drawn at all.
        root.settledEntries = root.rowEntries
    }

    // General > Shell settings (ShellSettings.qml) - a separate file from
    // monitors.json, watched the same way, since these are simple
    // immediately-saved toggles rather than staged/Apply-dependent
    // monitor state.
    FileView {
        id: barSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/barsettings.json"
        watchChanges: true
        onFileChanged: reload()
    }

    readonly property var barSettingsStore: {
        try {
            return JSON.parse(barSettingsFile.text())
        } catch (e) {
            return {}
        }
    }

    // Settings > General > Shell > Main Bar's "Show Single Workspace Monitors"
    // (see sortedWorkspaces): on unless turned off. A barsettings.json from
    // before it goes by the "Only Managed Workspaces In Widget" it replaced -
    // on there is off here.
    readonly property bool showSingleWorkspaceMonitors: root.barSettingsStore.showSingleWorkspaceMonitors !== undefined
        ? !!root.barSettingsStore.showSingleWorkspaceMonitors
        : !root.barSettingsStore.strictWorkspaceWidget

    Repeater {
        model: root.settledEntries

        Loader {
            id: entryLoader
            required property var modelData

            sourceComponent: entryLoader.modelData.kind === "separator" ? separatorComponent : workspaceComponent
        }
    }

    Component {
        id: separatorComponent
        Row {
            Rectangle { width: Config.scaled(15, root.uiScale); height: 1 ; color: "transparent"}
            Rectangle {
                width: Config.scaled(2, root.uiScale)
                height: root.height * 0.6
                // y rather than anchors.verticalCenter: a Loader with an
                // explicit height stretches a non-fill-anchored child to
                // match it (confirmed live - giving entryLoader
                // height: root.height to fix this separator sitting at the
                // top instead made it stretch to full height, overriding
                // this Rectangle's own 60%). Computing y directly against
                // root.height sidesteps the Loader's size entirely - Row
                // only manages its children's x, never y, so this is the
                // only positioning that actually applies.
                y: (root.height - height) / 2
                color: Config.fgcolor
            }
            Rectangle { width: Config.scaled(15, root.uiScale); height: 1 ; color: "transparent"}
        }
    }

    Component {
        id: workspaceComponent

        Rectangle {
            id: wsBox

            // parent is entryLoader (Loader reparents its loaded item
            // directly) - .ws rather than .modelData itself since the
            // Repeater's own model entries are now { kind, ws } wrappers,
            // not bare workspace objects, to make room for the
            // separator markers spliced into rowEntries above.
            readonly property var modelData: wsBox.parent.modelData.ws

            readonly property var mon: wsBox.modelData.monitor

            // purpura's number for it (see the label below).
            readonly property int number: registry.numberOf(wsBox.modelData)

            // Compared by id against the monitor's live activeWorkspace,
            // not read off modelData.active: the boxes are a settled
            // snapshot (see renderSettleTimer), and the border's to light
            // up the moment the switch happens, not once that catches up.
            readonly property bool isActive: !!wsBox.mon
                && !!wsBox.mon.activeWorkspace
                && wsBox.mon.activeWorkspace.id === wsBox.modelData.id

            // HyprlandMonitor.width/height are the raw/physical output
            // resolution (straight from hyprctl's own JSON), but a
            // window's at/size (and monitor.x/y) are in logical,
            // already-scale-divided coordinates - dividing a logical
            // window size by the unscaled monitor width/height made
            // every window rectangle too small by exactly a factor of
            // scale (e.g. half size at 200%/2x). These are the
            // logical/effective dimensions to actually match against.
            readonly property real monWidth: (wsBox.mon && wsBox.mon.scale > 0) ? wsBox.mon.width / wsBox.mon.scale : 0
            readonly property real monHeight: (wsBox.mon && wsBox.mon.scale > 0) ? wsBox.mon.height / wsBox.mon.scale : 0

            readonly property real aspect: (wsBox.mon && wsBox.mon.height > 0)
                ? (wsBox.mon.width / wsBox.mon.height)
                : (16 / 9)

            // Where a window being dragged would go, if let go now.
            readonly property bool dropTarget: root.windowDragging && root.dragOver !== ""
                && root.workspaceSelector(wsBox.modelData) === root.dragOver

            // One of its windows in real fullscreen - exclusive, the whole
            // monitor (Hyprland's internal mode 2), not just maximized: its
            // border's dashed (DashedBorder, below), in the same colors.
            readonly property bool exclusiveFullscreen: !!wsBox.modelData.hasFullscreen
                && wsBox.modelData.toplevels.values.some(t => !!t.lastIpcObject && t.lastIpcObject.fullscreen === 2)

            height: root.height
            width: wsBox.height * wsBox.aspect
            color: wsBox.dropTarget ? Config.fgcolorhover : Config.fillcolor
            border.width: wsBox.exclusiveFullscreen ? 0 : Config.scaled(2, root.uiScale)
            // A workspace holding a fullscreen app takes the border
            // Hyprland gives that app (fgcolorfullscreen) - dimmed the way
            // fgcolordarklight is to fgcolorlight when it isn't the one
            // shown on its monitor - so it always reads as more prominent
            // than one that doesn't, active or not.
            border.color: wsBox.dropTarget ? Config.fgcolorlight
                : wsBox.modelData.hasFullscreen
                ? (wsBox.isActive ? Config.fgcolorfullscreen : Qt.darker(Config.fgcolorfullscreen, 1.3))
                : (wsBox.isActive ? Config.fgcolor : Config.fgcolordark)
            radius: 0
            // A window that's fullscreened, off-monitor mid-drag, or
            // just rounds slightly past its workspace's edge would
            // otherwise draw outside this box's own border - clipped
            // to keep every window rectangle strictly inside it.
            clip: true

            // One rectangle per window actually open on this
            // workspace, positioned/sized as a fraction of the owning
            // monitor's geometry (at/size are absolute layout
            // coordinates, same space as monitor.x/y/width/height) so
            // it lands in the same relative spot inside this miniature
            // box.
            Repeater {
                model: wsBox.modelData.toplevels.values

                Rectangle {
                    id: winBox
                    required property var modelData

                    readonly property var ipcData: winBox.modelData.lastIpcObject
                    readonly property var atArr: winBox.ipcData.at ?? [0, 0]
                    readonly property var sizeArr: winBox.ipcData.size ?? [0, 0]
                    readonly property string winClass: winBox.ipcData.class ?? ""
                    // No dedicated "fullscreen" QML property on a
                    // Hyprland toplevel - only lastIpcObject carries
                    // it, straight from hyprctl clients' own field.
                    readonly property bool isFullscreen: !!winBox.ipcData.fullscreen

                    // A fullscreen window's own reported at/size isn't
                    // trusted to already cover the full monitor exactly
                    // - forced to fill this box outright instead, and
                    // every other window on the same workspace is
                    // hidden entirely rather than drawn underneath it
                    // (see visible below), matching what's actually on
                    // screen once something goes fullscreen.
                    x: winBox.isFullscreen ? 0
                        : (wsBox.mon ? (winBox.atArr[0] - wsBox.mon.x) / wsBox.monWidth * wsBox.width : 0)
                    y: winBox.isFullscreen ? 0
                        : (wsBox.mon ? (winBox.atArr[1] - wsBox.mon.y) / wsBox.monHeight * wsBox.height : 0)
                    width: winBox.isFullscreen ? wsBox.width
                        : ((wsBox.mon && wsBox.monWidth > 0)
                            ? Math.max(1, winBox.sizeArr[0] / wsBox.monWidth * wsBox.width)
                            : 1)
                    height: winBox.isFullscreen ? wsBox.height
                        : ((wsBox.mon && wsBox.monHeight > 0)
                            ? Math.max(1, winBox.sizeArr[1] / wsBox.monHeight * wsBox.height)
                            : 1)

                    // Gone while it's the window being dragged and the cursor's on
                    // the widget, where the window itself is hidden too.
                    visible: (!wsBox.modelData.hasFullscreen || winBox.isFullscreen)
                        && !(root.windowDragging && root.dragOverAnywhere && winBox.modelData === root.draggedToplevel)

                    color: "transparent"
                    border.width: Config.scaled(1, root.uiScale)
                    // Only lit up fgcolor when BOTH this window is the
                    // focused one ("activated") AND its workspace is the
                    // currently active one on its monitor - a focused
                    // window sitting on a workspace you've since
                    // switched away from should still read as dimmed,
                    // not call attention to itself.
                    border.color: (wsBox.isActive && winBox.modelData.activated)
                        ? Config.fgcolor
                        : Config.fgcolordark

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.max(Config.scaled(4, root.uiScale), Math.min(winBox.width, winBox.height) * 0.6)
                        source: root.iconSourceFor(winBox.winClass)
                    }
                }
            }

            // The border of one holding a window in real fullscreen (see
            // exclusiveFullscreen): over its windows the way a border is,
            // under the number.
            DashedBorder {
                z: 5
                visible: wsBox.exclusiveFullscreen
                color: wsBox.border.color
                thickness: Config.scaled(2, root.uiScale)
                dash: Config.scaled(6, root.uiScale)
                gap: Config.scaled(4, root.uiScale)
            }

            // Faint workspace number, drawn above the window grid (z
            // higher than the Repeater's default stacking) so it stays
            // legible regardless of how many window/icon rectangles are
            // packed underneath it: purpura's number for it (the book's -
            // see WorkspaceRegistry.qml), 1-5 for the pinned ones and from 6
            // up for the rest. None for one the book can't number (a special
            // workspace, or with no book, anything past 5).
            Text {
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    rightMargin: Config.scaled(4, root.uiScale)
                }
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignBottom
                z: 10
                visible: wsBox.number >= 1
                text: String(wsBox.number)
                color: Config.fgcolor
                opacity: 0.75
                // Outline so the number stays legible over whatever's
                // underneath it (light window rectangles/icons, not
                // just the box's own dark fill).
                style: Text.Outline
                styleColor: "black"
                font.family: Config.fontfamily
                font.bold: true
                font.pixelSize: Math.max(Config.scaled(8, root.uiScale), Math.min(wsBox.width, wsBox.height) * 0.55)
            }

            // Switches to this workspace - Hyprland's own activate(),
            // equivalent to HyprlandIpc.dispatch("workspace <name>").
            // Covers the whole box (window-grid rectangles/icons and
            // the number label underneath have no MouseAreas of their
            // own to compete with). The drag's combo on a window drawn here
            // never reaches it: purpura.lua picks that window up and
            // Hyprland drags it (see sendDropTargets()).
            MouseArea {
                anchors.fill: parent
                onClicked: wsBox.modelData.activate()
            }
        }
    }
}

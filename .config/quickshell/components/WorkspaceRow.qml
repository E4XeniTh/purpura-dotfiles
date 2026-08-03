import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import "../Config.js" as Config

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

    spacing: 4

    // Every connected screen, left-to-right by x - ties (side-by-side
    // monitors stacked vertically instead) broken by whichever is
    // closest to y = 0, so a monitor placed above the reference point
    // sorts before one placed further below it. Only used below to
    // rank which monitor each workspace belongs to.
    readonly property var sortedMonitors: Quickshell.screens.slice().sort((a, b) => {
        if (a.x !== b.x) return a.x - b.x
        return Math.abs(a.y) - Math.abs(b.y)
    })

    // showEmptyWidget (Screen Settings' "Show Empty: Widget" toggle) -
    // any workspace 1-5 pinned to a monitor (monitors.json) but not
    // existing in Hyprland yet (nobody's switched to it this session,
    // so Hyprland hasn't created it) gets synthesized as a placeholder
    // here, matching just enough of a real HyprlandWorkspace's shape
    // for wsBox/winBox below to render an empty box for it: .monitor
    // (a real HyprlandMonitor, for aspect ratio/geometry), .active
    // (always false - it can't be the active workspace if it doesn't
    // exist), .hasFullscreen (always false), .toplevels.values (empty -
    // nothing to draw in the window grid), and .activate() (dispatches
    // straight to Hyprland, same as a real workspace's own method,
    // since clicking one of these should actually create/switch to it).
    readonly property bool showEmptyWidget: !!root.screensStore.__showEmptyWidget

    // existingIds: every workspace id currently real in Hyprland,
    // computed once in sortedWorkspaces below and passed in here rather
    // than re-derived per-monitor - workspace ids are globally unique
    // (never two monitors sharing one), so checking existence against a
    // single flat set is both simpler and immune to a real workspace's
    // own .monitor being momentarily null right as it's created (see
    // sortedWorkspaces' dedup comment below) - keying existence off
    // per-monitor buckets used to let a placeholder for the same id
    // sneak in right alongside that real, momentarily-monitor-less
    // object, showing as a spurious extra box for the ~20ms it took
    // Hyprland to finish assigning the new workspace to its monitor.
    function placeholderWorkspaces(existingIds) {
        if (!root.showEmptyWidget) return []

        const placeholders = []
        for (const monName in root.screensStore) {
            if (monName.startsWith("__")) continue
            const stored = root.screensStore[monName]
            if (!stored || !stored.workspaces) continue

            const mon = Hyprland.monitors.values.find(m => m.name === monName)
            if (!mon) continue

            for (const num of stored.workspaces) {
                if (existingIds.has(num)) continue
                placeholders.push({
                    id: num,
                    monitor: mon,
                    active: false,
                    hasFullscreen: false,
                    toplevels: { values: [] },
                    // A plain "workspace N" dispatch only reliably lands
                    // on the pinned monitor if Hyprland still has its
                    // workspace_rule (from the last Apply) in effect for
                    // this id - focusmonitor first makes this correct
                    // regardless, rather than silently creating/
                    // switching to workspace N on whatever monitor
                    // happens to be focused right now instead of the one
                    // this box is actually sitting under.
                    activate: () => {
                        Hyprland.dispatch("focusmonitor " + monName)
                        Hyprland.dispatch("workspace " + num)
                    }
                })
            }
        }
        return placeholders
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
        // monitor - this (plus existingIds below) is what let an
        // extra/duplicate box flash for ~20ms during a workspace swap.
        const byId = new Map()
        for (const w of Hyprland.workspaces.values) {
            const prev = byId.get(w.id)
            if (!prev || (!prev.monitor && w.monitor)) byId.set(w.id, w)
        }

        // strictWorkspaceWidget (Screen Settings' toggle, above Identify)
        // drops any workspace not actually pinned to its monitor
        // (isPinned() below, straight off monitors.json's per-monitor
        // "workspaces" list) when on. Used to be a hardcoded `id <= 5`
        // cutoff - a leftover from when anything past 5 was, by
        // definition, an ephemeral auto-assigned spare. That's no longer
        // true (resolveWorkspaceAssignment() in ScreenSettings.qml can
        // now hand a monitor a real, fully-managed spare workspace above
        // 5 once 1-5 are all claimed elsewhere), and the cutoff was
        // never actually checking "is this managed" in the first place -
        // a genuinely stray/unmanaged workspace with an id <= 5 (created
        // by hand, or left over from before a reassignment) slipped
        // straight through it untouched, which is what read live as
        // "only managed workspaces" not actually hiding an unmanaged one.
        let workspaces = Array.from(byId.values())
        if (root.strictWorkspaceWidget) {
            workspaces = workspaces.filter(w => root.isPinned(w))
        }

        workspaces = workspaces.concat(root.placeholderWorkspaces(new Set(byId.keys())))
        return workspaces.sort((a, b) => {
            const rankA = (a.monitor && monitorRank[a.monitor.name] !== undefined) ? monitorRank[a.monitor.name] : 999
            const rankB = (b.monitor && monitorRank[b.monitor.name] !== undefined) ? monitorRank[b.monitor.name] : 999
            if (rankA !== rankB) return rankA - rankB
            return a.id - b.id
        })
    }

    // sortedWorkspaces with a "separator" marker spliced in wherever the
    // owning monitor changes between one entry and the next, so the Row
    // below can draw a small divider between each monitor's group of
    // workspace boxes instead of one continuous, ungrouped run of them.
    //
    // This is the "live" computation - re-evaluates the instant any
    // dependency changes (Hyprland.workspaces, screensStore, etc).
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
    //
    // Also re-polls monitors.json here rather than waiting for the
    // Timer's own 4s interval - Screen Settings' Apply always fires at
    // least one Hyprland event of its own (a monitor/workspace dispatch,
    // see ScreenSettings.qml), so this piggybacks on that instead of
    // needing its own cross-component signal. Numbers/icons on other
    // monitors' workspaces sometimes not rendering right after a fresh
    // config or enabling/disabling a monitor was this same lag - a real
    // monitor.json write just hadn't been picked up by this poll yet.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            Hyprland.refreshToplevels()
            root.loadScreensStore()
            renderSettleTimer.restart()
        }
    }
    Component.onCompleted: {
        Hyprland.refreshToplevels()
        root.loadScreensStore()
        // Seed the very first render immediately - no reason to wait out
        // a settle delay before anything has been drawn at all.
        root.settledEntries = root.rowEntries
    }

    // Which workspace numbers (1-5) are actually pinned to each
    // monitor via Screen Settings - read straight from the same
    // monitors.json ScreenSettings.qml writes, rather than depending on
    // that panel being open/instantiated, so the number label below can
    // tell "a real pin" apart from whatever spare workspace number
    // Hyprland happened to assign a monitor with nothing pinned to it.
    property var screensStore: ({})

    function loadScreensStore() {
        screensStoreProcess.running = false
        screensStoreProcess.running = true
    }

    function isPinned(workspace) {
        if (!workspace.monitor) return false
        const stored = root.screensStore[workspace.monitor.name]
        return !!(stored && stored.workspaces && stored.workspaces.includes(workspace.id))
    }

    // Global toggle from the same file, stored under a non-monitor-name
    // key (see ScreenSettings.qml's toggleStrictWorkspaceWidget) - reuses
    // the polling already happening for isPinned() above rather than
    // needing its own separate read.
    readonly property bool strictWorkspaceWidget: !!root.screensStore.__strictWorkspaceWidget

    Process {
        id: screensStoreProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/monitors.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.screensStore = JSON.parse(text)
                } catch (e) {
                    root.screensStore = {}
                }
            }
        }
    }

    // Nothing pushes a change notification when monitors.json is
    // rewritten (only ScreenSettings.qml's own Apply button touches
    // it), so this just polls - same interval Network Settings uses
    // for its own ZeroTier/nmcli refresh.
    Timer {
        interval: 4000
        repeat: true
        running: true
        onTriggered: root.loadScreensStore()
    }

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

        Rectangle {
            width: 2
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

            height: root.height
            width: wsBox.height * wsBox.aspect
            color: Config.fillcolor
            border.width: 2
            // hasFullscreen bumps the border up a tier from whatever
            // it'd otherwise be - fgcolor becomes fgcolorlight when
            // active, fgcolordark becomes fgcolordarklight when not -
            // so a workspace holding a fullscreen app always reads as
            // more prominent than one that doesn't, active or not.
            border.color: wsBox.modelData.hasFullscreen
                ? (wsBox.modelData.active ? Config.fgcolorlight : Config.fgcolordarklight)
                : (wsBox.modelData.active ? Config.fgcolor : Config.fgcolordark)
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

                    // Real per-app icon, the same way Tray.qml gets one
                    // - its Image binds straight to SystemTray's own
                    // already-resolved .icon rather than guessing an
                    // icon-theme name. There's no such direct icon on a
                    // Hyprland toplevel, but DesktopEntries.
                    // heuristicLookup() matches this window's WM class
                    // to its installed .desktop file and returns that
                    // entry's real icon name, which resolves correctly
                    // far more often than assuming the icon theme has
                    // an entry literally named after the raw class
                    // string (the fallback below, for whatever
                    // heuristicLookup can't match).
                    //
                    // heuristicLookup() itself only ever tries an exact
                    // desktop-file-id match or an exact (case-
                    // insensitive) StartupWMClass match (confirmed
                    // against Quickshell's own source) - it has no
                    // substring/fuzzy matching at all. Flatpak apps
                    // commonly report a short runtime class ("waterfox")
                    // that matches neither their reverse-DNS desktop
                    // file id nor StartupWMClass ("net.waterfox.
                    // waterfox"), so heuristicLookup comes back empty
                    // and this fell all the way through to the generic
                    // fallback icon. Falls back here to a substring
                    // search over every installed .desktop entry's own
                    // id for one that contains this window's class, so
                    // Waterfox (and anything else shaped the same way)
                    // still resolves to its real icon.
                    function substringLookup(cls) {
                        const lower = cls.toLowerCase()
                        const apps = DesktopEntries.applications.values
                        for (const app of apps) {
                            if (app.id.toLowerCase().includes(lower)) return app
                        }
                        return null
                    }

                    readonly property var desktopEntry: winBox.winClass.length > 0
                        ? (DesktopEntries.heuristicLookup(winBox.winClass) ?? winBox.substringLookup(winBox.winClass))
                        : null
                    readonly property string iconName: (winBox.desktopEntry && winBox.desktopEntry.icon.length > 0)
                        ? winBox.desktopEntry.icon
                        : winBox.winClass

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

                    visible: !wsBox.modelData.hasFullscreen || winBox.isFullscreen

                    color: "transparent"
                    border.width: 1
                    // Only lit up fgcolor when BOTH this window is the
                    // focused one ("activated") AND its workspace is the
                    // currently active one on its monitor - a focused
                    // window sitting on a workspace you've since
                    // switched away from should still read as dimmed,
                    // not call attention to itself.
                    border.color: (wsBox.modelData.active && winBox.modelData.activated)
                        ? Config.fgcolor
                        : Config.fgcolordark

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.max(4, Math.min(winBox.width, winBox.height) * 0.6)
                        // The plain single-arg iconPath() renders "a
                        // missing texture" image when the name doesn't
                        // resolve in the current icon theme (documented
                        // behavior, not a bug) rather than failing
                        // quietly - the two-arg fallback form loads a
                        // generic icon instead whenever the specific
                        // app/class name isn't a real theme icon, same
                        // fallback pattern BluetoothDeviceCard.qml uses.
                        source: winBox.iconName.length > 0
                            ? Quickshell.iconPath(winBox.iconName, "application-x-executable")
                            : Quickshell.iconPath("application-x-executable")
                    }
                }
            }

            // Faint workspace number, drawn above the window grid (z
            // higher than the Repeater's default stacking) so it stays
            // legible regardless of how many window/icon rectangles are
            // packed underneath it. Hidden entirely - not just dimmed -
            // for a workspace that was never actually pinned to this
            // monitor through Screen Settings (see isPinned()/
            // screensStore above) - the box and its window grid still
            // show either way, just without a number that would
            // otherwise look like a deliberate pin. No numeric cutoff
            // any more - a monitor's auto-assigned spare (see
            // resolveWorkspaceAssignment() in ScreenSettings.qml) is a
            // real, fully-managed workspace now even past id 5, so it
            // gets a number too as long as isPinned() confirms it.
            Text {
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    rightMargin: 4
                }
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignBottom
                z: 10
                visible: root.isPinned(wsBox.modelData)
                text: String(wsBox.modelData.id)
                color: Config.fgcolor
                opacity: 0.75
                // Outline so the number stays legible over whatever's
                // underneath it (light window rectangles/icons, not
                // just the box's own dark fill).
                style: Text.Outline
                styleColor: "black"
                font.family: Config.fontfamily
                font.bold: true
                font.pixelSize: Math.max(8, Math.min(wsBox.width, wsBox.height) * 0.55)
            }

            // Switches to this workspace - Hyprland's own activate(),
            // equivalent to HyprlandIpc.dispatch("workspace <name>").
            // Covers the whole box (window-grid rectangles/icons and
            // the number label underneath have no MouseAreas of their
            // own to compete with).
            MouseArea {
                anchors.fill: parent
                onClicked: wsBox.modelData.activate()
            }
        }
    }
}

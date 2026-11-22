import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../../Config.js" as Config
import "../common"
import "../common/WorkspaceRegistryLogic.js" as RegistryLogic
import "../common/HyprlandWindows.js" as HyprlandWindows

// Small "you just switched workspace" indicator, one per screen, shown
// briefly whenever that screen's active workspace changes - e.g. the
// SUPER+1..5 focus keybinds in hyprland.lua - on a screen with more than
// one workspace, every one of them in the row. Not shown for a window
// being moved to another workspace without following it
// (SUPER+CTRL+1..5, "follow = false"), since that never changes which
// workspace is active.
//
// Visually borrows DialogCard's translucent-black/purple-border look
// (not the component itself - DialogCard's ShaderEffectSource blur is
// overkill here, nothing needs to be obscured, and reusing it risked
// the same recursive-source-item crash root-caused for Network
// settings' old PSK prompt) and is genuinely click-through
// (mask: Region {}, no MouseArea anywhere) since it's purely
// informational and should never steal input from whatever's under it.
Scope {
    id: root

    // Settings > General's global UI Scale (UiScale.qml), from shell.qml -
    // multiplied into every window's Config.uiScale below.
    property real shellScale: 1.0

    // purpura.lua's book of the workspaces (WorkspaceRegistry.qml): which are
    // pinned to which monitor, and each one's purpura number. Read once here and
    // shared by every screen's own window below.
    WorkspaceRegistry {
        id: registry
        onBookChanged: renderSettleTimer.restart()
    }

    // General > Shell settings (ShellSettings.qml) - a separate file from
    // monitors.json, watched the same way, since the "Show empty
    // workspaces: In OSD" toggle is a simple immediately-saved setting
    // rather than staged/Apply-dependent monitor state.
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

    // Settings > General > Shell > Workspace OSD's size: 50 - 120%, 100%
    // unless set. Borders, and where it sits, don't change with it - it
    // grows upward from the same place.
    readonly property real osdSize: {
        const n = Number(root.barSettingsStore.workspaceOsdSize)
        return isFinite(n) && n > 0 ? Math.max(0.5, Math.min(1.2, n)) : 1
    }

    // A moment's look at it after the size changes, so the setting shows
    // what it does - on every monitor with workspaces to show. Not while
    // the shell's starting, when the size changes from the default to
    // what's saved as the file is read.
    property bool previewing: false
    property bool settled: false

    onOsdSizeChanged: {
        if (!root.settled) return
        root.previewing = true
        previewTimer.restart()
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: root.settled = true
    }

    Timer {
        id: previewTimer

        interval: 2000
        onTriggered: root.previewing = false
    }

    // A single Apply dispatches many sequential hyprctl eval calls (see
    // ScreenSettings.qml), each firing a live Hyprland raw event the
    // instant it lands - without coalescing, each osdWindow's
    // monitorWorkspaces below (a live reactive binding) would recompute
    // and render every one of those intermediate, mid-transition states
    // for a frame, which is what read live as boxes jittering or a
    // workspace appearing to blink in and back out during a workspace/
    // display swap. settleTick increments once the burst of raw events
    // from one Apply actually stops (or the book itself changes, see
    // above), and each osdWindow only copies its live computation into
    // what it actually renders when settleTick changes - see
    // monitorWorkspaces/liveMonitorWorkspaces below.
    property int settleTick: 0

    // Settings > General > Shell > Workspace OSD's "Show Workspace OSD on
    // switch": on unless turned off. Off, a switch shows nothing - a
    // fullscreen app given a workspace of its own still does (below).
    readonly property bool showOnSwitch: root.barSettingsStore.showWorkspaceOsdOnSwitch !== false

    // purpura.lua's "purpura-workspace,fullscreen,<monitor>,<workspace>": a
    // fullscreen app that opened has been sent to a workspace of its own
    // there (with Create Workspace For Fullscreen Apps on). That monitor's
    // OSD shows it, that workspace in the row - dashed, even should it be the
    // monitor's only one - whether switches show it or not.
    signal fullscreenMoved(string monitor, int workspace)

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Not purpura.lua's drag events (see Bar.qml's).
            if (event.name === "custom") {
                const parts = String(event.data).split(",")
                if (parts.length === 4 && parts[0] === "purpura-workspace" && parts[1] === "fullscreen"
                        && /^[A-Za-z0-9_.-]{1,64}$/.test(parts[2]) && /^\d{1,6}$/.test(parts[3])) {
                    root.fullscreenMoved(parts[2], parseInt(parts[3], 10))
                    // The row's looked at again once it's settled, that one in it.
                    renderSettleTimer.restart()
                } else if (parts.length === 3 && parts[0] === "purpura-workspace" && parts[1] === "shown") {
                    // purpura.lua's "purpura-workspace,shown,<monitor>": META + Tab
                    // or META + CTRL + Tab switched the monitor under the cursor
                    // while another had the focus - which Hyprland says nothing
                    // of, so every monitor's workspace (this OSD's, the bar's) is
                    // asked for again. Done here, once for the whole shell.
                    Hyprland.refreshMonitors()
                    renderSettleTimer.restart()
                }
                return
            }
            renderSettleTimer.restart()
        }
    }

    Timer {
        id: renderSettleTimer
        interval: 120
        repeat: false
        onTriggered: root.settleTick++
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow

            property var modelData
            screen: modelData

            // The shell-wide per-screen scale (see Config.uiScale), so
            // box/text/border sizes track this screen's own resolution
            // instead of assuming a fixed one - and on top of it, for the
            // boxes and text, the Workspace OSD size. Borders and the
            // position go by baseScale alone.
            readonly property real baseScale: Config.uiScale(modelData, root.shellScale)
            readonly property real uiScale: osdWindow.baseScale * root.osdSize

            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)

            readonly property bool showEmptyOsd: !!root.barSettingsStore.showEmptyOsd

            // This monitor's workspaces in the row (WorkspaceRegistryLogic.js's
            // osdWorkspaces), as they are this moment: once it has more than
            // one, every one - the ones Display settings pinned to it, an app's
            // own, a new one, one with a window fullscreen - in purpura's number
            // order, with an empty one not on screen only with showEmptyOsd
            // (pins are kept by Hyprland, there or not). With just the one,
            // none, so nothing shows. And the workspace a fullscreen app has
            // just been given here (see root.fullscreenMoved), while the OSD's
            // up for it, either way.
            //
            // A workspace Hyprland's only just made has no monitor yet - not
            // until Quickshell's asked for the list again, a moment after it
            // shows - so the one this monitor's showing counts as its own
            // here, as does the one purpura.lua's said a fullscreen app's
            // been given here.
            function workspacesNow() {
                if (!osdWindow.hyprMonitor) return []
                const name = osdWindow.hyprMonitor.name
                const active = osdWindow.hyprMonitor.activeWorkspace
                const activeId = active ? active.id : -1
                const records = Hyprland.workspaces.values.map(w => {
                    const showing = w.id >= 1 && w.id === activeId
                    const ours = showing || (w.id >= 1 && w.id === osdWindow.signalledId)
                    return {
                        id: w.id,
                        monitor: w.monitor ? w.monitor.name : (ours ? name : ""),
                        empty: HyprlandWindows.on(Hyprland.toplevels.values, w).length === 0,
                        shown: showing || (!!w.monitor && !!w.monitor.activeWorkspace && w.monitor.activeWorkspace.id === w.id),
                        persistent: !!w.lastIpcObject && w.lastIpcObject.ispersistent === true,
                        ws: w
                    }
                })
                return RegistryLogic.osdWorkspaces(registry.book, records, name, {
                    showEmpty: osdWindow.showEmptyOsd,
                    signalled: osdWindow.signalledId
                }).map(r => r.ws)
            }

            // The "live" computation - see monitorWorkspaces below for what
            // the Repeater actually renders.
            readonly property var liveMonitorWorkspaces: osdWindow.workspacesNow()

            // What the Repeater below actually renders - a debounced
            // snapshot of liveMonitorWorkspaces, copied over only when
            // root.settleTick changes (see its own declaration above),
            // not a plain reactive binding - otherwise every intermediate
            // state Hyprland passes through mid-Apply would flash on
            // screen as its own frame.
            property var monitorWorkspaces: []

            Connections {
                target: root
                function onSettleTickChanged() {
                    osdWindow.monitorWorkspaces = osdWindow.liveMonitorWorkspaces
                }
            }

            Component.onCompleted: {
                // Seed the very first render immediately - no reason to
                // wait out a settle delay before anything has been drawn
                // at all.
                osdWindow.monitorWorkspaces = osdWindow.liveMonitorWorkspaces
            }

            readonly property int activeId: (osdWindow.hyprMonitor && osdWindow.hyprMonitor.activeWorkspace)
                ? osdWindow.hyprMonitor.activeWorkspace.id
                : -1
            readonly property int activeIndex: osdWindow.monitorWorkspaces.findIndex(w => w.id === osdWindow.activeId)

            // How a window on that workspace is fullscreen, as the bar's
            // workspace widget draws it: 2 - one in real fullscreen, the whole
            // monitor (Hyprland's mode 2), or the workspace a fullscreen app's
            // just been given here (signalledId), whether or not that's caught
            // up here yet - a dashed border; 1 - one maximized - a solid one;
            // both in the fullscreen color. 0 - neither.
            function fullscreenOf(ws) {
                if (!ws) return 0
                if (ws.id === osdWindow.signalledId && !registry.isManaged(ws)) return 2
                if (!ws.hasFullscreen) return 0
                return HyprlandWindows.on(Hyprland.toplevels.values, ws)
                    .some(t => !!t.lastIpcObject && t.lastIpcObject.fullscreen === 2) ? 2 : 1
            }

            // The active one's, for the highlight round it (activeHighlight).
            readonly property int activeFullscreen: osdWindow.activeIndex >= 0
                ? osdWindow.fullscreenOf(osdWindow.monitorWorkspaces[osdWindow.activeIndex])
                : 0

            // Stays true through the ~250ms slide even after hideTimer
            // fires visually (only actually hides once reallyVisible
            // flips), matching the reallyVisible/closing-animation
            // convention used by SettingsPanel.qml/DialogCard.qml -
            // otherwise the window (and the animation running inside it)
            // would vanish mid-slide instead of finishing it.
            property bool reallyVisible: false

            // The workspace a fullscreen app's just been given on this
            // monitor - shown, and kept in the row, a little longer than a
            // switch is; -1 the rest of the time.
            property int signalledId: -1

            Connections {
                target: root
                function onFullscreenMoved(monitor, workspace) {
                    if (!osdWindow.hyprMonitor || monitor !== osdWindow.hyprMonitor.name) return
                    osdWindow.signalledId = workspace
                    // Coming up: drawn from what's there now (see onActiveIdChanged).
                    const now = osdWindow.workspacesNow()
                    if (!osdWindow.reallyVisible && now.length > 0) osdWindow.monitorWorkspaces = now
                    osdWindow.reallyVisible = true
                    hideTimer.interval = 2500
                    hideTimer.restart()
                }
            }

            onActiveIdChanged: {
                // Only the very first evaluation (component just created,
                // nothing has actually changed yet) has no prior value to
                // slide *from* - skip showing then, only on real switches.
                if (!osdWindow.hyprMonitor || osdWindow.activeId < 0) return
                // "Show Workspace OSD on switch" off: nothing (a fullscreen
                // app's own workspace still shows it - see above).
                if (!root.showOnSwitch) return
                // This monitor can have nothing to show - just the one
                // workspace, or nothing at all - and popping up an empty
                // box row would just be a floating border for no reason,
                // so skip entirely rather than show it. Checked against
                // the workspaces as they are this moment (workspacesNow(),
                // worked out afresh rather than read off the
                // liveMonitorWorkspaces binding, which may not have caught
                // up with this same change yet), NOT the debounced
                // monitorWorkspaces the Repeater actually renders -
                // activeId changes the instant Hyprland's own event
                // fires, while monitorWorkspaces only catches up once
                // renderSettleTimer's ~120ms window elapses. Using the
                // debounced value here raced the two: switching every
                // workspace off a monitor (e.g. reassigning them all to
                // a different monitor via Screen Settings) could still
                // read the *stale*, pre-Apply monitorWorkspaces at the
                // exact moment activeId flipped to the new (genuinely
                // empty) state, popping up an OSD that then rendered
                // nothing once monitorWorkspaces actually caught up -
                // reported live as an empty bordered box appearing on a
                // monitor with no managed workspaces left.
                const now = osdWindow.workspacesNow()
                if (now.length === 0) return
                // Coming up (not already showing, so nothing on screen to
                // jump): drawn from those, rather than the last settled
                // list, which is from before this switch - without a
                // workspace Hyprland's just made for it, or empty, the
                // monitor having had just the one until now.
                if (!osdWindow.reallyVisible) osdWindow.monitorWorkspaces = now
                osdWindow.reallyVisible = true
                if (osdWindow.signalledId < 0) hideTimer.interval = 1200
                hideTimer.restart()
            }

            // Safety net for the same race from the other direction: if
            // the debounced list settles to empty while already showing
            // (rather than exactly at the activeId-changed instant above),
            // hide immediately rather than leave an empty box lingering
            // for the rest of hideTimer's interval.
            onMonitorWorkspacesChanged: {
                if (osdWindow.monitorWorkspaces.length === 0) osdWindow.reallyVisible = false
            }

            Timer {
                id: hideTimer
                interval: 1200
                onTriggered: {
                    osdWindow.reallyVisible = false
                    osdWindow.signalledId = -1
                    hideTimer.interval = 1200
                }
            }

            visible: osdWindow.reallyVisible || (root.previewing && osdWindow.monitorWorkspaces.length > 0)

            WlrLayershell.namespace: "workspace-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // No top/left/right anchors - only bottom is anchored, with a
            // margin smaller than VolumeOsd's (screen.height / 8, implicitHeight
            // 84) so this sits just above it instead of the two overlapping
            // in the middle of the screen. Horizontally this still centers
            // itself the same way VolumeOsd does (no left/right anchors set).
            anchors.bottom: true
            margins.bottom: modelData.height / 8 + Config.scaled(84 + 20, osdWindow.baseScale)
            exclusiveZone: 0
            color: "transparent"

            // Fully click-through - purely informational, never wants
            // mouse input, unlike VolumeOsd's slider/mute button.
            mask: Region {}

            // Larger than the original pass, and each box's width now
            // tracks this screen's own aspect ratio (modelData.width /
            // modelData.height) instead of being a fixed square - a
            // 16:9 monitor gets wide boxes, a 16:10 or portrait one gets
            // narrower ones, so the OSD visually reads as "a row of tiny
            // monitors" rather than arbitrary numbered tiles.
            readonly property real boxPadding: Config.scaled(20, osdWindow.uiScale)
            readonly property real boxHeight: Config.scaled(64, osdWindow.uiScale)
            readonly property real boxWidth: osdWindow.boxHeight * (modelData.width / modelData.height)
            readonly property real boxSpacing: Config.scaled(12, osdWindow.uiScale)

            implicitWidth: contentRow.implicitWidth + osdWindow.boxPadding * 2
            implicitHeight: osdWindow.boxHeight + osdWindow.boxPadding * 2

            Rectangle {
                anchors.fill: parent
                color: Config.fillcolor
                border.width: Config.scaled(2, osdWindow.baseScale)
                border.color: Config.fgcolor
                radius: 0

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: osdWindow.boxSpacing

                    Repeater {
                        model: osdWindow.monitorWorkspaces

                        Rectangle {
                            id: osdBox
                            required property var modelData

                            // A window on it fullscreen (fullscreenOf): its border
                            // in the fullscreen color, as the workspace widget
                            // draws it - dashed for real fullscreen (the one a
                            // fullscreen app's just been given too), solid for
                            // one maximized.
                            readonly property int fullscreen: osdWindow.fullscreenOf(osdBox.modelData)

                            width: osdWindow.boxWidth
                            height: osdWindow.boxHeight
                            color: Config.fillcolor
                            border.width: osdBox.fullscreen === 2 ? 0 : Config.scaled(2, osdWindow.baseScale)
                            border.color: osdBox.fullscreen > 0 ? Config.fgcolorfullscreen : Config.fgcolor
                            radius: 0

                            DashedBorder {
                                visible: osdBox.fullscreen === 2
                                color: Config.fgcolorfullscreen
                                thickness: Config.scaled(2, osdWindow.baseScale)
                                dash: Config.scaled(8, osdWindow.uiScale)
                                gap: Config.scaled(5, osdWindow.uiScale)
                            }

                            // purpura's number for it - a managed one's only: an
                            // unmanaged one (an app's own, a new one, a spare)
                            // shows none.
                            Text {
                                anchors.centerIn: parent
                                visible: registry.isManaged(osdBox.modelData) && registry.numberOf(osdBox.modelData) >= 1
                                text: String(registry.numberOf(osdBox.modelData))
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(32, osdWindow.uiScale)
                                font.bold: true
                            }
                        }
                    }
                }

                // Sliding highlight around whichever box is the active
                // workspace - a sibling overlay rather than something
                // drawn per-box, so it can animate its position instead
                // of just snapping between boxes. z above the per-box
                // Repeater so this border draws over each box's own
                // border rather than under/behind it. Round one with a
                // window fullscreen (activeFullscreen) it's that box's
                // fullscreen color, lightened as fgcolorlight is fgcolor -
                // and dashed like it for real fullscreen, its dashes laid
                // over the box's own (the same size, dash and gap, so the
                // same places), not a solid line drawn over them.
                Rectangle {
                    id: activeHighlight

                    readonly property color tone: osdWindow.activeFullscreen > 0
                        ? Qt.lighter(Config.fgcolorfullscreen, 1.55)
                        : Config.fgcolorlight

                    z: 1
                    y: contentRow.y
                    width: osdWindow.boxWidth
                    height: osdWindow.boxHeight
                    color: "transparent"
                    border.width: osdWindow.activeFullscreen === 2 ? 0 : Config.scaled(3, osdWindow.baseScale)
                    border.color: activeHighlight.tone
                    radius: 0
                    visible: osdWindow.activeIndex >= 0

                    x: contentRow.x + (osdWindow.activeIndex >= 0
                        ? osdWindow.activeIndex * (osdWindow.boxWidth + osdWindow.boxSpacing)
                        : 0)

                    Behavior on x {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    DashedBorder {
                        visible: osdWindow.activeFullscreen === 2
                        color: activeHighlight.tone
                        thickness: Config.scaled(3, osdWindow.baseScale)
                        dash: Config.scaled(8, osdWindow.uiScale)
                        gap: Config.scaled(5, osdWindow.uiScale)
                    }
                }
            }
        }
    }
}

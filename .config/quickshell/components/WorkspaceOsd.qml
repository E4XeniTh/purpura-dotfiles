import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../Config.js" as Config

// Small "you just switched workspace" indicator, one per screen, shown
// briefly whenever that screen's active workspace changes - e.g. the
// SUPER+1..5 focus keybinds in hyprland.lua. Not shown for a window
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

    // Read once here (rather than per-screen inside osdWindow below) and
    // shared by every screen's own instance - same monitors.json
    // ScreenSettings.qml writes, holding both per-monitor pinned
    // workspaces and the "__showEmptyOsd" global toggle (see
    // ScreenSettings.qml's toggleShowEmptyOsd()).
    property var screensStore: ({})

    function loadScreensStore() {
        screensStoreProcess.running = false
        screensStoreProcess.running = true
    }

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

    Component.onCompleted: root.loadScreensStore()

    // Nothing pushes a change notification when monitors.json is
    // rewritten (only ScreenSettings.qml's own Apply/toggle calls touch
    // it) - polls instead, same interval used elsewhere for this file.
    Timer {
        interval: 4000
        repeat: true
        running: true
        onTriggered: root.loadScreensStore()
    }

    // A single Apply dispatches many sequential hyprctl eval calls (see
    // ScreenSettings.qml), each firing a live Hyprland raw event the
    // instant it lands - without coalescing, each osdWindow's
    // monitorWorkspaces below (a live reactive binding) would recompute
    // and render every one of those intermediate, mid-transition states
    // for a frame, which is what read live as boxes jittering or a
    // workspace appearing to blink in and back out during a workspace/
    // display swap. settleTick increments once the burst of raw events
    // from one Apply actually stops, and each osdWindow only copies its
    // live computation into what it actually renders when settleTick
    // changes - see monitorWorkspaces/liveMonitorWorkspaces below.
    property int settleTick: 0

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.loadScreensStore()
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

            // Same reference-resolution scaling formula as Dashboard.qml's
            // dashWindow, so box/text/border sizes track this screen's own
            // resolution instead of assuming a fixed one.
            readonly property real uiScale: Math.max(0.6, Math.min(1.8, modelData.width * 0.42 / 800))

            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)

            readonly property bool showEmptyOsd: !!root.screensStore.__showEmptyOsd

            // Every workspace number actually, deliberately pinned to
            // *this* monitor per monitors.json (i.e. chosen via the 1-5
            // buttons in Screen Settings) - straight off screensStore,
            // used both to filter the real Hyprland.workspaces list below
            // and to build showEmptyOsd's placeholders. Explicitly capped
            // at id <= 5: resolveWorkspaceAssignment() in
            // ScreenSettings.qml never lets anything past 5 be anything
            // other than an auto-assigned filler for a monitor nothing
            // was explicitly chosen for, and this OSD is meant to show
            // deliberate pins, not "whatever number this monitor happens
            // to be functioning on" - a monitor with nothing chosen
            // showing its filler workspace here would just be visual
            // noise nobody asked for. isPinned membership is still
            // checked separately from the id cutoff (not "any id <= 5
            // this monitor happens to be showing") so a genuinely stray/
            // misattributed workspace with an id <= 5 doesn't slip
            // through either - dropping either check broke this one way
            // or the other, reported live as the OSD always showing a
            // monitor's auto-filled spare even with nothing pinned.
            readonly property var pinnedNumbers: {
                if (!osdWindow.hyprMonitor) return []
                const stored = root.screensStore[osdWindow.hyprMonitor.name]
                const workspaces = (stored && stored.workspaces) ? stored.workspaces : []
                return workspaces.filter(num => num <= 5)
            }

            // Every workspace currently assigned to *this* monitor, sorted
            // by id - re-evaluates live off Hyprland.workspaces (an
            // ObjectModel, same reactive-list pattern as
            // Networking.devices/Pipewire.nodes elsewhere in this shell),
            // filtered down to only those actually pinned (see
            // pinnedNumbers above).
            //
            // When showEmptyOsd is on, any pinned number not existing in
            // Hyprland yet (nobody's switched to it this session) is
            // added as a bare placeholder ({ id }) - the delegate below
            // only ever reads .id off each entry, so nothing more is
            // needed. It'll never match activeId (a real workspace has to
            // be switched to for that), so the sliding highlight simply
            // never lands on one.
            //
            // This is the "live" computation - see monitorWorkspaces
            // below for what the Repeater actually renders.
            readonly property var liveMonitorWorkspaces: {
                if (!osdWindow.hyprMonitor) return []
                let list = Hyprland.workspaces.values
                    .filter(w => w.monitor === osdWindow.hyprMonitor && osdWindow.pinnedNumbers.includes(w.id))

                if (osdWindow.showEmptyOsd) {
                    const existing = new Set(list.map(w => w.id))
                    for (const num of osdWindow.pinnedNumbers) {
                        if (existing.has(num)) continue
                        list = list.concat([{ id: num }])
                    }
                }

                return list.slice().sort((a, b) => a.id - b.id)
            }

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

            // Stays true through the ~250ms slide even after hideTimer
            // fires visually (only actually hides once reallyVisible
            // flips), matching the reallyVisible/closing-animation
            // convention used by SettingsPanel.qml/DialogCard.qml -
            // otherwise the window (and the animation running inside it)
            // would vanish mid-slide instead of finishing it.
            property bool reallyVisible: false

            onActiveIdChanged: {
                // Only the very first evaluation (component just created,
                // nothing has actually changed yet) has no prior value to
                // slide *from* - skip showing then, only on real switches.
                if (!osdWindow.hyprMonitor || osdWindow.activeId < 0) return
                // monitorWorkspaces' pinnedNumbers filter can leave this
                // monitor with nothing at all to show (e.g. nothing
                // pinned to it yet and showEmptyOsd is off) - popping up
                // an empty box row would just be a floating border for no
                // reason, so skip entirely rather than show it.
                if (osdWindow.monitorWorkspaces.length === 0) return
                osdWindow.reallyVisible = true
                hideTimer.restart()
            }

            Timer {
                id: hideTimer
                interval: 1200
                onTriggered: osdWindow.reallyVisible = false
            }

            visible: osdWindow.reallyVisible

            WlrLayershell.namespace: "workspace-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // No top/left/right anchors - only bottom is anchored, with a
            // margin smaller than VolumeOsd's (screen.height / 8, implicitHeight
            // 84) so this sits just above it instead of the two overlapping
            // in the middle of the screen. Horizontally this still centers
            // itself the same way VolumeOsd does (no left/right anchors set).
            anchors.bottom: true
            margins.bottom: modelData.height / 8 + 84 + osdWindow.boxPadding
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
                border.width: 2
                border.color: Config.fgcolor
                radius: 0

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: osdWindow.boxSpacing

                    Repeater {
                        model: osdWindow.monitorWorkspaces

                        Rectangle {
                            required property var modelData

                            width: osdWindow.boxWidth
                            height: osdWindow.boxHeight
                            color: Config.fillcolor
                            border.width: 2
                            border.color: Config.fgcolor
                            radius: 0

                            Text {
                                anchors.centerIn: parent
                                text: String(parent.modelData.id)
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
                // border rather than under/behind it.
                Rectangle {
                    id: activeHighlight

                    z: 1
                    y: contentRow.y
                    width: osdWindow.boxWidth
                    height: osdWindow.boxHeight
                    color: "transparent"
                    border.width: Config.scaled(3, osdWindow.uiScale)
                    border.color: Config.fgcolorlight
                    radius: 0
                    visible: osdWindow.activeIndex >= 0

                    x: contentRow.x + (osdWindow.activeIndex >= 0
                        ? osdWindow.activeIndex * (osdWindow.boxWidth + osdWindow.boxSpacing)
                        : 0)

                    Behavior on x {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}

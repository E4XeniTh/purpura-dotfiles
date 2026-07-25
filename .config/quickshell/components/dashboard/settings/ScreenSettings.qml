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
// `hyprctl keyword monitor "..."` - Quickshell's own Quickshell.Hyprland
// module only exposes dispatch() for dispatcher-class commands, not
// keyword, and its monitor list doesn't appear to include disabled
// monitors either, so shelling out to the real binary covers both needs
// with one consistent data source.
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
    // height, refresh, x, y, scale } }. A monitor only appears here once
    // touched - values omitted from the object fall back to `monitors`.
    property var pending: ({})
    readonly property bool dirty: Object.keys(root.pending).length > 0

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

    function refreshMonitors() {
        monitorsProcess.running = false
        monitorsProcess.running = true
    }

    // Builds the exact value that goes after "monitor=" in hyprland's own
    // config syntax - same format hyprctl keyword and monitors.conf both
    // use, so this is shared by applyChanges() below.
    //
    // A monitor hyprctl reported as disabled may have stale/placeholder
    // geometry (0x0, etc.) since nothing was actually driving it - if
    // the user is enabling one without having typed real values in
    // themselves, trusting those numbers outright can hand hyprctl an
    // invalid mode/position it silently rejects, which is the leading
    // suspect for Apply appearing to do nothing. Falls back to
    // Hyprland's own "preferred"/"auto" tokens instead whenever a field
    // wasn't both (a) already active before this Apply and (b) not
    // something the user actually edited.
    function monitorLine(name) {
        const base = root.baseFor(name)
        const eff = root.effectiveFor(name)
        if (!eff.enabled) {
            return `${eff.name},disable`
        }

        const p = root.pending[name] || {}
        const wasActive = base && !base.disabled

        const res = (wasActive || p.width !== undefined || p.height !== undefined)
            ? `${eff.width}x${eff.height}@${eff.refresh}`
            : "preferred"
        const pos = (wasActive || p.x !== undefined || p.y !== undefined)
            ? `${eff.x}x${eff.y}`
            : "auto"
        const scale = eff.scale > 0 ? eff.scale : 1

        return `${eff.name},${res},${pos},${scale}`
    }

    function applyChanges() {
        if (!root.dirty) return

        const lines = []
        for (const m of root.monitors) {
            lines.push(root.monitorLine(m.name))
        }

        const script = lines.map(l => `hyprctl keyword monitor "${l}"`).join(" ; ")
        applyProcess.command = ["sh", "-c", script]
        applyProcess.running = false
        applyProcess.running = true

        monitorsFile.setText(lines.join("\n") + "\n")

        root.pending = ({})
    }

    onActiveChanged: {
        if (root.active) {
            root.pending = ({})
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
                } catch (e) {
                    root.monitors = []
                }
            }
        }
    }

    Process {
        id: applyProcess
        command: ["true"]

        stdout: StdioCollector {
            onStreamFinished: root.refreshMonitors()
        }

        // hyprctl keyword failures (a bad mode/position, etc.) go to
        // stderr and were previously just swallowed - surfaced to
        // Quickshell's own log now so a real failure is actually
        // visible (run `qs` from a terminal to see it) instead of
        // Apply just silently appearing to do nothing.
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ScreenSettings: hyprctl keyword monitor error(s):\n" + text)
                }
            }
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

                        onClicked: root.selectedName = modelData.name
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

                readonly property var selected: root.effectiveFor(root.selectedName)

                Layout.preferredWidth: contentRow.rightWidth
                Layout.alignment: Qt.AlignTop
                spacing: Config.scaled(12, root.uiScale)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(6, root.uiScale)

                    LabeledField {
                        Layout.fillWidth: true
                        uiScale: root.uiScale
                        label: "Width"
                        value: rightColumn.selected ? String(rightColumn.selected.width) : ""
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
                        value: rightColumn.selected ? String(rightColumn.selected.height) : ""
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
                        value: rightColumn.selected ? String(rightColumn.selected.refresh) : ""
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
                        value: rightColumn.selected ? String(rightColumn.selected.x) : ""
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
                        value: rightColumn.selected ? String(rightColumn.selected.y) : ""
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
                        value: rightColumn.selected ? String(rightColumn.selected.scale) : ""
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
                            onClicked: root.applyChanges()
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

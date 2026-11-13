import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Config.js" as Config
import "../common"
import "controls"

// The General tab's settings (as opposed to Sound/Network/Bluetooth/
// Display, which all configure a piece of hardware) - one tab of
// SettingsScreen.qml's fullscreen tabbed panel (see there for the tab
// bar/coordinator). Categories down the left ("Shell", "Input",
// "Updater", "Night Light", ...) mirror the Connections tab's own left
// icon-tab strip, picking which group of settings shows on the right.
//
// Everything here is a plain, immediately-saved toggle - no Apply
// button, unlike ScreenSettings.qml's staged monitor edits - persisted
// to its own barsettings.json/peripheralsettings.json/updatersettings.json
// rather than monitors.json, so a Display tab Apply can never clobber a
// Shell/Input/Updater setting (or vice versa) by overwriting the
// wrong file wholesale. WorkspaceRow.qml/WorkspaceOsd.qml/Bar.qml each
// watch barsettings.json directly for the same reason they already
// watched monitors.json - no property-passing chain needed.
// Input's mouse sensitivity/solaar startup settings are instead
// replayed by ~/.config/hypr/scripts/apply-peripherals.sh from
// hyprland.lua's own autostart block (see that script), the same
// "small JSON file + startup replay" pattern apply-monitors.sh already
// established for monitors.json. Updater.qml watches updatersettings.json
// directly too, same decoupled pattern. Night Light is the exception: its
// schedule changes settings on its own, so NightLight.qml owns its file
// and this category just drives that object (`nightLight`), as does Dropdown
// Console with DropdownConsole.qml (`dropdownConsole`) and Power with
// Idle.qml (`idle`). The UI Scale
// slider under the category list works the same way: UiScale.qml owns
// its file and hands the value to every component through shell.qml, and
// the slider here only calls its set() (`uiScaleSetting`).
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false

    // NightLight.qml, from shell.qml via SettingsScreen.qml.
    property var nightLight: null

    // DropdownConsole.qml, from shell.qml via SettingsScreen.qml.
    property var dropdownConsole: null

    // Idle.qml, from shell.qml via SettingsScreen.qml - the Power category.
    property var idle: null

    // UiScale.qml, from shell.qml via SettingsScreen.qml - the UI Scale
    // slider under the category list.
    property var uiScaleSetting: null

    // The UI Scale slider's position while it's being dragged. The scale
    // itself only changes once the slider is let go: it resizes this very
    // screen, slider included, which would keep shifting the value under
    // the cursor mid-drag.
    property bool uiScaleDragging: false
    property real draggedUiScale: 1
    readonly property real shownUiScale: root.uiScaleDragging
        ? root.draggedUiScale
        : (root.uiScaleSetting ? root.uiScaleSetting.value : 1)

    anchors.fill: parent

    // 0 = Shell, 1 = Input, 2 = Updater, 3 = Night Light, 4 = Dropdown Console,
    // 5 = Power.
    property int currentCategory: 0
    onCurrentCategoryChanged: categoryScroll.contentY = 0

    // Night Light category's view of root.nightLight, with defaults for the
    // moment before it's wired up.
    readonly property bool nlUsable: !!root.nightLight && root.nightLight.usable
    readonly property bool nlEnabled: !!root.nightLight && root.nightLight.enabled
    readonly property bool nlFading: !!root.nightLight && root.nightLight.fading
    readonly property real nlStrength: root.nightLight ? root.nightLight.strength : 0.5
    readonly property bool nlScheduled: !!root.nightLight && root.nightLight.scheduled
    readonly property int nlStart: root.nightLight ? root.nightLight.scheduleStart : 21 * 60
    readonly property int nlEnd: root.nightLight ? root.nightLight.scheduleEnd : 7 * 60
    readonly property int nlFadeIndex: root.nightLight ? root.nightLight.fadeIndex : 3

    function formatDuration(minutes) {
        const h = Math.floor(minutes / 60)
        const m = minutes % 60
        return h + "h" + (m > 0 ? " " + m + "m" : "")
    }

    property var barStore: ({})

    function loadBarStore() {
        barStoreProcess.running = false
        barStoreProcess.running = true
    }

    function setBarSetting(key, value) {
        const updated = Object.assign({}, root.barStore, { [key]: value })
        root.barStore = updated
        barSettingsFile.setText(JSON.stringify(updated, null, 2) + "\n")
    }

    readonly property bool strictWorkspaceWidget: !!root.barStore.strictWorkspaceWidget
    readonly property bool showEmptyWidget: !!root.barStore.showEmptyWidget
    readonly property bool showEmptyOsd: !!root.barStore.showEmptyOsd
    // Defaults true (rather than !! which would default false) - matches
    // BrightnessControl.qml's own always-on-until-told-otherwise default,
    // so a fresh install with no barsettings.json yet still shows it.
    readonly property bool showBrightnessControl: root.barStore.showBrightnessControl !== false
    readonly property bool showUpdater: root.barStore.showUpdater !== false
    readonly property bool showFullscreenHint: root.barStore.showFullscreenHint !== false

    function toggleStrictWorkspaceWidget() { root.setBarSetting("strictWorkspaceWidget", !root.strictWorkspaceWidget) }
    function toggleShowEmptyWidget() { root.setBarSetting("showEmptyWidget", !root.showEmptyWidget) }
    function toggleShowEmptyOsd() { root.setBarSetting("showEmptyOsd", !root.showEmptyOsd) }
    function toggleShowBrightnessControl() { root.setBarSetting("showBrightnessControl", !root.showBrightnessControl) }
    function toggleShowUpdater() { root.setBarSetting("showUpdater", !root.showUpdater) }
    function toggleShowFullscreenHint() { root.setBarSetting("showFullscreenHint", !root.showFullscreenHint) }

    // The volume, brightness and input language OSDs - OsdHost.qml reads
    // these back (and shows a preview whenever one changes).
    readonly property real osdSize: {
        const n = Number(root.barStore.osdSize)
        return isFinite(n) && n > 0 ? Math.max(0.5, Math.min(1.2, n)) : 0.8
    }
    readonly property var osdPositions: [
        { value: "top-left", label: "Top left" }, { value: "top", label: "Top" }, { value: "top-right", label: "Top right" },
        { value: "bottom-left", label: "Bottom left" }, { value: "bottom", label: "Bottom" }, { value: "bottom-right", label: "Bottom right" }
    ]
    readonly property string osdPosition: root.osdPositions.some(p => p.value === root.barStore.osdPosition) ? root.barStore.osdPosition : "bottom"
    // Corners only stack vertically.
    readonly property bool osdInCorner: root.osdPosition.endsWith("left") || root.osdPosition.endsWith("right")
    readonly property string osdStacking: root.osdInCorner || root.barStore.osdStacking === "vertical" ? "vertical" : "horizontal"

    // 50 - 120% (80% unless set - see OsdHost.qml), in steps of 5.
    function setOsdSize(size) { root.setBarSetting("osdSize", Math.round(Math.max(0.5, Math.min(1.2, size)) * 20) / 20) }
    function setOsdPosition(position) { root.setBarSetting("osdPosition", position) }
    function setOsdStacking(stacking) { if (!root.osdInCorner) root.setBarSetting("osdStacking", stacking) }

    // ---------------- Input (peripheralsettings.json) ----------------
    property var peripheralsStore: ({})

    function loadPeripheralsStore() {
        peripheralsStoreProcess.running = false
        peripheralsStoreProcess.running = true
        liveLayoutProcess.running = false
        liveLayoutProcess.running = true
        if (root.availableLayouts.length === 0) {
            layoutListProcess.running = false
            layoutListProcess.running = true
        }
    }

    function setPeripheralSetting(key, value) {
        const updated = Object.assign({}, root.peripheralsStore, { [key]: value })
        root.peripheralsStore = updated
        peripheralsSettingsFile.setText(JSON.stringify(updated, null, 2) + "\n")
    }

    // -1.0 - 1.0, 0 means no modification - same range/meaning as
    // hyprland.lua's own input.sensitivity, since this is the exact
    // same setting.
    readonly property real mouseSensitivity: root.peripheralsStore.mouseSensitivity !== undefined ? root.peripheralsStore.mouseSensitivity : 0
    // Defaults true, matching hyprland.lua.example's own previously-
    // unconditional `hl.exec_cmd("solaar --window hide")` autostart line -
    // a fresh install with no peripheralsettings.json yet still starts it.
    readonly property bool solaarStartupEnabled: root.peripheralsStore.solaarStartupEnabled !== false
    // Off by default - InputDevices.qml (which applies all of these) says
    // what off means.
    readonly property bool mouseAcceleration: root.peripheralsStore.mouseAcceleration === true

    // The input languages (xkb layout codes), in order: the first is the
    // one in use after login. Until some are saved, whatever Hyprland has
    // now - hyprland.lua's kb_layout.
    readonly property var keyboardLayouts: {
        const saved = root.peripheralsStore.keyboardLayouts
        if (Array.isArray(saved) && saved.length > 0) return saved.map(String)
        return root.liveLayouts.length > 0 ? root.liveLayouts : ["us"]
    }
    property var liveLayouts: []
    // Every layout xkb knows: [{ code, name }], by name.
    property var availableLayouts: []
    property string layoutSearch: ""

    function layoutName(code) {
        const known = root.availableLayouts.find(l => l.code === code)
        return known ? known.name : code
    }

    // Ticked: added at the end. Unticked: gone - but never the last one.
    function toggleLayout(code) {
        const current = root.keyboardLayouts
        if (current.indexOf(code) >= 0) {
            if (current.length > 1) root.setPeripheralSetting("keyboardLayouts", current.filter(c => c !== code))
        } else {
            root.setPeripheralSetting("keyboardLayouts", current.concat([code]))
        }
    }

    // To the front, so it's the one in use after login.
    function makeLayoutFirst(code) {
        const current = root.keyboardLayouts
        if (current[0] === code) return
        root.setPeripheralSetting("keyboardLayouts", [code].concat(current.filter(c => c !== code)))
    }

    // The language list: the ticked ones first, in their order, then the
    // rest by name - narrowed to the search's matches (name or code).
    readonly property var shownLayouts: {
        const query = root.layoutSearch.trim().toLowerCase()
        const chosen = root.keyboardLayouts
        const matches = l => query.length === 0 || l.name.toLowerCase().indexOf(query) >= 0 || l.code.toLowerCase().indexOf(query) >= 0
        const ticked = chosen.map(code => root.availableLayouts.find(l => l.code === code) || { code, name: code }).filter(matches)
        const rest = root.availableLayouts.filter(l => chosen.indexOf(l.code) < 0 && matches(l))
        return ticked.concat(rest)
    }

    function toggleMouseAcceleration() { root.setPeripheralSetting("mouseAcceleration", !root.mouseAcceleration) }

    // Live-dragged value, separate from mouseSensitivity (which only
    // updates once sensitivityApplyTimer's debounce actually writes it
    // to disk) - same "instant UI feedback, debounced real apply" split
    // BrightnessControl.qml's own barBrightnessOverride/applyTimer use,
    // so dragging the slider doesn't fire a `hyprctl eval` on every
    // single pixel of mouse movement.
    property real stagedSensitivity: 0

    function toggleSolaarStartup() {
        const newVal = !root.solaarStartupEnabled
        root.setPeripheralSetting("solaarStartupEnabled", newVal)
        if (newVal) {
            solaarStartProcess.running = false
            solaarStartProcess.running = true
        } else {
            solaarStopProcess.running = false
            solaarStopProcess.running = true
        }
    }

    // ---------------- Updater ----------------
    // Watched directly by Updater.qml too (its own FileView, same
    // decoupled-from-this-instance pattern barsettings.json/
    // peripheralsettings.json already use) - this is purely the UI side
    // of editing it.
    property var updaterStore: ({})

    function loadUpdaterStore() {
        updaterStoreProcess.running = false
        updaterStoreProcess.running = true
    }

    function setUpdaterSetting(key, value) {
        const updated = Object.assign({}, root.updaterStore, { [key]: value })
        root.updaterStore = updated
        updaterSettingsFile.setText(JSON.stringify(updated, null, 2) + "\n")
    }

    readonly property bool highlightOnUpdates: root.updaterStore.highlightOnUpdates !== false
    // Falls back to 30 whenever the stored value is missing or not a
    // positive number, same reasoning as Updater.qml's own identical
    // property - both read the same file, this is just the editable
    // mirror of it.
    readonly property int checkIntervalMinutes: {
        const raw = root.updaterStore.checkIntervalMinutes
        const n = Number(raw)
        return (raw !== undefined && !isNaN(n) && n > 0) ? n : 30
    }

    // Off unless turned on, same as Updater.qml's own copy.
    readonly property bool followPurpura: root.updaterStore.followPurpura === true

    function toggleHighlightOnUpdates() { root.setUpdaterSetting("highlightOnUpdates", !root.highlightOnUpdates) }
    function toggleFollowPurpura() { root.setUpdaterSetting("followPurpura", !root.followPurpura) }

    onActiveChanged: if (root.active) { root.loadBarStore(); root.loadPeripheralsStore(); root.loadUpdaterStore() }
    Component.onCompleted: { root.loadBarStore(); root.loadPeripheralsStore(); root.loadUpdaterStore() }

    // Read via `cat`, same idiom ScreenSettings.qml uses for monitors.json -
    // a missing file (first run) just yields empty stdout instead of
    // needing to reason about FileView's own missing-file behavior.
    Process {
        id: barStoreProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/barsettings.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.barStore = JSON.parse(text)
                } catch (e) {
                    root.barStore = {}
                }
            }
        }
    }

    // Write-only from here - WorkspaceRow.qml/WorkspaceOsd.qml/Bar.qml
    // each read this file back themselves via their own watchChanges
    // FileView, same split ScreenSettings.qml/monitorsFile already uses.
    FileView {
        id: barSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/barsettings.json"
        preload: false
    }

    // Same `cat`-via-Process idiom as barStoreProcess above.
    Process {
        id: peripheralsStoreProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/peripheralsettings.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.peripheralsStore = JSON.parse(text)
                } catch (e) {
                    root.peripheralsStore = {}
                }
                // Seeds the live slider position from whatever was just
                // loaded off disk - without this the slider would sit at
                // 0 (stagedSensitivity's own default) until the user
                // first touched it, even though a non-zero sensitivity
                // was already persisted.
                root.stagedSensitivity = root.mouseSensitivity
            }
        }
    }

    // Write-only from here: InputDevices.qml reads it back and applies it
    // (and apply-peripherals.sh at login).
    FileView {
        id: peripheralsSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/peripheralsettings.json"
        preload: false
    }

    // The input languages Hyprland has now (its main keyboard's), for
    // before any are saved.
    Process {
        id: liveLayoutProcess
        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards || []
                    const main = keyboards.find(k => k.main) || keyboards[0]
                    root.liveLayouts = main && main.layout
                        ? String(main.layout).split(",").map(s => s.trim()).filter(s => /^[A-Za-z0-9_-]+$/.test(s))
                        : []
                } catch (e) {
                    root.liveLayouts = []
                }
            }
        }
    }

    // Every layout xkb knows, with its name - the "! layout" part of its
    // rules list ("  hu              Hungarian").
    Process {
        id: layoutListProcess
        command: ["sh", "-c", "f=/usr/share/X11/xkb/rules/evdev.lst; [ -r \"$f\" ] || f=/usr/share/X11/xkb/rules/base.lst; "
            + "sed -n '/^! layout/,/^! /p' \"$f\""]

        stdout: StdioCollector {
            onStreamFinished: {
                const list = []
                for (const line of text.split("\n")) {
                    const m = /^\s+([A-Za-z0-9_-]+)\s+(.+?)\s*$/.exec(line)
                    // "custom" needs a hand-made xkb file - not one to tick.
                    if (m && m[1] !== "custom") list.push({ code: m[1], name: m[2] })
                }
                root.availableLayouts = list.sort((a, b) => a.name.localeCompare(b.name))
            }
        }
    }

    // Same `cat`-via-Process idiom as barStoreProcess/peripheralsStoreProcess
    // above.
    Process {
        id: updaterStoreProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/updatersettings.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.updaterStore = JSON.parse(text)
                } catch (e) {
                    root.updaterStore = {}
                }
            }
        }
    }

    // Write-only, same reasoning as barSettingsFile/peripheralsSettingsFile
    // above - Updater.qml reads this back itself via its own
    // watchChanges FileView.
    FileView {
        id: updaterSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/updatersettings.json"
        preload: false
    }

    // Debounced save for the sensitivity slider - see stagedSensitivity's
    // own comment above for why. InputDevices.qml puts it into Hyprland
    // once it's saved.
    Timer {
        id: sensitivityApplyTimer
        interval: 330
        repeat: false
        onTriggered: root.setPeripheralSetting("mouseSensitivity", root.stagedSensitivity)
    }

    // Immediate live effect for the Solaar Startup toggle, on top of the
    // persisted setting apply-peripherals.sh reads at next login - "off"
    // stops it right now instead of only taking effect after a restart,
    // and "on" starts it right now for the same reason the checkbox
    // reads as an immediately-applied toggle everywhere else in this
    // file. `--window hide` matches hyprland.lua.example's own previous
    // unconditional autostart line exactly.
    Process {
        id: solaarStartProcess
        command: ["solaar", "--window", "hide"]
    }

    Process {
        id: solaarStopProcess
        command: ["pkill", "-x", "solaar"]
    }

    Item {
        id: contentWrapper

        anchors.fill: parent

        RowLayout {
            id: contentRow

            readonly property real margins: Config.scaled(18, root.uiScale)

            anchors {
                fill: parent
                margins: contentRow.margins
            }
            spacing: Config.scaled(12, root.uiScale)

            readonly property real dividerWidth: Config.scaled(2, root.uiScale)
            readonly property real leftWidth: Config.scaled(200, root.uiScale)

            // ---------------- LEFT: categories ----------------
            ColumnLayout {
                id: categoryColumn

                // minimumWidth/maximumWidth pin this to exactly
                // leftWidth, not just preferredWidth - a RowLayout is
                // still free to shrink a child below its preferredWidth
                // (down to minimumWidth, which otherwise defaults to 0)
                // when the row doesn't have enough space for everyone's
                // preferred size, which is exactly what let this column
                // visibly narrow/widen depending on how wide the
                // currently-selected category's own content on the right
                // (categoryContent, Layout.fillWidth) happened to want to
                // be - reported live as this column resizing depending
                // on the right panel.
                Layout.preferredWidth: contentRow.leftWidth
                Layout.minimumWidth: contentRow.leftWidth
                Layout.maximumWidth: contentRow.leftWidth
                Layout.fillHeight: true
                spacing: Config.scaled(8, root.uiScale)

                DashCard {
                    id: barCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: barCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 0 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Shell"
                        color: barCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: barCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 0
                    }
                }

                DashCard {
                    id: peripheralsCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: peripheralsCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 1 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Input"
                        color: peripheralsCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: peripheralsCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 1
                    }
                }

                DashCard {
                    id: updaterCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: updaterCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 2 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Updater"
                        color: updaterCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: updaterCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 2
                    }
                }

                DashCard {
                    id: nightLightCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: nightLightCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 3 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Night Light"
                        color: nightLightCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: nightLightCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 3
                    }
                }

                DashCard {
                    id: consoleCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: consoleCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 4 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Dropdown Console"
                        color: consoleCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: consoleCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 4
                    }
                }

                DashCard {
                    id: powerCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: powerCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 5 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Power"
                        color: powerCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: powerCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 5
                    }
                }

                Item { Layout.fillHeight: true }

                // ---------------- UI scale ----------------
                // The whole shell's size (UiScale.qml), on top of each
                // screen's own resolution-based scale - not a category of
                // its own, just a small control pinned under the list.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(2, root.uiScale)
                    visible: !!root.uiScaleSetting
                    color: Config.fgcolor
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(4, root.uiScale)
                    visible: !!root.uiScaleSetting

                    Text {
                        Layout.fillWidth: true
                        text: "UI Scale"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    Text {
                        text: Math.round(root.shownUiScale * 100) + "%"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }
                }

                DeviceSlider {
                    id: uiScaleSlider

                    Layout.fillWidth: true
                    Layout.preferredHeight: uiScaleSlider.implicitHeight
                    visible: !!root.uiScaleSetting
                    uiScale: root.uiScale

                    readonly property real minimum: root.uiScaleSetting ? root.uiScaleSetting.minimum : 0.5
                    readonly property real maximum: root.uiScaleSetting ? root.uiScaleSetting.maximum : 1.5

                    value: (root.shownUiScale - uiScaleSlider.minimum) / (uiScaleSlider.maximum - uiScaleSlider.minimum)

                    // Snaps to UiScale's 5% steps while dragging, so the
                    // label never shows a value that can't be applied.
                    onMoved: (newValue) => {
                        root.draggedUiScale = root.uiScaleSetting.clamp(
                            uiScaleSlider.minimum + newValue * (uiScaleSlider.maximum - uiScaleSlider.minimum))
                        root.uiScaleDragging = true
                    }
                    onReleased: {
                        if (!root.uiScaleDragging) return
                        root.uiScaleSetting.set(root.draggedUiScale)
                        root.uiScaleDragging = false
                    }
                }
            }

            // ---------------- divider ----------------
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.fillHeight: true
                color: Config.fgcolor
            }

            // ---------------- RIGHT: current category's settings ----------------
            // Scrolls when a category's taller than the panel - only then.
            Flickable {
                id: categoryScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: categoryContent.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: categoryContent

                    width: categoryScroll.width
                    spacing: Config.scaled(10, root.uiScale)

                    // ---------------- Shell category ----------------
                    ColumnLayout {
                        id: barCategoryContent

                        Layout.fillWidth: true
                        visible: root.currentCategory === 0
                        spacing: Config.scaled(10, root.uiScale)

                    // ---------------- only managed workspaces in widget ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Config.scaled(8, root.uiScale)
                        spacing: Config.scaled(8, root.uiScale)

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.strictWorkspaceWidget ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleStrictWorkspaceWidget()
                            }
                        }

                        Text {
                            text: "Only Managed Workspaces In Widget"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleStrictWorkspaceWidget()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    SettingHint {
                        // Close under the setting it's for, like the Power category's.
                        Layout.topMargin: -Config.scaled(6, root.uiScale)
                        uiScale: root.uiScale
                        text: "The bar's workspace list shows only workspaces 1-5 that are pinned to a monitor in Display settings, each on its own monitor."
                    }

                    // ---------------- show empty workspaces (widget) ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(8, root.uiScale)

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.showEmptyWidget ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowEmptyWidget()
                            }
                        }

                        Text {
                            text: "Show Empty Workspaces In Widget"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowEmptyWidget()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    SettingHint {
                        // Close under the setting it's for, like the Power category's.
                        Layout.topMargin: -Config.scaled(6, root.uiScale)
                        uiScale: root.uiScale
                        text: "Pinned workspaces that haven't been opened yet still get a box in the bar's workspace list, to click straight to."
                    }

                    // ---------------- show empty workspaces (osd) ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(8, root.uiScale)

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.showEmptyOsd ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowEmptyOsd()
                            }
                        }

                        Text {
                            text: "Show Empty Workspaces In OSD"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowEmptyOsd()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    SettingHint {
                        // Close under the setting it's for, like the Power category's.
                        Layout.topMargin: -Config.scaled(6, root.uiScale)
                        uiScale: root.uiScale
                        text: "The same for the workspace popup that shows for a moment when you switch workspace."
                    }
                    Item {}
                    // ---------------- brightness control ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(8, root.uiScale)

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.showBrightnessControl ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowBrightnessControl()
                            }
                        }

                        Text {
                            text: "Show Brightness Control Widget"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowBrightnessControl()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    SettingHint {
                        // Close under the setting it's for, like the Power category's.
                        Layout.topMargin: -Config.scaled(6, root.uiScale)
                        uiScale: root.uiScale
                        text: "The brightness control on the bar."
                    }

                    // ---------------- show updater ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(8, root.uiScale)

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.showUpdater ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowUpdater()
                            }
                        }

                        Text {
                            text: "Show Updater Widget"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowUpdater()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    SettingHint {
                        // Close under the setting it's for, like the Power category's.
                        Layout.topMargin: -Config.scaled(6, root.uiScale)
                        uiScale: root.uiScale
                        text: "The updates button on the bar: left-click lists what's waiting, right-click updates everything."
                    }

                    // ---------------- fullscreen hint ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(8, root.uiScale)

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.showFullscreenHint ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowFullscreenHint()
                            }
                        }

                        Text {
                            text: "Show fullscreen hint"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleShowFullscreenHint()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    SettingHint {
                        // Close under the setting it's for, like the Power category's.
                        Layout.topMargin: -Config.scaled(6, root.uiScale)
                        uiScale: root.uiScale
                        text: "A moment's reminder, when a window goes fullscreen, that META + D still opens the dashboard behind it."
                    }

                    // ---------------- OSD ----------------
                    // The volume, brightness and input language popups. Every
                    // change shows them all for a moment, as a preview.
                    SectionHeader {
                        uiScale: root.uiScale
                        text: "OSD"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(6, root.uiScale)

                        RowLayout {
                            Layout.preferredWidth: Config.scaled(420, root.uiScale)
                            Layout.fillWidth: false
                            spacing: Config.scaled(8, root.uiScale)

                            Text {
                                text: "OSD Size:"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: Math.round(root.osdSize * 100) + "%"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }
                        }

                        // 50 - 120%, in steps of 5.
                        DeviceSlider {
                            Layout.preferredWidth: Config.scaled(420, root.uiScale)
                            uiScale: root.uiScale
                            value: (root.osdSize - 0.5) / 0.7
                            onMoved: (newValue) => root.setOsdSize(0.5 + newValue * 0.7)
                        }

                        SettingHint {
                            uiScale: root.uiScale
                            indented: false
                            text: "How big the volume, brightness and input language popups are."
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(6, root.uiScale)

                        Text {
                            text: "OSD Position:"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        // Laid out like the screen: the top three, then the bottom.
                        GridLayout {
                            columns: 3
                            columnSpacing: Config.scaled(6, root.uiScale)
                            rowSpacing: Config.scaled(6, root.uiScale)

                            Repeater {
                                model: root.osdPositions

                                DashCard {
                                    id: positionButton

                                    required property var modelData
                                    readonly property bool chosen: root.osdPosition === positionButton.modelData.value

                                    Layout.preferredWidth: Config.scaled(130, root.uiScale)
                                    Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                    uiScale: root.uiScale
                                    color: (positionMouse.containsMouse || positionButton.chosen) ? Config.fgcolorhover : Config.fillcolor
                                    border.color: positionButton.chosen ? Config.fgcolorlight : Config.fgcolor

                                    Text {
                                        anchors.centerIn: parent
                                        text: positionButton.modelData.label
                                        color: positionButton.chosen ? Config.fgcolorlight : Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: positionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.setOsdPosition(positionButton.modelData.value)
                                    }
                                }
                            }
                        }

                        SettingHint {
                            uiScale: root.uiScale
                            indented: false
                            text: "Where they show, on the bar's monitor. Along the top they sit under the bar."
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.scaled(6, root.uiScale)

                        Text {
                            text: "OSD Stacking:"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        // Locked to vertical in a corner.
                        RowLayout {
                            spacing: Config.scaled(6, root.uiScale)
                            enabled: !root.osdInCorner
                            opacity: enabled ? 1 : 0.5

                            Repeater {
                                model: [{ value: "vertical", label: "Vertical" }, { value: "horizontal", label: "Horizontal" }]

                                DashCard {
                                    id: stackingButton

                                    required property var modelData
                                    readonly property bool chosen: root.osdStacking === stackingButton.modelData.value

                                    Layout.preferredWidth: Config.scaled(130, root.uiScale)
                                    Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                    uiScale: root.uiScale
                                    color: (stackingMouse.containsMouse || stackingButton.chosen) ? Config.fgcolorhover : Config.fillcolor
                                    border.color: stackingButton.chosen ? Config.fgcolorlight : Config.fgcolor

                                    Text {
                                        anchors.centerIn: parent
                                        text: stackingButton.modelData.label
                                        color: stackingButton.chosen ? Config.fgcolorlight : Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: stackingMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.setOsdStacking(stackingButton.modelData.value)
                                    }
                                }
                            }
                        }

                        SettingHint {
                            uiScale: root.uiScale
                            indented: false
                            text: root.osdInCorner
                                ? "How they line up when more than one shows at once - always one above the other in a corner."
                                : "How they line up when more than one shows at once: one above the other, or side by side."
                        }
                    }

                    } // barCategoryContent

                    // ---------------- Input category ----------------
                    // Saved to peripheralsettings.json; InputDevices.qml puts it
                    // all into Hyprland.
                    ColumnLayout {
                        id: peripheralsCategoryContent

                        Layout.fillWidth: true
                        visible: root.currentCategory === 1
                        spacing: Config.scaled(10, root.uiScale)

                        // ---------------- Mouse ----------------
                        SectionHeader {
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            uiScale: root.uiScale
                            text: "Mouse"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(6, root.uiScale)

                            RowLayout {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.fillWidth: false
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "Mouse Sensitivity:"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.stagedSensitivity.toFixed(2)
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }
                            }

                            DeviceSlider {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                uiScale: root.uiScale
                                // Maps hyprland.lua's -1.0 - 1.0 sensitivity
                                // range onto DeviceSlider's own fixed 0.0 - 1.0
                                // control range.
                                value: (root.stagedSensitivity + 1) / 2
                                onMoved: (newValue) => {
                                    root.stagedSensitivity = Math.round((newValue * 2 - 1) * 100) / 100
                                    sensitivityApplyTimer.restart()
                                }
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                indented: false
                                text: "How far the cursor goes for the same mouse movement, from -1 (slowest) to 1 (fastest). At 0 with acceleration off, it goes exactly as far as the mouse reports."
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(4, root.uiScale)

                            CheckRow {
                                Layout.fillWidth: true
                                uiScale: root.uiScale
                                text: "Mouse Acceleration"
                                checked: root.mouseAcceleration
                                onToggled: root.toggleMouseAcceleration()
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                text: "Moving the mouse faster takes the cursor further than the same distance moved slowly. Off, the cursor always goes the same distance - best for aiming."
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                text: "You do NOT want this in first person shooters."
                                color: "#a11d1d"
                                font.bold: true
                            }
                        }

                        // ---------------- Keyboard ----------------
                        SectionHeader {
                            uiScale: root.uiScale
                            text: "Keyboard"
                        }

                        Text {
                            text: "Input Languages:"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        // The ticked languages in order - the first, lit, is the
                        // one in use after login. Clicking another puts it first;
                        // its x takes it off (never the last one).
                        Flow {
                            Layout.fillWidth: true
                            spacing: Config.scaled(6, root.uiScale)

                            Repeater {
                                model: root.keyboardLayouts

                                DashCard {
                                    id: languageChip

                                    required property string modelData
                                    required property int index
                                    readonly property bool first: languageChip.index === 0

                                    uiScale: root.uiScale
                                    width: chipRow.implicitWidth + Config.scaled(16, root.uiScale)
                                    height: Config.scaled(28, root.uiScale)
                                    color: chipMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                    border.color: languageChip.first ? Config.fgcolorlight : Config.fgcolor

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.makeLayoutFirst(languageChip.modelData)
                                    }

                                    Row {
                                        id: chipRow

                                        anchors.centerIn: parent
                                        spacing: Config.scaled(8, root.uiScale)

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.layoutName(languageChip.modelData)
                                            color: languageChip.first ? Config.fgcolorlight : Config.fgcolor
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(12, root.uiScale)
                                            font.bold: true
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: root.keyboardLayouts.length > 1
                                            text: "x"
                                            color: removeMouse.containsMouse ? Config.fgcolorred : Config.fgcolorhint
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(12, root.uiScale)
                                            font.bold: true

                                            MouseArea {
                                                id: removeMouse
                                                anchors.fill: parent
                                                anchors.margins: -Config.scaled(4, root.uiScale)
                                                hoverEnabled: true
                                                onClicked: root.toggleLayout(languageChip.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Search, then tick.
                        Rectangle {
                            Layout.preferredWidth: Config.scaled(420, root.uiScale)
                            Layout.preferredHeight: Config.scaled(30, root.uiScale)
                            color: Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: layoutSearchInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

                            TextInput {
                                id: layoutSearchInput

                                anchors.fill: parent
                                anchors.leftMargin: Config.scaled(8, root.uiScale)
                                anchors.rightMargin: Config.scaled(8, root.uiScale)
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: Config.fgcolor
                                selectionColor: Config.fgcolorhover
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                onTextEdited: root.layoutSearch = layoutSearchInput.text
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Config.scaled(8, root.uiScale)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: layoutSearchInput.text.length === 0
                                text: "Search languages..."
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(420, root.uiScale)
                            Layout.preferredHeight: Config.scaled(200, root.uiScale)
                            color: Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor

                            ListView {
                                id: layoutList

                                anchors.fill: parent
                                anchors.margins: Config.scaled(6, root.uiScale)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.shownLayouts

                                delegate: Rectangle {
                                    id: layoutRow

                                    required property var modelData
                                    readonly property bool ticked: root.keyboardLayouts.indexOf(layoutRow.modelData.code) >= 0

                                    width: layoutList.width
                                    height: Config.scaled(26, root.uiScale)
                                    color: layoutRowMouse.containsMouse ? Config.fgcolorhover : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Config.scaled(4, root.uiScale)
                                        anchors.rightMargin: Config.scaled(6, root.uiScale)
                                        spacing: Config.scaled(8, root.uiScale)

                                        Rectangle {
                                            Layout.preferredWidth: Config.scaled(16, root.uiScale)
                                            Layout.preferredHeight: Config.scaled(16, root.uiScale)
                                            color: layoutRow.ticked ? Config.fgcolor : Config.fillcolor
                                            border.width: Config.scaled(2, root.uiScale)
                                            border.color: Config.fgcolor
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: layoutRow.modelData.name
                                            color: layoutRow.ticked ? Config.fgcolorlight : Config.fgcolor
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(13, root.uiScale)
                                            font.bold: layoutRow.ticked
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: layoutRow.modelData.code
                                            color: Config.fgcolorhint
                                            font.family: Config.fontfamily
                                            font.pixelSize: Config.scaled(12, root.uiScale)
                                        }
                                    }

                                    MouseArea {
                                        id: layoutRowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.toggleLayout(layoutRow.modelData.code)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: layoutList.count === 0
                                text: root.availableLayouts.length === 0 ? "Loading..." : "No language matches."
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                            }
                        }

                        SettingHint {
                            uiScale: root.uiScale
                            indented: false
                            text: "Tick the languages you type in. With more than one, META + - switches to the next and shows which is on; the first (lit) is the one in use after login - click another to put it first."
                        }

                        // ---------------- the rest ----------------
                        SectionHeader {
                            uiScale: root.uiScale
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(4, root.uiScale)

                            CheckRow {
                                Layout.fillWidth: true
                                uiScale: root.uiScale
                                text: "Solaar Startup"
                                checked: root.solaarStartupEnabled
                                onToggled: root.toggleSolaarStartup()
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                text: "Starts Solaar, for Logitech wireless devices, in the background at login. Turning it on or off starts or stops it now as well."
                            }
                        }
                    }

                    // ---------------- Updater category ----------------
                    ColumnLayout {
                        id: updaterCategoryContent

                        Layout.fillWidth: true
                        visible: root.currentCategory === 2
                        spacing: Config.scaled(10, root.uiScale)

                        // ---------------- highlight on updates ----------------
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            spacing: Config.scaled(8, root.uiScale)

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                color: root.highlightOnUpdates ? Config.fgcolor : Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: Config.fgcolor
                                radius: 0

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.toggleHighlightOnUpdates()
                                }
                            }

                            Text {
                                text: "Highlight Button When Updates Available"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.toggleHighlightOnUpdates()
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        SettingHint {
                            // Close under the setting it's for, like the Power category's.
                            Layout.topMargin: -Config.scaled(6, root.uiScale)
                            uiScale: root.uiScale
                            text: "The updates button on the bar lights up while anything is waiting to update."
                        }

                        // ---------------- follow purpura ----------------
                        // Purpura's own updates in the updater - see Updater.qml
                        // and helpers/purpura-update.sh.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(4, root.uiScale)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Config.scaled(8, root.uiScale)

                                Rectangle {
                                    Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                    Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                    color: root.followPurpura ? Config.fgcolor : Config.fillcolor
                                    border.width: Config.scaled(2, root.uiScale)
                                    border.color: Config.fgcolor
                                    radius: 0

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.toggleFollowPurpura()
                                    }
                                }

                                Text {
                                    text: "Follow Purpura versioning"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.toggleFollowPurpura()
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: Config.scaled(28, root.uiScale)
                                wrapMode: Text.WordWrap
                                text: "Checks the checkout purpura was installed from for new commits: a notification for each new version, "
                                    + "its state under the updater's list, and right-clicking the updater installs it just before the firmware updates."
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(12, root.uiScale)
                            }
                        }

                        // ---------------- update check interval ----------------
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(4, root.uiScale)
                            spacing: Config.scaled(8, root.uiScale)

                            Text {
                                text: "Check for updates every"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(60, root.uiScale)
                                Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                color: Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: intervalInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

                                TextInput {
                                    id: intervalInput

                                    anchors {
                                        fill: parent
                                        margins: Config.scaled(6, root.uiScale)
                                    }
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    selectByMouse: true
                                    clip: true

                                    // Positive whole numbers only.
                                    validator: RegularExpressionValidator { regularExpression: /^[0-9]*$/ }

                                    // Guards the programmatic resync below
                                    // from being mistaken for a user edit by
                                    // onTextChanged - same reasoning
                                    // LabeledField.qml's own `syncing` flag
                                    // has for the exact same pattern.
                                    property bool syncing: false
                                    text: String(root.checkIntervalMinutes)

                                    Connections {
                                        target: root
                                        function onCheckIntervalMinutesChanged() {
                                            intervalInput.syncing = true
                                            intervalInput.text = String(root.checkIntervalMinutes)
                                            intervalInput.syncing = false
                                        }
                                    }

                                    // Committed live, on every keystroke that
                                    // actually parses to a positive integer -
                                    // an empty/in-progress edit (e.g. the
                                    // field momentarily cleared while
                                    // retyping) is just left unsaved rather
                                    // than persisting 0/NaN, root.
                                    // checkIntervalMinutes's own fallback
                                    // covers it meanwhile.
                                    onTextChanged: {
                                        if (intervalInput.syncing) return
                                        const n = parseInt(intervalInput.text, 10)
                                        if (!isNaN(n) && n > 0) {
                                            root.setUpdaterSetting("checkIntervalMinutes", n)
                                        }
                                    }

                                    onAccepted: intervalInput.focus = false
                                }
                            }

                            Text {
                                text: "minutes"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }
                        }

                        SettingHint {
                            // Close under the setting it's for, like the Power category's.
                            Layout.topMargin: -Config.scaled(6, root.uiScale)
                            uiScale: root.uiScale
                            indented: false
                            text: "How often pacman, the AUR and flatpak are checked for updates - and purpura, when it's followed."
                        }
                    }

                    // ---------------- Night Light category ----------------
                    ColumnLayout {
                        id: nightLightCategoryContent

                        Layout.fillWidth: true
                        visible: root.currentCategory === 3
                        spacing: Config.scaled(10, root.uiScale)

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            visible: !!root.nightLight && root.nightLight.availabilityKnown && !root.nlUsable
                            text: root.nightLight && root.nightLight.failed
                                ? "hyprsunset keeps exiting right after it starts, so night light is unavailable."
                                : "Night light needs hyprsunset: sudo pacman -S hyprsunset"
                            color: Config.fgcolorred
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            spacing: Config.scaled(10, root.uiScale)
                            enabled: root.nlUsable
                            opacity: enabled ? 1 : 0.35

                            // ---------------- on/off ----------------
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Config.scaled(8, root.uiScale)

                                Rectangle {
                                    Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                    Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                    color: root.nlEnabled ? Config.fgcolor : Config.fillcolor
                                    border.width: Config.scaled(2, root.uiScale)
                                    border.color: Config.fgcolor
                                    radius: 0

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.nightLight.setEnabled(!root.nlEnabled)
                                    }
                                }

                                Text {
                                    text: "Night Light"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.nightLight.setEnabled(!root.nlEnabled)
                                    }
                                }

                                Text {
                                    visible: root.nlFading
                                    text: root.nlEnabled ? "(fading in)" : "(fading out)"
                                    color: Config.fgcolorhint
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                }

                                Item { Layout.fillWidth: true }
                            }

                            SettingHint {
                                // Close under the setting it's for, like the Power category's.
                                Layout.topMargin: -Config.scaled(6, root.uiScale)
                                uiScale: root.uiScale
                                text: "Tints every screen warm, which is easier on the eyes at night."
                            }

                            // ---------------- strength ----------------
                            ColumnLayout {
                                Layout.topMargin: Config.scaled(4, root.uiScale)
                                spacing: Config.scaled(6, root.uiScale)

                                RowLayout {
                                    Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                    Layout.fillWidth: false
                                    spacing: Config.scaled(8, root.uiScale)

                                    Text {
                                        text: "Strength:"
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: Math.round(root.nlStrength * 100) + "%"
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }
                                }

                                DeviceSlider {
                                    Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                    uiScale: root.uiScale
                                    value: root.nlStrength
                                    onMoved: (newValue) => root.nightLight.setStrength(newValue)
                                }

                                SettingHint {
                                    uiScale: root.uiScale
                                    indented: false
                                    text: "How warm the tint gets - further right is warmer."
                                }
                            }

                            // ---------------- scheduled ----------------
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Config.scaled(8, root.uiScale)
                                spacing: Config.scaled(8, root.uiScale)

                                Rectangle {
                                    Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                    Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                    color: root.nlScheduled ? Config.fgcolor : Config.fillcolor
                                    border.width: Config.scaled(2, root.uiScale)
                                    border.color: Config.fgcolor
                                    radius: 0

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.nightLight.setScheduled(!root.nlScheduled)
                                    }
                                }

                                Text {
                                    text: "Scheduled Night Light"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.nightLight.setScheduled(!root.nlScheduled)
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            SettingHint {
                                // Close under the setting it's for, like the Power category's.
                                Layout.topMargin: -Config.scaled(6, root.uiScale)
                                uiScale: root.uiScale
                                text: "Turns night light on and off by itself every day, between the two times below."
                            }

                            // Only interactable while scheduling is on.
                            ColumnLayout {
                                Layout.topMargin: Config.scaled(4, root.uiScale)
                                spacing: Config.scaled(6, root.uiScale)
                                enabled: root.nlScheduled
                                opacity: enabled ? 1 : 0.35

                                RowLayout {
                                    Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                    Layout.fillWidth: false
                                    spacing: Config.scaled(8, root.uiScale)

                                    Text {
                                        text: "From " + scheduleSlider.format(scheduleSlider.previewStart)
                                            + " to " + scheduleSlider.format(scheduleSlider.previewEnd)
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.formatDuration(scheduleSlider.previewLength)
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }
                                }

                                TimeRangeSlider {
                                    id: scheduleSlider
                                    Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                    uiScale: root.uiScale
                                    startMinutes: root.nlStart
                                    endMinutes: root.nlEnd
                                    onCommitted: (start, end) => root.nightLight.setSchedule(start, end)
                                }
                            }

                            // ---------------- fade ----------------
                            // Ten lengths, 30 seconds to an hour (NightLight.qml's
                            // fadeStops) - the slider snaps to them.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Config.scaled(8, root.uiScale)
                                spacing: Config.scaled(6, root.uiScale)

                                RowLayout {
                                    Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                    Layout.fillWidth: false
                                    spacing: Config.scaled(8, root.uiScale)

                                    Text {
                                        text: "Fade In/Out:"
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.nightLight ? root.nightLight.fadeLabel(root.nlFadeIndex) : ""
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(13, root.uiScale)
                                        font.bold: true
                                    }
                                }

                                DeviceSlider {
                                    readonly property int stops: root.nightLight ? root.nightLight.fadeStops.length : 10

                                    Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                    uiScale: root.uiScale
                                    value: root.nlFadeIndex / (stops - 1)
                                    onMoved: (newValue) => root.nightLight.setFadeIndex(newValue * (stops - 1))
                                }

                                SettingHint {
                                    uiScale: root.uiScale
                                    indented: false
                                    text: "How gradually the schedule brings the tint in and takes it away. Switched by hand above, it changes at once."
                                }
                            }
                        }
                    }

                    // ---------------- Dropdown Console category ----------------
                    ColumnLayout {
                        id: consoleCategoryContent

                        Layout.fillWidth: true
                        visible: root.currentCategory === 4
                        spacing: Config.scaled(10, root.uiScale)

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            spacing: Config.scaled(6, root.uiScale)

                            RowLayout {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.fillWidth: false
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "Width:"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: (root.dropdownConsole ? root.dropdownConsole.widthPercent : 0) + "%"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }
                            }

                            DeviceSlider {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                uiScale: root.uiScale
                                value: root.dropdownConsole ? root.dropdownConsole.widthPercent / 100 : 0
                                onMoved: (newValue) => root.dropdownConsole.setWidthPercent(newValue * 100)
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                indented: false
                                text: "How much of the screen's width the console takes."
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(6, root.uiScale)

                            RowLayout {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.fillWidth: false
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "Height:"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: (root.dropdownConsole ? root.dropdownConsole.heightPercent : 0) + "%"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }
                            }

                            DeviceSlider {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                uiScale: root.uiScale
                                value: root.dropdownConsole ? root.dropdownConsole.heightPercent / 100 : 0
                                onMoved: (newValue) => root.dropdownConsole.setHeightPercent(newValue * 100)
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                indented: false
                                text: "How far down the screen the console reaches."
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(6, root.uiScale)

                            RowLayout {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.fillWidth: false
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "Font Size:"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: (root.dropdownConsole ? root.dropdownConsole.fontSize : 0) + "pt"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }
                            }

                            DeviceSlider {
                                id: consoleFontSlider

                                readonly property int minimum: root.dropdownConsole ? root.dropdownConsole.minFontSize : 0
                                readonly property int maximum: root.dropdownConsole ? root.dropdownConsole.maxFontSize : 1

                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                uiScale: root.uiScale
                                value: root.dropdownConsole ? (root.dropdownConsole.fontSize - minimum) / (maximum - minimum) : 0
                                onMoved: (newValue) => root.dropdownConsole.setFontSize(minimum + newValue * (maximum - minimum))
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                indented: false
                                text: "The terminal's text size."
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(6, root.uiScale)

                            RowLayout {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.fillWidth: false
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "Opacity:"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: (root.dropdownConsole ? root.dropdownConsole.opacityPercent : 0) + "%"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }
                            }

                            DeviceSlider {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                uiScale: root.uiScale
                                value: root.dropdownConsole ? root.dropdownConsole.opacityPercent / 100 : 0
                                onMoved: (newValue) => root.dropdownConsole.setOpacityPercent(newValue * 100)
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                indented: false
                                text: "How solid the console's background is - lower shows more of what's behind it."
                            }
                        }

                        Item {
                            Layout.preferredHeight: Config.scaled(14, root.uiScale)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(8, root.uiScale)

                            readonly property bool on: !!root.dropdownConsole && root.dropdownConsole.autoHideEnabled

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                color: parent.on ? Config.fgcolor : Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: Config.fgcolor

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.dropdownConsole.setAutoHideEnabled(!root.dropdownConsole.autoHideEnabled)
                                }
                            }

                            Text {
                                text: "Auto-hide when unfocused"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.dropdownConsole.setAutoHideEnabled(!root.dropdownConsole.autoHideEnabled)
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        SettingHint {
                            // Close under the setting it's for, like the Power category's.
                            Layout.topMargin: -Config.scaled(6, root.uiScale)
                            uiScale: root.uiScale
                            text: "Closes the console as soon as you click away from it."
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(8, root.uiScale)

                            readonly property bool on: !!root.dropdownConsole && root.dropdownConsole.autokillEnabled

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                color: parent.on ? Config.fgcolor : Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: Config.fgcolor

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.dropdownConsole.setAutokillEnabled(!root.dropdownConsole.autokillEnabled)
                                }
                            }

                            Text {
                                text: "Autokill when inactive / in background"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.dropdownConsole.setAutokillEnabled(!root.dropdownConsole.autokillEnabled)
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            id: autokillDelayRow

                            Layout.fillWidth: true
                            spacing: Config.scaled(8, root.uiScale)

                            // Dark and locked while autokill is off.
                            readonly property bool on: !!root.dropdownConsole && root.dropdownConsole.autokillEnabled
                            readonly property int minutes: root.dropdownConsole ? root.dropdownConsole.autokillMinutes : 30

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(70, root.uiScale)
                                Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                color: Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: !autokillDelayRow.on ? Config.fgcolordark
                                    : autokillDelayInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

                                TextInput {
                                    id: autokillDelayInput

                                    anchors {
                                        fill: parent
                                        margins: Config.scaled(6, root.uiScale)
                                    }
                                    enabled: autokillDelayRow.on
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: autokillDelayRow.on ? Config.fgcolor : Config.fgcolordark
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    selectByMouse: true
                                    clip: true
                                    validator: RegularExpressionValidator { regularExpression: /^[0-9]*$/ }
                                    text: String(autokillDelayRow.minutes)

                                    // Saves on Enter or on leaving the box, not on
                                    // each keystroke, so a value being typed can't
                                    // get snapped to the minimum halfway through.
                                    // Then shows what was really saved, which is
                                    // the old value if the box was left empty.
                                    onEditingFinished: {
                                        const typed = parseInt(autokillDelayInput.text, 10)
                                        if (!isNaN(typed)) root.dropdownConsole.setAutokillMinutes(typed)
                                        autokillDelayInput.text = String(autokillDelayRow.minutes)
                                    }
                                    onAccepted: autokillDelayInput.focus = false
                                }
                            }

                            Text {
                                text: "minute delay"
                                color: autokillDelayRow.on ? Config.fgcolor : Config.fgcolordark
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }
                        }

                        SettingHint {
                            // Close under the setting it's for, like the Power category's.
                            Layout.topMargin: -Config.scaled(6, root.uiScale)
                            uiScale: root.uiScale
                            indented: false
                            text: "While the console is closed, ends its terminal once it has sat at a prompt for this long. A command still running keeps it."
                        }

                        RowLayout {
                            id: autokillNotificationRow

                            Layout.fillWidth: true
                            spacing: Config.scaled(8, root.uiScale)

                            // Dark and locked while autokill is off, like the delay.
                            readonly property bool usable: autokillDelayRow.on
                            readonly property bool on: !!root.dropdownConsole && root.dropdownConsole.autokillNotification
                            readonly property color shownColor: usable ? Config.fgcolor : Config.fgcolordark

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(20, root.uiScale)
                                Layout.preferredHeight: Config.scaled(20, root.uiScale)
                                color: autokillNotificationRow.on ? autokillNotificationRow.shownColor : Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: autokillNotificationRow.shownColor

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: autokillNotificationRow.usable
                                    hoverEnabled: true
                                    onClicked: root.dropdownConsole.setAutokillNotification(!autokillNotificationRow.on)
                                }
                            }

                            Text {
                                text: "Show auto-kill notification"
                                color: autokillNotificationRow.shownColor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: autokillNotificationRow.usable
                                    hoverEnabled: true
                                    onClicked: root.dropdownConsole.setAutokillNotification(!autokillNotificationRow.on)
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        SettingHint {
                            // Close under the setting it's for, like the Power category's.
                            Layout.topMargin: -Config.scaled(6, root.uiScale)
                            uiScale: root.uiScale
                            text: "A notification when the terminal is ended that way."
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            spacing: Config.scaled(6, root.uiScale)

                            Text {
                                text: "Execute on new instance:"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            Rectangle {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.preferredHeight: Config.scaled(28, root.uiScale)
                                color: Config.fillcolor
                                border.width: Config.scaled(2, root.uiScale)
                                border.color: startupCommandInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

                                TextInput {
                                    id: startupCommandInput

                                    anchors {
                                        fill: parent
                                        margins: Config.scaled(6, root.uiScale)
                                    }
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    selectByMouse: true
                                    clip: true
                                    text: root.dropdownConsole ? root.dropdownConsole.startupCommand : ""

                                    // Saved on Enter or on leaving the box, like the
                                    // autokill delay. Only a console started after
                                    // that runs it.
                                    onEditingFinished: {
                                        if (!root.dropdownConsole) return
                                        root.dropdownConsole.setStartupCommand(startupCommandInput.text)
                                        startupCommandInput.text = root.dropdownConsole.startupCommand
                                    }
                                    onAccepted: startupCommandInput.focus = false
                                }
                            }

                            SettingHint {
                                uiScale: root.uiScale
                                indented: false
                                text: "Typed into every new terminal as it starts, e.g. cd ~/project && claude. A new one starts the first time the console opens, and after the last one ended."
                            }
                        }
                    }

                    // ---------------- Power category ----------------
                    // Idle.qml's settings: lock, dim and suspend, each counted
                    // from the stage before it when that one's on. It holds the
                    // boxes to their limits (a minute at least each, a dim
                    // opacity of 50-100%), and they show what it kept.
                    ColumnLayout {
                        id: powerCategoryContent

                        Layout.fillWidth: true
                        visible: root.currentCategory === 5
                        spacing: Config.scaled(10, root.uiScale)

                        readonly property bool ready: !!root.idle
                        readonly property bool autoLock: !!root.idle && root.idle.autoLock
                        readonly property bool autoDim: !!root.idle && root.idle.autoDim
                        readonly property bool autoSuspend: !!root.idle && root.idle.autoSuspend

                        // ---------------- Lockscreen ----------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(8, root.uiScale)
                            spacing: Config.scaled(4, root.uiScale)

                            Text {
                                text: "Lockscreen"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(16, root.uiScale)
                                font.bold: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Config.scaled(2, root.uiScale)
                                color: Config.fgcolor
                            }
                        }

                        CheckRow {
                            Layout.fillWidth: true
                            uiScale: root.uiScale
                            text: "Auto-lock"
                            checked: powerCategoryContent.autoLock
                            usable: powerCategoryContent.ready
                            onToggled: root.idle.setAutoLock(!root.idle.autoLock)
                        }

                        RowLayout {
                            id: lockDelayRow

                            Layout.fillWidth: true
                            Layout.leftMargin: Config.scaled(28, root.uiScale)
                            spacing: Config.scaled(8, root.uiScale)

                            readonly property color shownColor: powerCategoryContent.autoLock ? Config.fgcolor : Config.fgcolordark

                            Text {
                                text: "after"
                                color: lockDelayRow.shownColor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            NumberBox {
                                uiScale: root.uiScale
                                value: root.idle ? root.idle.lockMinutes : 10
                                usable: powerCategoryContent.autoLock
                                onCommitted: (value) => root.idle.setLockMinutes(value)
                            }

                            Text {
                                text: "minutes of inactivity"
                                color: lockDelayRow.shownColor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // A notification a minute before it locks - so only with a
                        // delay of 2 minutes or more.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Config.scaled(28, root.uiScale)
                            spacing: Config.scaled(8, root.uiScale)

                            CheckRow {
                                uiScale: root.uiScale
                                text: "Warn before auto-lock"
                                checked: !!root.idle && root.idle.lockWarning
                                usable: powerCategoryContent.autoLock
                                onToggled: root.idle.setLockWarning(!root.idle.lockWarning)
                            }

                            Text {
                                visible: !!root.idle && root.idle.lockMinutes < 2
                                text: "(needs 2 minutes or more)"
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(13, root.uiScale)
                            }

                            Item { Layout.fillWidth: true }
                        }

                        CheckRow {
                            Layout.fillWidth: true
                            uiScale: root.uiScale
                            text: "Show time"
                            checked: !!root.idle && root.idle.showTime
                            usable: powerCategoryContent.ready
                            onToggled: root.idle.setShowTime(!root.idle.showTime)
                        }

                        CheckRow {
                            Layout.fillWidth: true
                            uiScale: root.uiScale
                            text: "Show media player (if active)"
                            checked: !!root.idle && root.idle.showMedia
                            usable: powerCategoryContent.ready
                            onToggled: root.idle.setShowMedia(!root.idle.showMedia)
                        }

                        // ---------------- Dim ----------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(14, root.uiScale)
                            spacing: Config.scaled(4, root.uiScale)

                            Text {
                                text: "Dim"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(16, root.uiScale)
                                font.bold: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Config.scaled(2, root.uiScale)
                                color: Config.fgcolor
                            }
                        }

                        CheckRow {
                            Layout.fillWidth: true
                            uiScale: root.uiScale
                            text: "Auto-dim"
                            checked: !!root.idle && root.idle.autoDim
                            usable: powerCategoryContent.ready
                            onToggled: root.idle.setAutoDim(!root.idle.autoDim)
                        }

                        // Everything under Auto-dim: dark and locked while it's off.
                        ColumnLayout {
                            id: dimOptions

                            Layout.fillWidth: true
                            Layout.leftMargin: Config.scaled(28, root.uiScale)
                            spacing: Config.scaled(10, root.uiScale)

                            readonly property bool usable: powerCategoryContent.autoDim
                            readonly property color shownColor: dimOptions.usable ? Config.fgcolor : Config.fgcolordark

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Config.scaled(4, root.uiScale)

                                CheckRow {
                                    Layout.fillWidth: true
                                    uiScale: root.uiScale
                                    text: "Per monitor"
                                    checked: !!root.idle && root.idle.dimPerMonitor
                                    usable: dimOptions.usable
                                    onToggled: root.idle.setDimPerMonitor(!root.idle.dimPerMonitor)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Config.scaled(28, root.uiScale)
                                    wrapMode: Text.WordWrap
                                    text: "Every monitor dims after its own inactivity, without waiting for the lock - input while it has focus, or a window on it keeping the computer awake, counts."
                                    color: Config.fgcolorhint
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(12, root.uiScale)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "after"
                                    color: dimOptions.shownColor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                NumberBox {
                                    uiScale: root.uiScale
                                    value: root.idle ? root.idle.dimMinutes : 5
                                    usable: dimOptions.usable
                                    onCommitted: (value) => root.idle.setDimMinutes(value)
                                }

                                // Counted from the stage before it, when that one's on.
                                Text {
                                    text: root.idle ? root.idle.dimDelayLabel : ""
                                    color: dimOptions.shownColor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }

                        // The two below are how any dim looks - Manual dim's too -
                        // so they stay usable with auto-dim off.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(4, root.uiScale)

                            CheckRow {
                                Layout.fillWidth: true
                                uiScale: root.uiScale
                                text: "Show active monitors"
                                checked: !!root.idle && root.idle.dimShowActive
                                usable: powerCategoryContent.ready
                                onToggled: root.idle.setDimShowActive(!root.idle.dimShowActive)
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: Config.scaled(28, root.uiScale)
                                wrapMode: Text.WordWrap
                                text: "Names the monitors still in use on the dimmed ones - with Per monitor, or after a Manual dim."
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(12, root.uiScale)
                            }
                        }

                        // How dark the dimmed screens go: 50-100%.
                        ColumnLayout {
                            Layout.topMargin: Config.scaled(4, root.uiScale)
                            spacing: Config.scaled(6, root.uiScale)
                            enabled: powerCategoryContent.ready
                            opacity: enabled ? 1 : 0.35

                            RowLayout {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                Layout.fillWidth: false
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "Dim opacity:"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: (root.idle ? root.idle.dimOpacity : 100) + "%"
                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }
                            }

                            DeviceSlider {
                                Layout.preferredWidth: Config.scaled(420, root.uiScale)
                                uiScale: root.uiScale
                                value: root.idle ? (root.idle.dimOpacity - 50) / 50 : 1
                                onMoved: (newValue) => root.idle.setDimOpacity(50 + newValue * 50)
                            }
                        }

                        // ---------------- Suspend ----------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Config.scaled(14, root.uiScale)
                            spacing: Config.scaled(4, root.uiScale)

                            Text {
                                text: "Suspend"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(16, root.uiScale)
                                font.bold: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Config.scaled(2, root.uiScale)
                                color: Config.fgcolor
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.scaled(4, root.uiScale)

                            CheckRow {
                                Layout.fillWidth: true
                                uiScale: root.uiScale
                                text: "Auto-suspend"
                                checked: powerCategoryContent.autoSuspend
                                usable: powerCategoryContent.ready
                                onToggled: root.idle.setAutoSuspend(!root.idle.autoSuspend)
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: Config.scaled(28, root.uiScale)
                                wrapMode: Text.WordWrap
                                text: "Counts down on the main monitor before suspending - once every monitor is dimmed, or for the last 30 seconds without auto-dim, with the other monitors black. Any input calls it off."
                                color: Config.fgcolorhint
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(12, root.uiScale)
                            }
                        }

                        // Everything under Auto-suspend: dark and locked while it's off.
                        ColumnLayout {
                            id: suspendOptions

                            Layout.fillWidth: true
                            Layout.leftMargin: Config.scaled(28, root.uiScale)
                            spacing: Config.scaled(10, root.uiScale)

                            readonly property bool usable: powerCategoryContent.autoSuspend
                            readonly property color shownColor: suspendOptions.usable ? Config.fgcolor : Config.fgcolordark

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Config.scaled(8, root.uiScale)

                                Text {
                                    text: "after"
                                    color: suspendOptions.shownColor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                NumberBox {
                                    uiScale: root.uiScale
                                    value: root.idle ? root.idle.suspendMinutes : 30
                                    usable: suspendOptions.usable
                                    onCommitted: (value) => root.idle.setSuspendMinutes(value)
                                }

                                // Counted from the stage before it, when that one's on.
                                Text {
                                    text: root.idle ? root.idle.suspendDelayLabel : ""
                                    color: suspendOptions.shownColor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Config.scaled(4, root.uiScale)

                                CheckRow {
                                    Layout.fillWidth: true
                                    uiScale: root.uiScale
                                    text: "Wake up lock"
                                    checked: !!root.idle && root.idle.wakeUpLock
                                    usable: suspendOptions.usable && !(root.idle && root.idle.wakeUpLockForced)
                                    onToggled: root.idle.setWakeUpLock(!root.idle.wakeUpLock)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Config.scaled(28, root.uiScale)
                                    wrapMode: Text.WordWrap
                                    text: "Locks the screen before suspending, so the computer wakes up locked. Always on while auto-lock is."
                                    color: Config.fgcolorhint
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(12, root.uiScale)
                                }
                            }
                        }
                    }

                }
            }
        }
    }
}

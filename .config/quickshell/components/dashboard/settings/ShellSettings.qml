import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../../../Config.js" as Config

// Shell-level settings (as opposed to Sound/Network/Bluetooth/Display,
// which all configure a piece of hardware) - one tab of
// SettingsScreen.qml's fullscreen tabbed panel (see there for the tab
// bar/coordinator). Categories down the left ("Bar", "Peripherals",
// "Updater") mirror Network/Bluetooth's own left icon-tab strip, picking
// which group of settings shows on the right.
//
// Everything here is a plain, immediately-saved toggle - no Apply
// button, unlike ScreenSettings.qml's staged monitor edits - persisted
// to its own barsettings.json/peripheralsettings.json/updatersettings.json
// rather than monitors.json, so a Display tab Apply can never clobber a
// Bar/Peripherals/Updater setting (or vice versa) by overwriting the
// wrong file wholesale. WorkspaceRow.qml/WorkspaceOsd.qml/Bar.qml each
// watch barsettings.json directly for the same reason they already
// watched monitors.json - no property-passing chain needed.
// Peripherals' mouse sensitivity/solaar startup settings are instead
// replayed by ~/.config/hypr/scripts/apply-peripherals.sh from
// hyprland.lua's own autostart block (see that script), the same
// "small JSON file + startup replay" pattern apply-monitors.sh already
// established for monitors.json. Updater.qml watches updatersettings.json
// directly too, same decoupled pattern.
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false

    anchors.fill: parent

    // 0 = Bar, 1 = Peripherals, 2 = Updater.
    property int currentCategory: 0

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

    function toggleStrictWorkspaceWidget() { root.setBarSetting("strictWorkspaceWidget", !root.strictWorkspaceWidget) }
    function toggleShowEmptyWidget() { root.setBarSetting("showEmptyWidget", !root.showEmptyWidget) }
    function toggleShowEmptyOsd() { root.setBarSetting("showEmptyOsd", !root.showEmptyOsd) }
    function toggleShowBrightnessControl() { root.setBarSetting("showBrightnessControl", !root.showBrightnessControl) }
    function toggleShowUpdater() { root.setBarSetting("showUpdater", !root.showUpdater) }

    // ---------------- Peripherals ----------------
    property var peripheralsStore: ({})

    function loadPeripheralsStore() {
        peripheralsStoreProcess.running = false
        peripheralsStoreProcess.running = true
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

    function toggleHighlightOnUpdates() { root.setUpdaterSetting("highlightOnUpdates", !root.highlightOnUpdates) }

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

    // Write-only, same reasoning as barSettingsFile above - nothing else
    // in the running shell reads peripheralsettings.json back, only
    // apply-peripherals.sh at the next Hyprland startup.
    FileView {
        id: peripheralsSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/peripheralsettings.json"
        preload: false
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

    // Debounced real apply for the sensitivity slider - see
    // stagedSensitivity's own comment above for why. `hyprctl eval`, not
    // `keyword` - this config is parsed by hyprlang's Lua frontend, which
    // rejects `keyword` outright (see apply-monitors.sh's own comment for
    // the same reasoning), so re-invoking the same hl.config({ input =
    // {...} }) call hyprland.lua's static config used at parse time is
    // the only working live-apply path here too.
    Timer {
        id: sensitivityApplyTimer
        interval: 330
        repeat: false
        onTriggered: {
            root.setPeripheralSetting("mouseSensitivity", root.stagedSensitivity)
            sensitivityApplyProcess.command = ["hyprctl", "eval", "hl.config({ input = { sensitivity = " + root.stagedSensitivity + " } })"]
            sensitivityApplyProcess.running = false
            sensitivityApplyProcess.running = true
        }
    }

    Process {
        id: sensitivityApplyProcess
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
                        text: "Bar"
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
                        text: "Peripherals"
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

                Item { Layout.fillHeight: true }
            }

            // ---------------- divider ----------------
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.fillHeight: true
                color: Config.fgcolor
            }

            // ---------------- RIGHT: current category's settings ----------------
            ColumnLayout {
                id: categoryContent

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Config.scaled(10, root.uiScale)

                Text {
                    text: ["Bar", "Peripherals", "Updater"][root.currentCategory]
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                // ---------------- Bar category ----------------
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

                    Text {
                        text: "Only managed workspaces in widget:"
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

                    Item { Layout.fillWidth: true }
                }

                // ---------------- show empty workspaces (widget + osd) ----------------
                RowLayout {
                    Layout.fillWidth: true
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
                        text: "In widget"
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

                    Item { Layout.preferredWidth: Config.scaled(16, root.uiScale) }

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
                        text: "In OSD"
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

                // ---------------- brightness control ----------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Brightness Control:"
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

                    Item { Layout.fillWidth: true }
                }

                // ---------------- show updater ----------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Show Updater:"
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

                    Item { Layout.fillWidth: true }
                }

                } // barCategoryContent

                // ---------------- Peripherals category ----------------
                ColumnLayout {
                    id: peripheralsCategoryContent

                    Layout.fillWidth: true
                    visible: root.currentCategory === 1
                    spacing: Config.scaled(10, root.uiScale)

                    // ---------------- solaar startup ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Config.scaled(8, root.uiScale)
                        spacing: Config.scaled(8, root.uiScale)

                        Text {
                            text: "Solaar Startup:"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleSolaarStartup()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: Config.scaled(20, root.uiScale)
                            Layout.preferredHeight: Config.scaled(20, root.uiScale)
                            color: root.solaarStartupEnabled ? Config.fgcolor : Config.fillcolor
                            border.width: Config.scaled(2, root.uiScale)
                            border.color: Config.fgcolor
                            radius: 0

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleSolaarStartup()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // ---------------- mouse sensitivity ----------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Config.scaled(4, root.uiScale)
                        spacing: Config.scaled(6, root.uiScale)

                        RowLayout {
                            Layout.fillWidth: true
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
                            Layout.fillWidth: true
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

                        Text {
                            text: "Highlight Button When Updates Available:"
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

                        Item { Layout.fillWidth: true }
                    }

                    // ---------------- update check interval ----------------
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Config.scaled(4, root.uiScale)
                        spacing: Config.scaled(8, root.uiScale)

                        Text {
                            text: "Update Check Interval (minutes):"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

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
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}

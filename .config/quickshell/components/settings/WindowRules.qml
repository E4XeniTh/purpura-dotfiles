import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import "../../Config.js" as Config
import "../common"
import "controls"
import "WindowRulesLogic.js" as Logic

// Settings > General > Windows: how apps look as they start and open - one
// rule per app, in two sections.
//
// Apps: every app with a rule - kitty's floating window comes pre-included -
// each with a line on what its rule does. Pick one to change it, or remove
// it; add one that's open now, or one that isn't, by its window class.
//
// How <app> opens: the picked app's rule - as it likes, tiled, floating (at a
// size, centered), maximized or fullscreen; how see-through; and the
// animation it opens with.
//
// Each change is saved as it's made - windowrules.json here (this category's
// source of truth) and hypr/windowrules.lua for Hyprland's next load - and
// handed straight to Hyprland through `hyprctl eval`, as
// purpura.windowRules({ ... }) (see purpura.lua's How apps open). How a rule
// opens a window, and at what size, is for windows as they open (Hyprland's
// static effects); its opacity and animation reach those open now too (its
// dynamic ones). Nothing's written until something's changed; until then kitty's
// rule is hyprland.lua's own "kittyrule", which the list takes kitty's size
// from.
ColumnLayout {
    id: root

    property real uiScale: 1.0
    property bool active: false

    property var rules: []
    property bool loaded: false
    property string selectedApp: ""
    property string applyError: ""
    // The opacity slider's spot while it's dragged; saved once it's let go.
    property real draggedOpacity: -1

    readonly property var selectedRule: root.rules.find(r => r.app === root.selectedApp) || null
    readonly property bool floating: !!root.selectedRule && root.selectedRule.layout === "float"
    readonly property real shownOpacity: root.draggedOpacity >= 0 ? root.draggedOpacity
        : (root.selectedRule ? root.selectedRule.opacity : 1)
    readonly property real labelWidth: Config.scaled(96, root.uiScale)

    spacing: Config.scaled(10, root.uiScale)

    function load() {
        storeProcess.running = false
        storeProcess.running = true
        Hyprland.refreshToplevels()
    }

    onActiveChanged: if (root.active) root.load()
    Component.onCompleted: root.load()

    // Nothing's picked until an app's clicked (or added): none at first, and none
    // once the one picked is removed.
    function show(list) {
        root.rules = list
        root.loaded = true
        if (!list.some(r => r.app === root.selectedApp)) root.selectedApp = ""
    }

    function save(list) {
        root.show(list)
        storeFile.setText(JSON.stringify({ rules: list }, null, 2) + "\n")
        hyprFile.setText(Logic.fileText(list))
        root.apply(["hyprctl", "eval", "purpura.windowRules(" + Logic.luaList(list) + ")"])
    }

    function change(app, fields) {
        root.save(root.rules.map(r => r.app === app ? Logic.normalize(Object.assign({}, r, fields)) : r))
    }

    function addApp(app) {
        const name = String(app || "").trim()
        if (!Logic.validApp(name)) return
        if (!root.rules.some(r => r.app === name)) root.save(root.rules.concat([Logic.normalize({ app: name })]))
        root.selectedApp = name
    }

    function addTyped() {
        const name = classInput.text.trim()
        if (!Logic.validApp(name)) return
        root.addApp(name)
        classInput.text = ""
    }

    function removeApp(app) {
        root.save(root.rules.filter(r => r.app !== app))
    }

    // One eval at a time, in order: each hands over the whole list, so the
    // last one sent is the one that counts.
    property var pendingApply: null

    function apply(command) {
        if (applyProcess.running) {
            root.pendingApply = command
            return
        }
        applyProcess.command = command
        applyProcess.running = true
    }

    // The app's own name and icon, from its .desktop file - the class itself
    // when there's none. The same lookups as WorkspaceRow.qml's.
    function entryOf(app) {
        const entry = DesktopEntries.heuristicLookup(app)
        if (entry) return entry
        const lower = app.toLowerCase()
        return DesktopEntries.applications.values.find(e => e.id.toLowerCase().includes(lower)) || null
    }

    function nameOf(app) {
        const entry = root.entryOf(app)
        return entry && entry.name ? entry.name : app
    }

    function iconOf(app) {
        const entry = root.entryOf(app)
        return Quickshell.iconPath(entry && entry.icon ? entry.icon : app, "application-x-executable")
    }

    // The apps open now that have no rule yet, by name.
    readonly property var openApps: {
        const seen = {}
        const out = []
        for (const toplevel of Hyprland.toplevels.values) {
            const ipc = toplevel.lastIpcObject || {}
            const app = String(ipc.initialClass || ipc.class || "")
            if (!Logic.validApp(app) || seen[app] || root.rules.some(r => r.app === app)) continue
            seen[app] = true
            out.push(app)
        }
        return out.sort((a, b) => root.nameOf(a).localeCompare(root.nameOf(b)))
    }
    property int pickedOpen: 0

    // Read via `cat`, as the other settings are: no file yet gives nothing.
    Process {
        id: storeProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/windowrules.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                const list = Logic.parseStore(text)
                if (list) {
                    root.show(list)
                } else {
                    hyprlandProcess.running = false
                    hyprlandProcess.running = true
                }
            }
        }
    }

    // Before anything's been changed here: kitty's, at the size hyprland.lua's
    // kittyrule gives it.
    Process {
        id: hyprlandProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"]

        stdout: StdioCollector {
            onStreamFinished: root.show(Logic.defaults(text))
        }
    }

    FileView {
        id: storeFile
        path: Quickshell.env("HOME") + "/.config/quickshell/windowrules.json"
        preload: false
    }

    FileView {
        id: hyprFile
        path: Quickshell.env("HOME") + "/.config/hypr/windowrules.lua"
        preload: false
    }

    // What Hyprland says to a rejected list, shown under the rule: eval replies
    // "ok" when all went well, and otherwise with what didn't - a field
    // hl.window_rule turned down included (it reports those rather than
    // stopping), or hyprctl's own reply when Hyprland can't be reached.
    Process {
        id: applyProcess

        stdout: StdioCollector {
            onStreamFinished: {
                const output = text.trim()
                root.applyError = output === "" || output === "ok" ? "" : output
            }
        }

        onExited: {
            if (!root.pendingApply) return
            const next = root.pendingApply
            root.pendingApply = null
            applyProcess.command = next
            applyProcess.running = true
        }
    }

    // ---------------- Apps ----------------
    SectionHeader {
        Layout.topMargin: Config.scaled(8, root.uiScale)
        uiScale: root.uiScale
        text: "Apps"
    }

    SettingHint {
        Layout.topMargin: -Config.scaled(4, root.uiScale)
        uiScale: root.uiScale
        indented: false
        text: "Pick an app to set how it looks as it starts and opens, or add one below."
    }

    Repeater {
        model: root.rules

        DashCard {
            id: appRow

            required property var modelData
            readonly property bool picked: appRow.modelData.app === root.selectedApp

            Layout.fillWidth: true
            Layout.preferredHeight: Config.scaled(42, root.uiScale)
            uiScale: root.uiScale
            color: rowMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
            border.color: appRow.picked ? Config.fgcolorlight : Config.fgcolor

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selectedApp = appRow.modelData.app
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Config.scaled(10, root.uiScale)
                    rightMargin: Config.scaled(5, root.uiScale)
                }
                spacing: Config.scaled(10, root.uiScale)

                IconImage {
                    implicitSize: Config.scaled(22, root.uiScale)
                    source: root.iconOf(appRow.modelData.app)
                }

                Text {
                    text: root.nameOf(appRow.modelData.app)
                    color: appRow.picked ? Config.fgcolorlight : Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(13, root.uiScale)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: Logic.summary(appRow.modelData)
                    elide: Text.ElideRight
                    color: Config.fgcolorhint
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, root.uiScale)
                }

                ActionButton {
                    Layout.preferredHeight: Config.scaled(30, root.uiScale)
                    uiScale: root.uiScale
                    text: "Remove"
                    danger: true
                    onClicked: root.removeApp(appRow.modelData.app)
                }
            }
        }
    }

    Text {
        visible: root.loaded && root.rules.length === 0
        text: "No apps yet - add one below."
        color: Config.fgcolorhint
        font.family: Config.fontfamily
        font.pixelSize: Config.scaled(13, root.uiScale)
    }

    // Adding one: open now...
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Config.scaled(4, root.uiScale)
        spacing: Config.scaled(8, root.uiScale)

        Text {
            Layout.preferredWidth: Config.scaled(150, root.uiScale)
            text: "Add an open app:"
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }

        DropdownBox {
            id: openPicker

            Layout.preferredWidth: Config.scaled(240, root.uiScale)
            uiScale: root.uiScale
            enabled: root.openApps.length > 0
            options: root.openApps.length > 0 ? root.openApps.map(app => root.nameOf(app)) : ["No other apps open"]
            currentIndex: Math.min(root.pickedOpen, Math.max(0, root.openApps.length - 1))
            maxVisibleRows: 8
            onActivated: (index) => root.pickedOpen = index
        }

        ActionButton {
            uiScale: root.uiScale
            text: "Add"
            enabled: root.openApps.length > 0
            onClicked: root.addApp(root.openApps[openPicker.currentIndex])
        }

        Item { Layout.fillWidth: true }
    }

    // ...or not, by its class.
    RowLayout {
        Layout.fillWidth: true
        spacing: Config.scaled(8, root.uiScale)

        Text {
            Layout.preferredWidth: Config.scaled(150, root.uiScale)
            text: "Or by its class:"
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }

        Rectangle {
            Layout.preferredWidth: Config.scaled(240, root.uiScale)
            Layout.preferredHeight: Config.scaled(28, root.uiScale)
            color: Config.fillcolor
            border.width: Config.scaled(2, root.uiScale)
            border.color: classInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

            TextInput {
                id: classInput

                anchors.fill: parent
                anchors.leftMargin: Config.scaled(8, root.uiScale)
                anchors.rightMargin: Config.scaled(8, root.uiScale)
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Config.fgcolor
                selectionColor: Config.fgcolorhover
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                maximumLength: 128
                validator: RegularExpressionValidator { regularExpression: /^[A-Za-z0-9._+ -]*$/ }
                onAccepted: root.addTyped()
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Config.scaled(8, root.uiScale)
                anchors.verticalCenter: parent.verticalCenter
                visible: classInput.text.length === 0
                text: "kitty, org.kde.dolphin..."
                color: Config.fgcolorhint
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
            }
        }

        ActionButton {
            uiScale: root.uiScale
            text: "Add"
            enabled: Logic.validApp(classInput.text.trim()) && !root.rules.some(r => r.app === classInput.text.trim())
            onClicked: root.addTyped()
        }

        Item { Layout.fillWidth: true }
    }

    SettingHint {
        Layout.topMargin: -Config.scaled(4, root.uiScale)
        uiScale: root.uiScale
        indented: false
        text: "An app that isn't open goes by its windows' class, as `hyprctl clients` lists it."
    }

    // ---------------- How it opens ----------------
    // Only once an app's picked above: the hint up there says to.
    SectionHeader {
        Layout.topMargin: Config.scaled(14, root.uiScale)
        visible: !!root.selectedRule
        uiScale: root.uiScale
        text: root.selectedRule ? "How " + root.nameOf(root.selectedApp) + " opens" : ""
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !!root.selectedRule
        spacing: Config.scaled(10, root.uiScale)

        // ---------------- opens as ----------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Config.scaled(8, root.uiScale)

            Text {
                Layout.preferredWidth: root.labelWidth
                text: "Opens as:"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            Repeater {
                model: Logic.LAYOUTS

                ActionButton {
                    required property var modelData

                    uiScale: root.uiScale
                    text: modelData.label
                    lit: !!root.selectedRule && root.selectedRule.layout === modelData.value
                    onClicked: root.change(root.selectedApp, { layout: modelData.value })
                }
            }

            Item { Layout.fillWidth: true }
        }

        SettingHint {
            Layout.topMargin: -Config.scaled(6, root.uiScale)
            Layout.leftMargin: root.labelWidth + Config.scaled(8, root.uiScale)
            uiScale: root.uiScale
            indented: false
            text: "As it likes leaves it to the app. Maximized counts only beside other windows: one alone on its workspace isn't let be maximized. Opening fullscreen, it gets an empty workspace of its own when Create Workspace For Fullscreen Apps (Shell > Main Bar) is on."
        }

        // ---------------- size, centered (floating) ----------------
        RowLayout {
            id: sizeRow

            Layout.fillWidth: true
            spacing: Config.scaled(8, root.uiScale)

            readonly property color shownColor: root.floating ? Config.fgcolor : Config.fgcolordark

            Text {
                Layout.preferredWidth: root.labelWidth
                text: "Size:"
                color: sizeRow.shownColor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            NumberBox {
                uiScale: root.uiScale
                value: root.selectedRule ? root.selectedRule.width : Logic.KITTY_WIDTH
                usable: root.floating
                onCommitted: (value) => root.change(root.selectedApp, { width: value })
            }

            Text {
                text: "×"
                color: sizeRow.shownColor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            NumberBox {
                uiScale: root.uiScale
                value: root.selectedRule ? root.selectedRule.height : Logic.KITTY_HEIGHT
                usable: root.floating
                onCommitted: (value) => root.change(root.selectedApp, { height: value })
            }

            Text {
                text: "pixels"
                color: sizeRow.shownColor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            Item { Layout.fillWidth: true }
        }

        CheckRow {
            Layout.fillWidth: true
            Layout.leftMargin: root.labelWidth + Config.scaled(8, root.uiScale)
            uiScale: root.uiScale
            text: "Centered on screen"
            checked: !!root.selectedRule && root.selectedRule.center
            usable: root.floating
            onToggled: root.change(root.selectedApp, { center: !root.selectedRule.center })
        }

        SettingHint {
            Layout.topMargin: -Config.scaled(6, root.uiScale)
            Layout.leftMargin: root.labelWidth + Config.scaled(8, root.uiScale)
            uiScale: root.uiScale
            indented: false
            text: "For a floating window: its size as it opens, " + Logic.MIN_SIZE + " pixels at least each way."
        }

        // ---------------- opacity ----------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Config.scaled(8, root.uiScale)

            Text {
                Layout.preferredWidth: root.labelWidth
                text: "Opacity:"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            // 10 - 100%, in steps of 5.
            DeviceSlider {
                Layout.preferredWidth: Config.scaled(300, root.uiScale)
                uiScale: root.uiScale
                value: (root.shownOpacity - 0.1) / 0.9
                onMoved: (newValue) => root.draggedOpacity = Logic.clampOpacity(0.1 + newValue * 0.9)
                onReleased: {
                    if (root.draggedOpacity < 0) return
                    const opacity = root.draggedOpacity
                    root.draggedOpacity = -1
                    root.change(root.selectedApp, { opacity: opacity })
                }
            }

            Text {
                text: Math.round(root.shownOpacity * 100) + "%"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            Item { Layout.fillWidth: true }
        }

        SettingHint {
            Layout.topMargin: -Config.scaled(6, root.uiScale)
            Layout.leftMargin: root.labelWidth + Config.scaled(8, root.uiScale)
            uiScale: root.uiScale
            indented: false
            text: "How see-through its windows are - the ones open now change too."
        }

        // ---------------- animation ----------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Config.scaled(8, root.uiScale)

            Text {
                Layout.preferredWidth: root.labelWidth
                text: "Animation:"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
                font.bold: true
            }

            DropdownBox {
                Layout.preferredWidth: Config.scaled(160, root.uiScale)
                uiScale: root.uiScale
                options: Logic.ANIMATIONS.map(a => a.label)
                currentIndex: Logic.indexIn(Logic.ANIMATIONS, root.selectedRule ? root.selectedRule.animation : "")
                onActivated: (index) => root.change(root.selectedApp, { animation: Logic.ANIMATIONS[index].value })
            }

            Item { Layout.fillWidth: true }
        }

        SettingHint {
            Layout.topMargin: -Config.scaled(6, root.uiScale)
            Layout.leftMargin: root.labelWidth + Config.scaled(8, root.uiScale)
            uiScale: root.uiScale
            indented: false
            text: "How its windows come up: Default is hyprland.lua's, the same for every window."
        }

        Text {
            Layout.fillWidth: true
            visible: root.applyError !== ""
            text: "Hyprland didn't take it: " + root.applyError
            wrapMode: Text.Wrap
            color: Config.fgcolorred
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(12, root.uiScale)
        }

        SettingHint {
            Layout.topMargin: Config.scaled(4, root.uiScale)
            uiScale: root.uiScale
            indented: false
            text: "How it opens and its size are for windows as they open: ones open now keep theirs."
        }
    }
}

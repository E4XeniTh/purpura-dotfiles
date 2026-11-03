import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "../../../Config.js" as Config

// Settings > Shortcuts: a full-size keyboard as wide as the tab and centered
// in its height, one rectangle per key. Clicking a key opens a panel listing
// its binds, each removable, with a + button that reveals the form for adding
// a new one.
//
// A key's border shows its state, across all modifiers: fgcolordark when
// unused, fgcolor when bound, fgcolorlight when one of its binds has a
// description, which also shows in a hint while the key is hovered.
//
// The bound keys come from `hyprctl binds -j`, so binds written by hand in
// hyprland.lua show up too. What's changed here is saved to shortcuts.json
// (the source of truth for this tab) and turned into hypr/shortcuts.lua,
// which hyprland.lua loads after its own binds, so a change survives
// reloads and restarts. It's also applied right away through `hyprctl eval`
// rather than a reload, because a reload reverts runtime-only state such as
// the monitor layout.
//
// Removing or replacing a hyprland.lua bind can't edit that file, so the
// combo goes on shortcuts.json's `removed` list, which shortcuts.lua
// unbinds. Hyprland's hl.unbind is case-sensitive, so that list keeps each
// combo exactly as hyprctl reported it.
//
// Descriptions set in hyprland.lua (hl.bind's `description` option) are read
// from hyprctl. One edited here is kept in shortcuts.json by combo and wins
// over that, an empty one included, so a hyprland.lua bind can be changed
// without being rebound.
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false

    anchors.fill: parent

    // ---------------- layout ----------------
    // Croatian QWERTZ on an ISO board (hyprland.lua's kb_layout). `sym` is
    // the keysym name Hyprland binds by, so another layout needs its own
    // symbols here. Sizes and positions are in key units.
    readonly property real keyboardUnitsWide: 22.5
    readonly property real keyboardUnitsTall: 6.25

    readonly property var keys: {
        const out = []

        // Lays a row out left to right. A number is a gap; a bare string is
        // both label and keysym; otherwise [label, sym, width, height].
        function row(startX, y, items) {
            let x = startX
            for (const item of items) {
                if (typeof item === "number") {
                    x += item
                    continue
                }
                const k = typeof item === "string" ? [item, item] : item
                const w = k[2] || 1
                out.push({ label: k[0], sym: k[1], x: x, y: y, w: w, h: k[3] || 1 })
                x += w
            }
        }

        // Main block
        row(0, 0, [["Esc", "Escape"], 1, "F1", "F2", "F3", "F4", 0.5, "F5", "F6", "F7", "F8", 0.5, "F9", "F10", "F11", "F12"])
        row(0, 1.25, [["¸", "grave"], "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ["'", "apostrophe"], ["+", "plus"], ["Backspace", "BackSpace", 2]])
        row(0, 2.25, [["Tab", "Tab", 1.75], "Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", ["Š", "scaron"], ["Đ", "dstroke"], ["Enter", "Return", 1.25, 2]])
        row(0, 3.25, [["Caps", "Caps_Lock", 1.75], "A", "S", "D", "F", "G", "H", "J", "K", "L", ["Č", "ccaron"], ["Ć", "cacute"], ["Ž", "zcaron"]])
        row(0, 4.25, [["Shift", "Shift_L", 1.25], ["<", "less"], "Y", "X", "C", "V", "B", "N", "M", [",", "comma"], [".", "period"], ["-", "minus"], ["Shift", "Shift_R", 2.75]])
        row(0, 5.25, [["Ctrl", "Control_L", 1.25], ["Super", "Super_L", 1.25], ["Alt", "Alt_L", 1.25], ["Space", "space", 6.25], ["AltGr", "ISO_Level3_Shift", 1.25], ["Super", "Super_R", 1.25], ["Menu", "Menu", 1.25], ["Ctrl", "Control_R", 1.25]])

        // Navigation block
        row(15.25, 0, [["Print", "Print"], ["Scroll", "Scroll_Lock"], ["Pause", "Pause"]])
        row(15.25, 1.25, [["Ins", "Insert"], ["Home", "Home"], ["PgUp", "Page_Up"]])
        row(15.25, 2.25, [["Del", "Delete"], ["End", "End"], ["PgDn", "Page_Down"]])
        row(16.25, 4.25, [["↑", "Up"]])
        row(15.25, 5.25, [["←", "Left"], ["↓", "Down"], ["→", "Right"]])

        // Numpad
        row(18.5, 1.25, [["Num", "Num_Lock"], ["/", "KP_Divide"], ["*", "KP_Multiply"], ["-", "KP_Subtract"]])
        row(18.5, 2.25, [["7", "KP_7"], ["8", "KP_8"], ["9", "KP_9"], ["+", "KP_Add", 1, 2]])
        row(18.5, 3.25, [["4", "KP_4"], ["5", "KP_5"], ["6", "KP_6"]])
        row(18.5, 4.25, [["1", "KP_1"], ["2", "KP_2"], ["3", "KP_3"], ["Enter", "KP_Enter", 1, 2]])
        row(18.5, 5.25, [["0", "KP_0", 2], [",", "KP_Separator"]])

        return out
    }

    // ---------------- actions offered for a new bind ----------------
    readonly property var actions: [
        { label: "Run command", command: true },
        { label: "Close window", lua: "hl.dsp.window.close()" },
        { label: "Toggle floating", lua: "hl.dsp.window.float({ action = \"toggle\" })" },
        { label: "Maximize", lua: "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })" },
        { label: "Fullscreen", lua: "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })" },
        { label: "Go to workspace", workspace: "hl.dsp.focus({ workspace = %1 })" },
        { label: "Move window to workspace", workspace: "hl.dsp.window.move({ workspace = %1, follow = false })" },
        { label: "Lock screen", lua: "hl.dsp.global(\"quickshell:lockscreen\")" },
        { label: "Power menu", lua: "hl.dsp.global(\"quickshell:powermenu\")" },
        { label: "Clipboard", lua: "hl.dsp.global(\"quickshell:clipboard\")" },
        { label: "Notifications", lua: "hl.dsp.global(\"quickshell:notifications\")" },
        { label: "Dashboard", lua: "hl.dsp.global(\"quickshell:dashboard\")" },
        { label: "Settings", lua: "hl.dsp.global(\"quickshell:settingsscreen\")" },
        { label: "Screenshot", lua: "hl.dsp.global(\"quickshell:screenshot\")" }
    ]
    readonly property var actionLabels: root.actions.map(a => a.label)
    readonly property var workspaceLabels: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
    readonly property var modifierNames: ["SUPER", "CTRL", "ALT", "SHIFT"]

    // ---------------- binds ----------------
    // { binds: [{ combo, key, label, lua }], removed: [combo],
    //   descriptions: { comboKey: text } }
    property var store: ({ binds: [], removed: [], descriptions: {} })
    // Parsed `hyprctl binds -j`.
    property var liveBinds: []
    property string applyError: ""

    function comboKey(combo) {
        const parts = combo.split("+").map(p => p.trim().toLowerCase())
        const key = parts.pop()
        return parts.sort().concat([key]).join("+")
    }

    function comboFromLive(bind) {
        const bits = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"], [2, "CAPS"], [16, "MOD2"], [32, "MOD3"], [128, "MOD5"]]
        const parts = bits.filter(b => bind.modmask & b[0]).map(b => b[1])
        parts.push(bind.key)
        return parts.join(" + ")
    }

    function descriptionFromLive(bind) {
        return bind.has_description === false ? "" : (bind.description || "")
    }

    function labelFromLive(bind) {
        const dispatcher = bind.dispatcher || ""
        if (dispatcher.length === 0 || dispatcher.startsWith("__")) return "Set in hyprland.lua"
        return (dispatcher + " " + (bind.arg || "")).trim()
    }

    // Everything bound right now: this tab's own binds, then whatever else
    // Hyprland reports. Own binds stay listed even if hyprctl can't be read.
    readonly property var allBinds: {
        const notes = root.store.descriptions
        const own = root.store.binds.map(b => ({
            combo: b.combo,
            key: b.key,
            label: b.label,
            description: notes[root.comboKey(b.combo)] || "",
            own: true
        }))
        const seen = {}
        for (const b of own) seen[root.comboKey(b.combo)] = true

        const others = []
        for (const b of root.liveBinds) {
            if (!b.key || b.mouse || b.catch_all || b.submap) continue
            const combo = root.comboFromLive(b)
            const id = root.comboKey(combo)
            if (seen[id]) continue
            seen[id] = true
            others.push({
                combo: combo,
                key: b.key,
                label: root.labelFromLive(b),
                description: notes[id] !== undefined ? notes[id] : root.descriptionFromLive(b),
                own: false
            })
        }
        return own.concat(others)
    }

    readonly property var boundKeys: {
        const found = {}
        for (const b of root.allBinds) found[b.key.toLowerCase()] = true
        return found
    }

    readonly property var describedKeys: {
        const found = {}
        for (const b of root.allBinds) {
            if (b.description) found[b.key.toLowerCase()] = true
        }
        return found
    }

    // The key under the mouse and what its hint shows, one line per described
    // bind.
    property var hoveredKey: null
    readonly property var hoveredHintLines: {
        if (!root.hoveredKey) return []
        const sym = root.hoveredKey.sym.toLowerCase()
        return root.allBinds
            .filter(b => b.description && b.key.toLowerCase() === sym)
            .map(b => b.combo + ": " + b.description)
    }

    // The key whose panel is open; null when closed.
    property var selectedKey: null
    readonly property var selectedBinds: root.selectedKey
        ? root.allBinds.filter(b => b.key.toLowerCase() === root.selectedKey.sym.toLowerCase())
        : []

    // New-bind form, hidden until the panel's + button is clicked.
    property bool formOpen: false
    property var formModifiers: ["SUPER"]
    property int formAction: 0
    property int formWorkspace: 0
    readonly property var formActionEntry: root.actions[root.formAction]
    readonly property string formCombo: root.selectedKey ? root.modifierNames
        .filter(m => root.formModifiers.indexOf(m) !== -1)
        .concat([root.selectedKey.sym])
        .join(" + ") : ""
    readonly property var formConflict: root.selectedBinds.find(b => root.comboKey(b.combo) === root.comboKey(root.formCombo)) || null
    // A taken combo with no command typed keeps its action, so a bind can
    // get a description without being set up again.
    readonly property bool formDescriptionOnly: !!root.formConflict && !!root.formActionEntry.command && commandInput.text.trim().length === 0
    readonly property bool formValid: !root.formActionEntry.command || commandInput.text.trim().length > 0 || root.formDescriptionOnly

    // What the description field was last filled with, so moving to another
    // combo clears that but keeps anything typed by hand.
    property string prefilledDescription: ""

    function syncDescription() {
        const bind = root.allBinds.find(b => root.comboKey(b.combo) === root.comboKey(root.formCombo))
        const existing = bind ? bind.description : ""
        if (existing.length > 0 || descriptionInput.text === root.prefilledDescription) {
            descriptionInput.text = existing
            root.prefilledDescription = existing
        }
    }

    onFormComboChanged: root.syncDescription()

    function openKey(key) {
        root.formOpen = false
        root.selectedKey = key
        panel.forceActiveFocus()
    }

    function openForm() {
        root.formModifiers = ["SUPER"]
        root.formAction = 0
        root.formWorkspace = 0
        commandInput.text = ""
        descriptionInput.text = ""
        root.prefilledDescription = ""
        root.syncDescription()
        root.formOpen = true
        if (root.formConflict) descriptionInput.focusInput()
        else commandInput.focusInput()
    }

    function closeForm() {
        root.formOpen = false
        panel.forceActiveFocus()
    }

    function closeKey() {
        root.selectedKey = null
        root.forceActiveFocus()
    }

    function toggleModifier(name) {
        root.formModifiers = root.formModifiers.indexOf(name) === -1
            ? root.formModifiers.concat([name])
            : root.formModifiers.filter(m => m !== name)
    }

    // Double-quoted JSON strings are valid Lua strings once control
    // characters, whose \u escapes differ in Lua, are gone.
    function luaString(text) {
        return JSON.stringify(text.replace(/[\x00-\x1f\x7f]/g, ""))
    }

    function submitForm() {
        if (!root.formValid) return
        const description = descriptionInput.text.trim()
        if (root.formDescriptionOnly) {
            const descriptions = Object.assign({}, root.store.descriptions)
            descriptions[root.comboKey(root.formCombo)] = description
            root.saveStore(Object.assign({}, root.store, { descriptions: descriptions }))
            root.closeKey()
            return
        }
        const entry = root.formActionEntry
        let label = entry.label
        let lua = entry.lua
        if (entry.command) {
            const command = commandInput.text.trim()
            label = "Run: " + command
            lua = "hl.dsp.exec_cmd(" + root.luaString(command) + ")"
        } else if (entry.workspace) {
            const workspace = root.workspaceLabels[root.formWorkspace]
            label = entry.label + " " + workspace
            lua = entry.workspace.replace("%1", workspace)
        }
        root.addBind(root.formCombo, root.selectedKey.sym, label, lua, description)
        root.closeKey()
    }

    // The descriptions map with this combo's set, or dropped when empty.
    function withDescription(combo, description) {
        const next = Object.assign({}, root.store.descriptions)
        if (description.length > 0) next[root.comboKey(combo)] = description
        else delete next[root.comboKey(combo)]
        return next
    }

    function addBind(combo, key, label, lua, description) {
        const id = root.comboKey(combo)
        const replaced = root.allBinds.filter(b => root.comboKey(b.combo) === id)
        const removed = root.store.removed.slice()
        for (const b of replaced) {
            if (!b.own && removed.indexOf(b.combo) === -1) removed.push(b.combo)
        }
        const binds = root.store.binds.filter(b => root.comboKey(b.combo) !== id)
        binds.push({ combo: combo, key: key, label: label, lua: lua })

        root.saveStore({ binds: binds, removed: removed, descriptions: root.withDescription(combo, description) })
        const unbinds = replaced.map(b => "hl.unbind(" + root.luaString(b.combo) + ")")
        root.applyLive(unbinds.concat(["hl.bind(" + root.luaString(combo) + ", " + lua + ")"]))
    }

    function removeBind(bind) {
        const removed = root.store.removed.slice()
        if (!bind.own && removed.indexOf(bind.combo) === -1) removed.push(bind.combo)
        const binds = root.store.binds.filter(b => b.combo !== bind.combo)

        root.saveStore({ binds: binds, removed: removed, descriptions: root.withDescription(bind.combo, "") })
        root.applyLive(["hl.unbind(" + root.luaString(bind.combo) + ")"])
        root.syncDescription()
    }

    function saveStore(next) {
        root.store = next
        storeFile.setText(JSON.stringify(next, null, 2) + "\n")

        const lines = ["-- Generated by Settings > Shortcuts from quickshell/shortcuts.json - edits here get overwritten."]
        for (const combo of next.removed) lines.push("hl.unbind(" + root.luaString(combo) + ")")
        for (const b of next.binds) lines.push("hl.bind(" + root.luaString(b.combo) + ", " + b.lua + ")")
        luaFile.setText(lines.join("\n") + "\n")
    }

    function applyLive(statements) {
        root.applyQueue.push(statements.join("; "))
        root.applyNext()
    }

    // One at a time: restarting the Process would kill a running eval and
    // lose that change until the next reload.
    property var applyQueue: []

    function applyNext() {
        if (applyProcess.running || root.applyQueue.length === 0) return
        root.applyError = ""
        applyProcess.command = ["hyprctl", "eval", root.applyQueue.shift()]
        applyProcess.running = true
    }

    function refresh() {
        storeProcess.running = false
        storeProcess.running = true
        bindsProcess.running = false
        bindsProcess.running = true
    }

    onActiveChanged: {
        if (root.active) root.refresh()
        else if (root.selectedKey) root.closeKey()
    }
    Component.onCompleted: root.refresh()

    // Same `cat`-via-Process idiom as ShellSettings.qml: a missing file
    // (first run) is just empty stdout.
    Process {
        id: storeProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/shortcuts.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.store = { binds: parsed.binds || [], removed: parsed.removed || [], descriptions: parsed.descriptions || {} }
                } catch (e) {
                    root.store = { binds: [], removed: [], descriptions: {} }
                }
            }
        }
    }

    Process {
        id: bindsProcess
        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.liveBinds = JSON.parse(text)
                } catch (e) {
                    root.liveBinds = []
                }
            }
        }
    }

    // A rejected bind reports its reason on stdout, shown above the numpad.
    Process {
        id: applyProcess

        stdout: StdioCollector {
            onStreamFinished: {
                const output = text.trim()
                root.applyError = /error|fail|invalid|couldn't/i.test(output) ? output : ""
            }
        }

        onExited: {
            bindsProcess.running = false
            bindsProcess.running = true
            root.applyNext()
        }
    }

    FileView {
        id: storeFile
        path: Quickshell.env("HOME") + "/.config/quickshell/shortcuts.json"
        preload: false
    }

    FileView {
        id: luaFile
        path: Quickshell.env("HOME") + "/.config/hypr/shortcuts.lua"
        preload: false
    }

    // A bordered text button, used for the panel's modifiers and actions.
    component PanelButton: DashCard {
        id: button

        property string text: ""
        property bool lit: false
        property bool enabled: true
        signal clicked()

        uiScale: root.uiScale
        implicitWidth: buttonLabel.implicitWidth + Config.scaled(20, root.uiScale)
        implicitHeight: Config.scaled(32, root.uiScale)
        color: buttonMouse.containsMouse && button.enabled ? Config.fgcolorhover : Config.fillcolor
        border.color: button.lit ? Config.fgcolorlight : Config.fgcolor
        opacity: button.enabled ? 1 : 0.5

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.text
            color: button.border.color
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (button.enabled) button.clicked()
        }
    }

    // A bordered single-line text field, used for the panel's inputs.
    component PanelInput: Rectangle {
        id: field

        property alias text: fieldInput.text
        property string placeholder: ""

        function focusInput() { fieldInput.forceActiveFocus() }

        height: Config.scaled(32, root.uiScale)
        color: Config.fillcolor
        border.width: Config.scaled(2, root.uiScale)
        border.color: fieldInput.activeFocus ? Config.fgcolorlight : Config.fgcolor

        TextInput {
            id: fieldInput
            anchors {
                fill: parent
                margins: Config.scaled(8, root.uiScale)
            }
            verticalAlignment: TextInput.AlignVCenter
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            selectByMouse: true
            clip: true
            activeFocusOnTab: true
            onAccepted: root.submitForm()

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: fieldInput.text.length === 0
                text: field.placeholder
                color: Config.fgcolor
                opacity: 0.6
                font: fieldInput.font
            }
        }
    }

    // ---------------- keyboard ----------------
    Item {
        id: keyboard

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: Config.scaled(18, root.uiScale)
        }

        readonly property real gap: Config.scaled(4, root.uiScale)
        // The width sets the size of a key and the height follows, so keys
        // are square. A key's trailing gap is left off, so the last column
        // and row end flush.
        readonly property real unitWidth: (width + gap) / root.keyboardUnitsWide
        readonly property real unitHeight: unitWidth
        height: unitHeight * root.keyboardUnitsTall - gap

        Repeater {
            model: root.keys

            delegate: Rectangle {
                id: keyRect

                required property var modelData

                readonly property bool bound: !!root.boundKeys[keyRect.modelData.sym.toLowerCase()]
                readonly property bool described: !!root.describedKeys[keyRect.modelData.sym.toLowerCase()]
                readonly property bool selected: root.selectedKey === keyRect.modelData

                x: keyRect.modelData.x * keyboard.unitWidth
                y: keyRect.modelData.y * keyboard.unitHeight
                width: keyRect.modelData.w * keyboard.unitWidth - keyboard.gap
                height: keyRect.modelData.h * keyboard.unitHeight - keyboard.gap

                color: keyMouse.containsMouse || keyRect.selected ? Config.fgcolorhover : Config.fillcolor
                border.width: Config.scaled(2, root.uiScale)
                border.color: keyRect.described ? Config.fgcolorlight : keyRect.bound ? Config.fgcolor : Config.fgcolordark

                Text {
                    anchors {
                        fill: parent
                        margins: Config.scaled(4, root.uiScale)
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: keyRect.modelData.label
                    color: keyRect.described ? Config.fgcolorlight : Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(13, root.uiScale)
                    font.bold: true
                }

                MouseArea {
                    id: keyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.openKey(keyRect.modelData)
                    onContainsMouseChanged: {
                        if (containsMouse) root.hoveredKey = keyRect.modelData
                        else if (root.hoveredKey === keyRect.modelData) root.hoveredKey = null
                    }
                }
            }
        }

        // The empty corner above the numpad.
        Text {
            x: 18.5 * keyboard.unitWidth
            width: 4 * keyboard.unitWidth - keyboard.gap
            height: keyboard.unitHeight - keyboard.gap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            text: root.applyError.length > 0 ? root.applyError : "Click a key to bind it"
            color: root.applyError.length > 0 ? Config.fgcolorred : Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
        }

        // Centered above the hovered key, kept inside the keyboard's width.
        DashCard {
            id: keyHint

            readonly property var key: root.hoveredKey
            readonly property real padding: Config.scaled(8, root.uiScale)

            visible: root.hoveredHintLines.length > 0 && root.selectedKey === null
            uiScale: root.uiScale
            color: "#ee000000"
            width: hintText.width + keyHint.padding * 2
            height: hintText.implicitHeight + keyHint.padding * 2
            x: !key ? 0 : Math.max(0, Math.min(keyboard.width - width,
                key.x * keyboard.unitWidth + (key.w * keyboard.unitWidth - keyboard.gap - width) / 2))
            y: !key ? 0 : key.y * keyboard.unitHeight - height - keyboard.gap

            Text {
                id: hintText
                x: keyHint.padding
                y: keyHint.padding
                width: Math.min(implicitWidth, Config.scaled(420, root.uiScale))
                wrapMode: Text.Wrap
                text: root.hoveredHintLines.join("\n")
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(13, root.uiScale)
            }
        }
    }

    // ---------------- key panel ----------------
    Rectangle {
        anchors.fill: parent
        visible: root.selectedKey !== null
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeKey()
        }
    }

    DashCard {
        id: panel

        // Top-anchored: the dropdowns grow this downward, which would
        // otherwise slide the whole panel under the cursor.
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Config.scaled(40, root.uiScale)
        }

        visible: root.selectedKey !== null
        uiScale: root.uiScale
        color: "#ee000000"
        width: Config.scaled(560, root.uiScale)
        height: panelColumn.implicitHeight

        // Steps back one level, the same as Cancel.
        Keys.onEscapePressed: {
            if (root.formOpen) root.closeForm()
            else root.closeKey()
        }

        // Keeps a click on the panel's blank space from reaching the
        // dismissing backdrop behind it.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: panelColumn

            width: parent.width
            padding: Config.scaled(16, root.uiScale)
            spacing: Config.scaled(12, root.uiScale)

            readonly property real innerWidth: width - padding * 2

            Text {
                text: root.selectedKey ? "Key: " + root.selectedKey.label : ""
                color: Config.fgcolorlight
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(16, root.uiScale)
                font.bold: true
            }

            Repeater {
                model: root.selectedBinds

                delegate: Item {
                    id: bindRow

                    required property var modelData

                    width: panelColumn.innerWidth
                    height: removeButton.height

                    Text {
                        anchors {
                            left: parent.left
                            right: removeButton.left
                            rightMargin: Config.scaled(10, root.uiScale)
                            verticalCenter: parent.verticalCenter
                        }
                        elide: Text.ElideRight
                        text: bindRow.modelData.combo + "  -  " + (bindRow.modelData.description || bindRow.modelData.label)
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                    }

                    PanelButton {
                        id: removeButton
                        anchors.right: parent.right
                        text: "Remove"
                        onClicked: root.removeBind(bindRow.modelData)
                    }
                }
            }

            // Same look as Project Mortar's add-ammo button.
            Rectangle {
                visible: !root.formOpen
                width: panelColumn.innerWidth
                height: Config.scaled(44, root.uiScale)
                color: addMouse.containsMouse ? addFill : "transparent"
                border.width: Config.scaled(2, root.uiScale)
                border.color: Config.fgcolorlight

                readonly property color addFill: {
                    const c = Qt.color(Config.fgcolorlight)
                    return Qt.rgba(c.r, c.g, c.b, 0.12)
                }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Config.fgcolorlight
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(24, root.uiScale)
                }

                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.openForm()
                }
            }

            Column {
                visible: root.formOpen
                width: panelColumn.innerWidth
                spacing: panelColumn.spacing

                Rectangle {
                    visible: root.selectedBinds.length > 0
                    width: panelColumn.innerWidth
                    height: Config.scaled(2, root.uiScale)
                    color: Config.fgcolor
                }

                Row {
                    spacing: Config.scaled(8, root.uiScale)

                    Repeater {
                        model: root.modifierNames

                        delegate: PanelButton {
                            required property string modelData

                            text: modelData
                            lit: root.formModifiers.indexOf(modelData) !== -1
                            onClicked: root.toggleModifier(modelData)
                        }
                    }
                }

                Row {
                    spacing: Config.scaled(8, root.uiScale)

                    DropdownBox {
                        width: Config.scaled(280, root.uiScale)
                        uiScale: root.uiScale
                        options: root.actionLabels
                        currentIndex: root.formAction
                        onActivated: (index) => {
                            root.formAction = index
                            open = false
                            if (root.formActionEntry.command) commandInput.focusInput()
                            else panel.forceActiveFocus()
                        }
                    }

                    DropdownBox {
                        visible: !!root.formActionEntry.workspace
                        width: Config.scaled(80, root.uiScale)
                        uiScale: root.uiScale
                        options: root.workspaceLabels
                        currentIndex: root.formWorkspace
                        onActivated: (index) => {
                            root.formWorkspace = index
                            open = false
                        }
                    }
                }

                PanelInput {
                    id: commandInput
                    visible: !!root.formActionEntry.command
                    width: panelColumn.innerWidth
                    placeholder: "Command to run"
                }

                PanelInput {
                    id: descriptionInput
                    width: panelColumn.innerWidth
                    placeholder: "Description"
                }

                Item {
                    width: panelColumn.innerWidth
                    height: bindButton.height

                    Text {
                        anchors {
                            left: parent.left
                            right: buttonRow.left
                            rightMargin: Config.scaled(10, root.uiScale)
                            verticalCenter: parent.verticalCenter
                        }
                        elide: Text.ElideRight
                        text: root.formCombo
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                    }

                    Row {
                        id: buttonRow
                        anchors.right: parent.right
                        spacing: Config.scaled(8, root.uiScale)

                        PanelButton {
                            text: "Cancel"
                            onClicked: root.closeForm()
                        }

                        PanelButton {
                            id: bindButton
                            // Binding a combo that's already taken swaps it out.
                            text: root.formDescriptionOnly ? "Save" : root.formConflict ? "Replace" : "Bind"
                            lit: true
                            enabled: root.formValid
                            onClicked: root.submitForm()
                        }
                    }
                }
            }
        }
    }
}

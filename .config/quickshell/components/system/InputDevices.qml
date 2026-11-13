import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Settings > General > Input at work: puts the mouse's sensitivity and
// acceleration and the keyboard's input languages (peripheralsettings.json,
// which ShellSettings.qml writes) into Hyprland - when they change, when the
// shell starts, and again after every config reload, which puts back
// hyprland.lua's own values. apply-peripherals.sh does the same once at
// login. Re-applying what's already there costs nothing: Hyprland leaves a
// keyboard alone when its config hasn't changed, so the language in use
// stays put.
//
// Also the input language shortcut (META + -): the next language, and an
// OSD (LanguageOsd.qml) saying which one's on - with only one language,
// neither: nothing to switch to, and the OSD never shows.
Scope {
    id: root

    // LanguageOsd.qml, from shell.qml.
    property var osd: null

    FileView {
        id: settingsFile

        path: Quickshell.env("HOME") + "/.config/quickshell/peripheralsettings.json"
        // Read up front, so the first thing applied is what's saved.
        blockLoading: true
        watchChanges: true
        // A fresh install has no file yet - that's just the defaults.
        printErrors: false
        onFileChanged: reload()
    }

    readonly property var store: {
        try {
            return JSON.parse(settingsFile.text()) || {}
        } catch (e) {
            return {}
        }
    }

    // -1 - 1, as hyprland.lua's input.sensitivity.
    readonly property real sensitivity: {
        const n = Number(root.store.mouseSensitivity)
        return isFinite(n) ? Math.max(-1, Math.min(1, n)) : 0
    }

    // Off by default. Off is libinput's flat profile rather than Hyprland's
    // force_no_accel, which skips libinput altogether - sensitivity
    // included, so the slider would do nothing. Flat at 0 moves the cursor
    // exactly as far as the mouse says, the same as force_no_accel did.
    readonly property bool acceleration: root.store.mouseAcceleration === true

    // The input languages in order (xkb layout codes; the first is the one
    // in use at login). None saved yet leaves hyprland.lua's kb_layout be.
    readonly property var layouts: Array.isArray(root.store.keyboardLayouts)
        ? root.store.keyboardLayouts.map(String).filter(code => /^[A-Za-z0-9_-]+$/.test(code))
        : []

    readonly property string pointerLua: "hl.config({ input = { force_no_accel = false, accel_profile = \""
        + (root.acceleration ? "adaptive" : "flat") + "\", sensitivity = " + root.sensitivity + " } })"
    readonly property string layoutLua: root.layouts.length > 0
        ? "hl.config({ input = { kb_layout = \"" + root.layouts.join(",") + "\", kb_variant = \"\" } })"
        : ""

    function apply() {
        Quickshell.execDetached(["hyprctl", "eval", root.pointerLua])
        if (root.layoutLua !== "") Quickshell.execDetached(["hyprctl", "eval", root.layoutLua])
    }

    // How many input languages there are: the ticked ones - or, none saved
    // yet, how many Hyprland has (hyprland.lua's kb_layout), asked at
    // startup and after every config reload.
    property int liveLanguageCount: 0
    readonly property int languageCount: root.layouts.length > 0 ? root.layouts.length : root.liveLanguageCount
    readonly property bool multipleLanguages: root.languageCount > 1

    function countLiveLanguages() {
        liveLanguagesProcess.running = false
        liveLanguagesProcess.running = true
    }

    Process {
        id: liveLanguagesProcess

        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards || []
                    const main = keyboards.find(k => k.main) || keyboards[0]
                    root.liveLanguageCount = main && main.layout
                        ? String(main.layout).split(",").filter(code => code.trim().length > 0).length
                        : 0
                } catch (e) {
                    root.liveLanguageCount = 0
                }
            }
        }
    }

    onPointerLuaChanged: Quickshell.execDetached(["hyprctl", "eval", root.pointerLua])
    onLayoutLuaChanged: {
        if (root.layoutLua !== "") Quickshell.execDetached(["hyprctl", "eval", root.layoutLua])
    }

    Component.onCompleted: {
        root.apply()
        root.countLiveLanguages()
    }

    // ---------------- the input language shortcut ----------------
    // The next language, named by Hyprland's "activelayout" event that
    // follows (one per keyboard - they all say the same). With only one
    // language, nothing at all.
    property bool awaitingSwitch: false
    property bool shownSinceSwitch: false

    function nextLanguage() {
        if (!root.multipleLanguages) return
        root.awaitingSwitch = true
        root.shownSinceSwitch = false
        switchTimer.restart()
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
    }

    function showLanguage(name) {
        if (root.osd && name) root.osd.show(name)
    }

    // What the main keyboard has on, asked directly.
    function showActiveLanguage() {
        activeLanguageProcess.running = false
        activeLanguageProcess.running = true
    }

    // No event in time (or none at all): ask instead.
    Timer {
        id: switchTimer

        interval: 400
        onTriggered: {
            if (!root.shownSinceSwitch) root.showActiveLanguage()
            root.awaitingSwitch = false
        }
    }

    Process {
        id: activeLanguageProcess

        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards || []
                    const main = keyboards.find(k => k.main) || keyboards[0]
                    if (main) root.showLanguage(main.active_keymap)
                } catch (e) {
                    // Nothing to show.
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                root.apply()
                root.countLiveLanguages()
            } else if (event.name === "activelayout" && root.awaitingSwitch) {
                // "keyboard name,layout name" - the name itself can hold
                // commas, the keyboard's can't.
                const comma = event.data.indexOf(",")
                root.shownSinceSwitch = true
                root.showLanguage(comma >= 0 ? event.data.slice(comma + 1) : event.data)
            }
        }
    }

    GlobalShortcut {
        name: "inputlanguage"
        description: "Next input language"

        onPressed: root.nextLanguage()
    }

    IpcHandler {
        target: "inputlanguage"

        function next(): void { root.nextLanguage() }
    }
}

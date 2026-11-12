import Quickshell
import Quickshell.Io
import QtQuick

// The global UI Scale - the slider at the bottom of Settings > Shell's
// category list. One multiplier on top of every screen's own
// resolution-based scale (Config.uiScale): shell.qml hands `value` to
// every component that sizes itself, as its `shellScale`.
//
// Owns uiscalesettings.json, the same way NightLight.qml owns its file;
// ShellSettings.qml's slider only calls set().
Scope {
    id: root

    // Not watched: this is the only writer.
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/uiscalesettings.json"
        // Read before any window opens, so the shell comes up at the saved
        // size instead of opening at 100% and then jumping.
        blockLoading: true
        // A fresh install has no file yet - that's just 100%, not an error.
        printErrors: false
    }

    readonly property real minimum: 0.5
    readonly property real maximum: 1.5
    readonly property real step: 0.05

    // A missing or unreadable file reads as 100%.
    property real value: {
        try {
            const stored = JSON.parse(settingsFile.text())
            return root.clamp(stored && stored.scale !== undefined ? stored.scale : 1)
        } catch (e) {
            return 1
        }
    }

    // Snapped to the slider's steps and kept inside its range, so a
    // hand-edited file can't make the shell unusably small or large.
    function clamp(scale) {
        const n = Number(scale)
        if (isNaN(n)) return 1
        const snapped = Math.round(n / root.step) * root.step
        return Math.round(Math.max(root.minimum, Math.min(root.maximum, snapped)) * 100) / 100
    }

    function set(scale) {
        const next = root.clamp(scale)
        if (next === root.value) return
        root.value = next
        settingsFile.setText(JSON.stringify({ scale: next }, null, 2) + "\n")
    }
}

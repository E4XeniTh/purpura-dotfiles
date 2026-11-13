import QtQuick
import Quickshell
import Quickshell.Io

// Names the shell shows in place of the system's own - Settings >
// Connections' devices and connections, Settings > Sound's playback and
// recording devices - kept as { key: name } in a small JSON file of their own
// (`file`, in ~/.config/quickshell). Only the shell reads them: nothing is
// renamed for the system or any other app. Every copy watches the file, so a
// rename shows wherever the name does.
Scope {
    id: root

    // e.g. "connectionaliases.json"
    property string file: ""

    FileView {
        id: aliasFile

        path: root.file.length > 0 ? Quickshell.env("HOME") + "/.config/quickshell/" + root.file : ""
        blockLoading: true
        watchChanges: true
        // A fresh install has no file yet - that's just no renames.
        printErrors: false
        onFileChanged: reload()
    }

    readonly property var stored: {
        try {
            const parsed = JSON.parse(aliasFile.text())
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
        } catch (e) {
            return {}
        }
    }

    // What a rename just set, until the file it went to reads back: the
    // write happens in the background, and the name should change at once.
    property var written: null
    onStoredChanged: root.written = null

    readonly property var aliases: root.written !== null ? root.written : root.stored

    // What to call `key`: its alias, or else `systemName`.
    function name(key, systemName) {
        const alias = root.aliases[key]
        return typeof alias === "string" && alias.length > 0 ? alias : systemName
    }

    function hasAlias(key) {
        const alias = root.aliases[key]
        return typeof alias === "string" && alias.length > 0
    }

    // Calls `key` `newName` from now on - or the system's own name again when
    // that's blank or the same as it.
    function rename(key, newName, systemName) {
        const next = Object.assign({}, root.aliases)
        const trimmed = (newName || "").trim()
        if (trimmed.length === 0 || trimmed === systemName) delete next[key]
        else next[key] = trimmed
        root.written = next
        aliasFile.setText(JSON.stringify(next, null, 2) + "\n")
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "WorkspaceRegistryLogic.js" as Logic

// purpura.lua's book of Hyprland's workspaces (WORKSPACES there): every workspace's
// purpura number and type (pinned, spare, reserved, fullscreen, new, other) and what
// it's for, each monitor's assigned workspaces and what Display settings' buttons
// picked for it - from $XDG_RUNTIME_DIR/purpura-workspaces.json, which purpura.lua
// rewrites as it changes. Every copy watches the file. A read that catches it
// mid-write keeps the last good one. With no file (purpura.lua not loaded) there's
// no book: 1-5 still show their numbers and count as managed, as they did by number.
Scope {
    id: root

    FileView {
        id: registryFile

        path: (Quickshell.env("XDG_RUNTIME_DIR") || (Quickshell.env("HOME") + "/.cache")) + "/purpura-workspaces.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    readonly property var parsed: Logic.parse(registryFile.text())
    property var book: null
    onParsedChanged: if (root.parsed) root.book = root.parsed
    Component.onCompleted: if (root.parsed) root.book = root.parsed

    readonly property bool available: root.book !== null

    // By Hyprland workspace - an object with an id, or the id.
    function idOf(workspace) {
        return typeof workspace === "number" ? workspace : (workspace ? workspace.id : NaN)
    }
    function entryOf(workspace) { return Logic.entryOf(root.book, root.idOf(workspace)) }
    function numberOf(workspace) { return Logic.numberOf(root.book, root.idOf(workspace)) }
    function typeOf(workspace) { return Logic.typeOf(root.book, root.idOf(workspace)) }
    function isManaged(workspace) { return Logic.isManaged(root.book, root.idOf(workspace)) }

    // By monitor name.
    function pinsOf(name) { return Logic.pinsOf(root.book, name) }
    function assignedOf(name) { return Logic.assignedOf(root.book, name) }
    readonly property var monitors: Logic.monitorsOf(root.book)
}

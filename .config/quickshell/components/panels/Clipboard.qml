import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import "../../Config.js" as Config

// Clipboard history panel - opens bottom-right on META + V (bound via
// hyprland.lua's `hl.bind(mainMod .. " + V", hl.dsp.global("quickshell:clipboard"))`,
// the same GlobalShortcut mechanism PowerMenu/LockScreen use for their own
// keybinds). Backed by cliphist - `wl-paste --watch cliphist store` must
// already be running for both the text and image mime types (see README),
// the shell here only ever shells out to `cliphist list` / `decode` /
// `wipe`, it doesn't watch the clipboard itself.
//
// Structurally mirrors Notification.qml's own history panel: the outer
// window is sized to the full content immediately, and only the inner
// panelBox Rectangle animates open via clip - see that file's own comment
// for why (animating the window itself was a real per-frame Wayland
// surface resize, not just a repaint, and felt laggy).
Scope {
    id: root

    // Settings > General's global UI Scale (UiScale.qml), from shell.qml -
    // multiplied into every window's Config.uiScale below.
    property real shellScale: 1.0

    // EdgeGaps.qml: lines this up with the bar's right end.
    property var edgeGaps: null

    property bool open: false

    // The LazyLoader gate below (root.open && previewedEntryId !== "")
    // only ever hides the preview WINDOW when the clipboard closes - it
    // never actually clears previewedEntryId itself, so without this the
    // very next open (via any path: the shortcut, IpcHandler, selecting
    // an entry) immediately re-satisfied that same gate and reopened the
    // preview on the same entry, looking exactly like it had never
    // closed at all.
    onOpenChanged: {
        if (root.open) {
            autoCloseTimer.restart()
            // Opens on the newest entry, ready for the keyboard - and on a
            // newer one still if the refresh opening sets off finds it.
            root.followNewest = true
            if (clipModel.count > 0) root.selectIndex(0)
        } else {
            root.followNewest = false
            root.panelOpened = false
            root.previewedEntryId = ""
            root.previewedIsImage = false
            root.previewedImagePath = ""
            root.previewText = ""
            autoCloseTimer.stop()
        }
    }

    // Whether the panel has finished its opening animation - the preview
    // pane waits for it (see its LazyLoader).
    property bool panelOpened: false

    // Auto-close after 5s with the mouse over neither the clipboard
    // panel nor the preview pane - HoverHandler on each (below) restarts
    // this to a fresh 5s every time the mouse leaves either one, and
    // stops it while the mouse is present in either, so it only ever
    // fires after 5 full uninterrupted seconds of no mouse activity in
    // either window.
    Timer {
        id: autoCloseTimer
        interval: 5000
        repeat: false
        onTriggered: root.open = false
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.open = !root.open }
        function show(): void { root.open = true }
        function hide(): void { root.open = false }
    }

    GlobalShortcut {
        name: "clipboard"
        onPressed: {
            root.open = !root.open
        }
    }

    // Persistent for the Scope's lifetime (not inside the LazyLoader)
    // so a wipe/select triggered from one open doesn't need its own
    // teardown/rebuild dance - only the visual panel is lazy-loaded.
    ListModel {
        id: clipModel
    }

    // Raw `cliphist list` text from the last successful refresh - lets
    // the poll Timer below skip rebuilding clipModel (and re-triggering
    // every image entry's thumbnail decode) on ticks where nothing
    // actually changed, not just on ticks where something did.
    property string lastListText: ""

    // Which entry (if any) is currently shown highlighted+blurred in the
    // list, with its full contents open in the side preview pane. Gated
    // together with root.open (see the preview pane's LazyLoader below)
    // so closing the clipboard for any reason also always closes the
    // preview pane with it, instead of needing every place root.open can
    // become false to separately remember to reset this too.
    property string previewedEntryId: ""
    property bool previewedIsImage: false
    property string previewedImagePath: ""
    property string previewText: ""

    // Set right when a delete is fired, consumed (and always cleared)
    // the next time the list actually refreshes - lets that refresh know
    // "this particular emptiness, if it happens, came from a delete" so
    // it only auto-closes the clipboard for that reason, never just
    // because the panel happened to open onto an already-empty history.
    property bool pendingDeleteClose: false

    function refresh() {
        listProcess.running = true
    }

    // ---------------- the selection ----------------
    // The selected entry is the previewed one: the keyboard moves it, the
    // mouse moves it by pointing at an entry, Enter copies it. Entries are
    // newest first.

    // Until the first refresh after opening (or a key or the mouse moving
    // the selection), it stays on whatever's newest.
    property bool followNewest: false

    // A move the panel scrolls to show (the mouse's own never need it).
    signal selectionMoved(int index)

    function indexOfEntry(entryId) {
        for (let i = 0; i < clipModel.count; i++) {
            if (clipModel.get(i).entryId === entryId) return i
        }
        return -1
    }

    function selectIndex(index) {
        if (index < 0 || index >= clipModel.count) return
        const entry = clipModel.get(index)
        root.previewEntry(entry.entryId, entry.isImage, entry.imagePath)
        root.selectionMoved(index)
    }

    // Up/Down (step -1/1), Page Up/Down, Home/End. With nothing selected,
    // the first press lands on the newest entry.
    function moveSelection(step) {
        root.followNewest = false
        if (clipModel.count === 0) return
        const at = root.indexOfEntry(root.previewedEntryId)
        root.selectIndex(at < 0 ? 0 : Math.max(0, Math.min(clipModel.count - 1, at + step)))
    }

    // The mouse pointing at an entry (see clipWindow.pointerAt).
    function pointAt(entryId, isImage, imagePath) {
        root.followNewest = false
        root.previewEntry(entryId, isImage, imagePath)
    }

    // Delete: the selection moves on to the next entry (the one before, at
    // the end of the list).
    function deleteSelected() {
        root.followNewest = false
        const at = root.indexOfEntry(root.previewedEntryId)
        if (at < 0) return
        const gone = clipModel.get(at)
        const goneId = gone.entryId
        const gonePreview = gone.preview
        const next = at + 1 < clipModel.count ? at + 1 : at - 1
        let nextEntry = null
        if (next >= 0) {
            const e = clipModel.get(next)
            nextEntry = { entryId: e.entryId, isImage: e.isImage, imagePath: e.imagePath }
        }
        root.deleteEntry(goneId, gonePreview)
        if (nextEntry) {
            root.previewEntry(nextEntry.entryId, nextEntry.isImage, nextEntry.imagePath)
            root.selectionMoved(next)
        }
    }

    // The panel's keys; true for one it used.
    function handleKey(key) {
        switch (key) {
        case Qt.Key_Down: root.moveSelection(1); return true
        case Qt.Key_Up: root.moveSelection(-1); return true
        case Qt.Key_PageDown: root.moveSelection(5); return true
        case Qt.Key_PageUp: root.moveSelection(-5); return true
        case Qt.Key_End: root.moveSelection(clipModel.count); return true
        case Qt.Key_Home: root.moveSelection(-clipModel.count); return true
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (root.previewedEntryId !== "") root.selectEntry(root.previewedEntryId)
            return true
        case Qt.Key_Delete: root.deleteSelected(); return true
        case Qt.Key_Escape: root.open = false; return true
        }
        return false
    }

    // Hovering an entry (see entryMouseArea's onEntered below) previews
    // it - moving the mouse off that entry deliberately does NOT clear
    // the preview, only hovering a DIFFERENT one changes it, so the pane
    // doesn't flicker shut while the mouse crosses the gap between the
    // list and the preview pane itself (e.g. to select some of its
    // text). Left click no longer previews at all - it just copies
    // immediately (see selectEntry, called straight from onClicked).
    function previewEntry(entryId, isImage, imagePath) {
        if (root.previewedEntryId === entryId) return

        root.previewedEntryId = entryId
        root.previewedIsImage = isImage
        root.previewedImagePath = imagePath
        root.previewText = ""

        if (!isImage) {
            // The entry's id on the first line, so a decode finishing after
            // the selection moved on is recognised (see previewTextProcess).
            previewTextProcess.command = ["bash", "-c", 'printf "%s\\n" "$1"; cliphist decode "$1"', "clipboard-preview", entryId]
            previewTextProcess.running = true
        }
    }

    function selectEntry(entryId) {
        selectProcess.command = ["bash", "-c", 'cliphist decode "$1" | wl-copy', "clipboard-select", entryId]
        selectProcess.running = true
        root.open = false
    }

    // cliphist's own documented usage is `cliphist list | picker | cliphist
    // delete` - it reads whole "id\tpreview" lines from stdin and pulls the
    // id off the front of each one, rather than reliably taking a bare id
    // as a positional argument. Piping entryId+preview back in that same
    // shape (via printf, so nothing here is shell-interpolated) is what
    // actually matches how it's meant to be driven.
    function deleteEntry(entryId, preview) {
        // Deleting the entry currently open in the preview pane closes
        // just the pane, independent of whether the clipboard itself
        // ends up closing too (see pendingDeleteClose below).
        if (root.previewedEntryId === entryId) {
            root.previewedEntryId = ""
        }

        root.pendingDeleteClose = true
        deleteProcess.command = ["bash", "-c", 'printf "%s\\t%s\\n" "$1" "$2" | cliphist delete', "clipboard-delete", entryId, preview]
        deleteProcess.running = true
    }

    Process {
        id: listProcess
        command: ["cliphist", "list"]

        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                if (listCollector.text === root.lastListText) {
                    root.pendingDeleteClose = false
                    root.listRefreshed()
                    return
                }
                root.lastListText = listCollector.text

                const lines = listCollector.text.split("\n").filter(l => l.length > 0)
                const parsedEntries = []
                const newIds = new Set()

                for (const line of lines) {
                    const tab = line.indexOf("\t")
                    if (tab === -1) continue

                    const entryId = line.substring(0, tab)
                    // cliphist's own preview occasionally arrives already
                    // prefixed with "..." (a middle-of-entry fragment) -
                    // strip it so the preview always reads from the real
                    // start of the copied text, and only our own Text's
                    // elide (end-anchored) ever adds a "..." back.
                    const preview = line.substring(tab + 1).replace(/^\.\.\.\s*/, "")
                    const isImage = /binary data/i.test(preview)

                    // A browser's "copy image" often populates a
                    // text/html clipboard mime alongside the actual
                    // image data, whose body opens with exactly this
                    // meta tag - it's not real content, just a duplicate
                    // artifact of the same copy, so skip it entirely
                    // rather than showing it as its own history entry.
                    if (preview.indexOf('<meta http-equiv="content-type" content="text/html; charset=utf-8">') !== -1) continue

                    // A file manager's "copy" (as opposed to copying its
                    // actual bytes) typically populates a text/uri-list
                    // clipboard mime holding a bare file:// path - not
                    // something useful to select for re-pasting as text,
                    // so skip it entirely rather than showing it as its
                    // own history entry.
                    if (preview.indexOf("file://") !== -1) continue

                    parsedEntries.push({
                        entryId: entryId,
                        preview: preview,
                        isImage: isImage,
                        imagePath: isImage ? ("/tmp/quickshell-clip-" + entryId + ".img") : ""
                    })
                    newIds.add(entryId)
                }

                // Diffed against the CURRENT clipModel instead of a blind
                // clear()+rebuild - deleting one entry (or copying a new
                // one) used to tear down and recreate every delegate,
                // which meant every image entry's thumbnail flickered
                // out and back in even though its own entry never
                // actually changed.
                //
                // Pass 1: drop rows whose entry no longer exists, back
                // to front so removing one never shifts the index of a
                // row still waiting to be checked.
                for (let i = clipModel.count - 1; i >= 0; i--) {
                    if (!newIds.has(clipModel.get(i).entryId)) {
                        clipModel.remove(i)
                    }
                }

                // Pass 2: what's left in clipModel is now exactly a
                // subsequence of parsedEntries in the same relative
                // order (pass 1 only ever removed things) - so walking
                // both in lockstep and inserting wherever they don't
                // match is enough to thread in every genuinely new entry
                // at its correct position, leaving every already-present
                // row (and its delegate/decoded thumbnail) completely
                // untouched.
                for (let i = 0; i < parsedEntries.length; i++) {
                    const existing = i < clipModel.count ? clipModel.get(i) : null
                    if (!existing || existing.entryId !== parsedEntries[i].entryId) {
                        clipModel.insert(i, parsedEntries[i])
                    }
                }

                if (root.pendingDeleteClose) {
                    root.pendingDeleteClose = false
                    if (clipModel.count === 0) root.open = false
                }
                root.listRefreshed()
            }
        }
    }

    // The first refresh after opening settles which entry is the newest.
    function listRefreshed() {
        if (!root.followNewest || !root.open) return
        root.followNewest = false
        if (clipModel.count > 0 && clipModel.get(0).entryId !== root.previewedEntryId) root.selectIndex(0)
    }

    // Command is set fresh per click by selectEntry() above - a single
    // reused Process, not one per entry, since only ever one selection
    // happens at a time.
    Process {
        id: selectProcess
    }

    Process {
        id: deleteProcess
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    Process {
        id: wipeProcess
        command: ["cliphist", "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh()
            root.open = false
        }
    }

    // Fetches the FULL text of whichever entry is currently being
    // previewed - cliphist list's own preview is capped at ~100 chars,
    // nowhere near enough for the preview pane's "full contents" job.
    // Not needed for image entries, which reuse the thumbnail's already-
    // decoded /tmp file directly instead.
    Process {
        id: previewTextProcess

        // A decode asked for while another runs starts once that one's done
        // (Quickshell queues it), so the earlier one's text arrives first -
        // and only the selected entry's own is shown.
        stdout: StdioCollector {
            id: previewTextCollector
            onStreamFinished: {
                const text = previewTextCollector.text
                const newline = text.indexOf("\n")
                if (newline < 0 || text.substring(0, newline) !== root.previewedEntryId) return
                root.previewText = text.substring(newline + 1)
            }
        }
    }

    // Only mounted while open, same reasoning as VolumeOsd/BrightnessOsd -
    // no point keeping the panel's render tree alive for something
    // nobody's looking at.
    LazyLoader {
        active: root.open

        PanelWindow {
            id: clipWindow

            // The shell-wide per-screen scale (see Config.uiScale) of
            // whichever screen the compositor put this window on.
            readonly property real uiScale: Config.uiScale(clipWindow.screen, root.shellScale)

            anchors { bottom: true; right: true }
            margins { bottom: Config.scaled(3, clipWindow.uiScale); right: root.edgeGaps ? root.edgeGaps.right : 10 }

            implicitWidth: Config.scaled(400, clipWindow.uiScale)
            // +20 = the 10px top + 10px bottom margins contentCol below
            // sits inside - without it, panelBox/mainRect were exactly
            // contentCol's own height with only a bottom margin applied,
            // so contentCol's top edge landed 10px above mainRect's top
            // and mainRect's clip:true cut the title row off.
            implicitHeight: Math.max(contentCol.implicitHeight + Config.scaled(20, clipWindow.uiScale), 2)
            color: "transparent"

            // Overlay (not the unset default, which is Top - same as
            // Bar.qml) so this renders above regular windows.
            WlrLayershell.namespace: "clipboard"
            WlrLayershell.layer: WlrLayer.Overlay

            // The keyboard is the panel's while it's open (see keyHandler
            // below). Exclusive, not OnDemand: Hyprland hands an on-demand
            // surface's focus back to the window under the mouse the moment
            // the mouse moves over it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Component.onCompleted: {
                root.refresh()
                keyHandler.forceActiveFocus()
            }

            // Up/Down (Page Up/Down, Home/End) move the selection, Enter
            // copies it, Delete removes it, Escape closes - see
            // root.handleKey(). Each key used holds off the auto-close the
            // way the mouse being over the panel does.
            Item {
                id: keyHandler
                focus: true
                Keys.onPressed: (event) => {
                    if (!root.handleKey(event.key)) return
                    event.accepted = true
                    if (autoCloseTimer.running) autoCloseTimer.restart()
                }
            }

            // Keeps a selection the keyboard moved in view.
            Connections {
                target: root
                function onSelectionMoved(index) {
                    clipList.positionViewAtIndex(index, ListView.Contain)
                }
            }

            // Where the mouse last was, in window coordinates - unknown until
            // it's first seen over an entry after opening.
            property real pointerX: NaN
            property real pointerY: NaN

            // An entry under the mouse: selected only when the mouse itself
            // moved. Qt also reports an entry sliding under a still mouse -
            // the list scrolling to a selection the keyboard moved, or the
            // panel opening right where the mouse rests - and that mustn't
            // take the selection.
            function pointerAt(area, x, y, entryId, isImage, imagePath) {
                const p = area.mapToItem(null, x, y)
                const moved = !isNaN(clipWindow.pointerX)
                    && (Math.abs(p.x - clipWindow.pointerX) > 0.5 || Math.abs(p.y - clipWindow.pointerY) > 0.5)
                clipWindow.pointerX = p.x
                clipWindow.pointerY = p.y
                if (moved) root.pointAt(entryId, isImage, imagePath)
            }

            // Cliphist has no push-based "history changed" signal to
            // hook into, so this is a plain poll - cheap since refresh()
            // now skips rebuilding clipModel entirely when the raw list
            // text hasn't actually changed since last time. Lives inside
            // the LazyLoader like everything else here, so it only ever
            // runs while the panel is actually open.
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: root.refresh()
            }

            Rectangle {
                id: panelBox

                // Anchored to the window's bottom (not top, like
                // Notification's own top-right panel) so it grows upward
                // as it opens instead of downward off the bottom edge.
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                width: contentCol.width
                height: contentCol.implicitHeight + Config.scaled(20, clipWindow.uiScale)

                color: "transparent"

                Rectangle {
                    id: mainRect
                    anchors.fill: parent
                    color: Config.fillcolor
                    border.width: Config.scaled(2, clipWindow.uiScale)
                    border.color: Config.fgcolor
                    clip: true

                    // Purely observational - doesn't grab/consume
                    // anything the way a MouseArea would, so it coexists
                    // fine with every entry's own MouseArea underneath.
                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) {
                                autoCloseTimer.stop()
                            } else {
                                autoCloseTimer.restart()
                            }
                        }
                    }

                    ColumnLayout {
                        id: contentCol
                        width: Config.scaled(400, clipWindow.uiScale) - 2 * Config.scaled(10, clipWindow.uiScale)

                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            margins: Config.scaled(10, clipWindow.uiScale)
                        }
                        spacing: Config.scaled(10, clipWindow.uiScale)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: "Clipboard"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(14, clipWindow.uiScale)
                                font.bold: true
                            }

                            Text {
                                visible: clipModel.count > 0
                                text: "Clear all"
                                color: clearAllMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: Config.scaled(14, clipWindow.uiScale)

                                MouseArea {
                                    id: clearAllMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: wipeProcess.running = true
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: clipModel.count === 0
                            text: "No clipboard history"
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(12, clipWindow.uiScale)
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ListView {
                            id: clipList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, Config.scaled(420, clipWindow.uiScale))
                            visible: clipModel.count > 0
                            clip: true
                            spacing: Config.scaled(8, clipWindow.uiScale)
                            model: clipModel
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: entryDelegate

                                required property string entryId
                                required property string preview
                                required property bool isImage
                                required property string imagePath

                                readonly property bool isPreviewed: root.previewedEntryId === entryDelegate.entryId

                                width: clipList.width
                                // 16 = 8px top + 8px bottom margin around
                                // contentRow below (anchored top/left/
                                // right only, not bottom, so its actual
                                // height never fights this binding the
                                // way panelBox's did before that fix).
                                // An image entry's 80px-tall thumbnail
                                // (+16 margin) lands this at 96 - exactly
                                // two base (48px) text-entry rows tall.
                                height: Math.max(Config.scaled(64, clipWindow.uiScale), contentRow.implicitHeight + Config.scaled(16, clipWindow.uiScale))
                                // The selected entry (see root.previewEntry)
                                // - the one under the mouse, or the one the
                                // keyboard moved to.
                                color: entryDelegate.isPreviewed ? Config.fgcolorhover : Config.fillcolor
                                border.width: Config.scaled(2, clipWindow.uiScale)
                                border.color: entryDelegate.isPreviewed ? Config.fgcolorlight : Config.fgcolor

                                RowLayout {
                                    id: contentRow

                                    // verticalCenter (not top) so a short
                                    // single-line entry sits centered in
                                    // its row instead of stuck at the
                                    // top-left with dead space below it -
                                    // a tall wrapped entry still just
                                    // grows the whole row height to match
                                    // (see entryDelegate.height above), so
                                    // centering here never clips anything.
                                    anchors {
                                        verticalCenter: parent.verticalCenter
                                        left: parent.left
                                        right: parent.right
                                        margins: Config.scaled(8, clipWindow.uiScale)
                                    }
                                    spacing: Config.scaled(8, clipWindow.uiScale)

                                    Image {
                                        id: thumb
                                        visible: entryDelegate.isImage
                                        Layout.preferredWidth: Config.scaled(80, clipWindow.uiScale)
                                        Layout.preferredHeight: Config.scaled(80, clipWindow.uiScale)
                                        Layout.alignment: Qt.AlignTop
                                        // Decoded at twice that size (for a
                                        // HiDPI screen), not the picture's
                                        // own - a screenshot is the whole
                                        // screen, for each row.
                                        sourceSize: Qt.size(Config.scaled(160, clipWindow.uiScale), Config.scaled(160, clipWindow.uiScale))
                                        // Fit the whole image within the
                                        // thumbnail bounds instead of
                                        // cropping it to fill - letterboxed
                                        // is preferable to silently losing
                                        // part of the picture.
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: false
                                    }

                                    Text {
                                        // No label at all for image
                                        // entries - the thumbnail already
                                        // says everything there is to say.
                                        visible: !entryDelegate.isImage
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignTop
                                        text: entryDelegate.preview
                                        // Some clipboard entries (e.g. a
                                        // browser's "copy image" also
                                        // populating a text/html mime
                                        // alongside the actual image) are
                                        // literal HTML/XML source. Text's
                                        // default AutoText would sniff
                                        // that and try to actually RENDER
                                        // it as rich text/markup (an <img>
                                        // tag inside becomes a real,
                                        // usually-broken embedded image
                                        // request) instead of showing it -
                                        // forcing PlainText always shows
                                        // the raw characters as-is.
                                        textFormat: Text.PlainText
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: Config.scaled(14, clipWindow.uiScale)
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                    }
                                }

                                // Blur only ever covers THIS entry's own
                                // row - every other delegate keeps its own
                                // independent isPreviewed check, so only
                                // the one currently hovered shows it. No
                                // "click to copy" label anymore - left
                                // click just copies immediately now (see
                                // entryMouseArea below), there's nothing
                                // left for a label to explain.
                                FastBlur {
                                    // Explicit, not relying on plain
                                    // declaration order - keeps this
                                    // pinned below entryMouseArea (z: 1)
                                    // regardless of how this delegate
                                    // gets reordered/edited later.
                                    z: 0
                                    anchors.fill: contentRow
                                    source: contentRow
                                    radius: Config.scaled(48, clipWindow.uiScale)
                                    visible: entryDelegate.isPreviewed
                                }

                                MouseArea {
                                    id: entryMouseArea
                                    z: 1
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    // Pointing selects and previews (see
                                    // clipWindow.pointerAt) - clicking no
                                    // longer previews at all, left click
                                    // copies+closes immediately, right
                                    // click deletes, same as every other
                                    // list in this shell.
                                    onEntered: clipWindow.pointerAt(entryMouseArea, entryMouseArea.mouseX, entryMouseArea.mouseY,
                                        entryDelegate.entryId, entryDelegate.isImage, entryDelegate.imagePath)
                                    onPositionChanged: (mouse) => clipWindow.pointerAt(entryMouseArea, mouse.x, mouse.y,
                                        entryDelegate.entryId, entryDelegate.isImage, entryDelegate.imagePath)
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            root.deleteEntry(entryDelegate.entryId, entryDelegate.preview)
                                        } else {
                                            root.selectEntry(entryDelegate.entryId)
                                        }
                                    }
                                }

                                // Decoded once per delegate instance - the
                                // LazyLoader tears the whole panel down on
                                // close, so this never runs against a stale
                                // entry. The reload timer gives the detached
                                // decode process a moment to finish writing
                                // the file before Image actually loads it.
                                Component.onCompleted: {
                                    if (entryDelegate.isImage) {
                                        Quickshell.execDetached(["bash", "-c", 'cliphist decode "$1" > "$2"', "clipboard-thumb", entryDelegate.entryId, entryDelegate.imagePath])
                                        thumbReloadTimer.start()
                                    }
                                }

                                Timer {
                                    id: thumbReloadTimer
                                    interval: 250
                                    onTriggered: thumb.source = "file://" + entryDelegate.imagePath
                                }
                            }
                        }

                        Item { height: Config.scaled(8, clipWindow.uiScale) }
                    }
                }

                states: [
                    State {
                        name: "spread"
                        PropertyChanges { target: panelBox; width: Config.scaled(400, clipWindow.uiScale); height: Config.scaled(2, clipWindow.uiScale) }
                    },
                    State {
                        name: "open"
                        PropertyChanges { target: panelBox; width: Config.scaled(400, clipWindow.uiScale); height: contentCol.implicitHeight + Config.scaled(20, clipWindow.uiScale) }
                    }
                ]

                transitions: [
                    Transition {
                        NumberAnimation {
                            properties: "width,height"
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }
                ]

                Component.onCompleted: {
                    panelBox.width = 0
                    panelBox.height = Config.scaled(4, clipWindow.uiScale)
                    panelBox.state = "spread"
                    openTimer.start()
                }

                Timer {
                    id: openTimer
                    interval: 300
                    repeat: false
                    onTriggered: {
                        panelBox.state = "open"
                        openedTimer.start()
                    }
                }

                // The second phase's length (the transition above): the
                // panel is all the way open when this fires.
                Timer {
                    id: openedTimer
                    interval: 300
                    repeat: false
                    onTriggered: root.panelOpened = true
                }
            }
        }
    }

    // Full-content preview pane, to the left of the clipboard panel -
    // gated on root.open too (not just previewedEntryId), so closing the
    // clipboard for any reason (selecting an entry, re-pressing META + V,
    // an IpcHandler hide()) always takes this down with it instead of
    // needing every one of those paths to separately remember to clear
    // previewedEntryId. It also waits for the panel to finish opening
    // (root.panelOpened), so the newest entry, selected straight away,
    // isn't previewed beside a panel still growing.
    LazyLoader {
        active: root.open && root.panelOpened && root.previewedEntryId !== ""

        PanelWindow {
            id: previewWindow

            // Same per-screen scale as clipWindow above.
            readonly property real uiScale: Config.uiScale(previewWindow.screen, root.shellScale)

            anchors { bottom: true; right: true }
            // 10 (screen gap, matching clipWindow's own) + 400
            // (clipWindow's width) + 10 (gap between the two panels).
            margins { bottom: Config.scaled(10, previewWindow.uiScale); right: (root.edgeGaps ? root.edgeGaps.right : 10) + Config.scaled(10, previewWindow.uiScale) + Config.scaled(400, previewWindow.uiScale) }

            // 400 max in both cases; images are always exactly that
            // square, text instead shrinks to fit its own content (down
            // to whatever a short entry actually needs) and only ever
            // grows up to this cap, past which it wraps/scrolls instead
            // of the window growing further.
            readonly property int paneMaxSize: Config.scaled(400, previewWindow.uiScale)
            // Total inset from the window edge to the actual
            // Image/Flickable content: 10px margin from outerBox to the
            // inner nested box, then another 10px from that box to the
            // content itself - twice, once per side (left+right, or
            // top+bottom).
            readonly property int panePadding: 4 * Config.scaled(10, previewWindow.uiScale)
            // Natural (unwrapped) width the text would take with no
            // width constraint at all - NoWrap means this never depends
            // on any width WE assign it, so it's safe to size the real,
            // visible TextEdit's width from this without a binding loop.
            readonly property real textNaturalWidth: naturalWidthMeasure.contentWidth
            readonly property real textContentWidth: Math.min(paneMaxSize - panePadding, textNaturalWidth)

            implicitWidth: root.previewedIsImage
                ? paneMaxSize
                : Math.min(paneMaxSize, textContentWidth + panePadding)
            implicitHeight: root.previewedIsImage
                ? paneMaxSize
                : Math.min(paneMaxSize, previewTextItem.contentHeight + panePadding)
            color: "transparent"

            // Invisible - exists purely so textNaturalWidth above has
            // something to measure against that isn't the real,
            // eventually-wrapped TextEdit (which would be circular: its
            // own width already depends on this pane's size).
            Text {
                id: naturalWidthMeasure
                visible: false
                text: root.previewText
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, previewWindow.uiScale)
            }

            // Overlay for the same reason as clipWindow above.
            WlrLayershell.namespace: "clipboard-preview"
            WlrLayershell.layer: WlrLayer.Overlay

            Component.onCompleted: outerBox.forceActiveFocus()

            Rectangle {
                id: outerBox

                focus: true

                anchors.fill: parent
                color: Config.fillcolor
                border.width: Config.scaled(2, previewWindow.uiScale)
                border.color: Config.fgcolor

                // Same shared autoCloseTimer as the main panel's own
                // HoverHandler - reading a long previewed entry without
                // touching the mouse shouldn't let the clipboard idle-
                // close out from under it.
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            autoCloseTimer.stop()
                        } else {
                            autoCloseTimer.restart()
                        }
                    }
                }

                // Inner container holding the actual copied contents -
                // its own fillcolor background + lighter inner border
                // gives the double-border "nested card" look already
                // used elsewhere in this shell (e.g. DashCard.qml).
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Config.scaled(10, previewWindow.uiScale)
                    color: Config.fillcolor
                    border.width: Config.scaled(2, previewWindow.uiScale)
                    border.color: Config.fgcolorlight

                    Image {
                        id: previewImage

                        // Opening selects the newest entry straight away,
                        // and an image entry's file may still be being
                        // written by its thumbnail's decode (see the list's
                        // delegates) - so a failed load is tried again a few
                        // times, a moment apart, by blanking the source.
                        property bool reloading: false
                        property string retriedPath: ""
                        property int retries: 0

                        visible: root.previewedIsImage
                        anchors.fill: parent
                        anchors.margins: Config.scaled(10, previewWindow.uiScale)
                        // Decoded to fit twice the pane (for a HiDPI screen),
                        // not at the picture's own size.
                        sourceSize: Qt.size(previewWindow.paneMaxSize * 2, previewWindow.paneMaxSize * 2)
                        source: (root.previewedIsImage && !previewImage.reloading) ? ("file://" + root.previewedImagePath) : ""
                        onStatusChanged: {
                            if (status !== Image.Error) return
                            if (previewImage.retriedPath !== root.previewedImagePath) {
                                previewImage.retriedPath = root.previewedImagePath
                                previewImage.retries = 0
                            }
                            if (previewImage.retries < 5) {
                                previewImage.retries++
                                previewRetryTimer.restart()
                            }
                        }
                        // Scale to fill as much of the square as possible
                        // without cropping or distorting - including
                        // upscaling an image that's smaller than the pane,
                        // which plain PreserveAspectFit already does on its
                        // own (Image always scales to its target size here).
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false

                        Timer {
                            id: previewRetryTimer
                            interval: 250
                            onTriggered: {
                                previewImage.reloading = true
                                previewImage.reloading = false
                            }
                        }
                    }

                    Flickable {
                        visible: !root.previewedIsImage
                        anchors.fill: parent
                        anchors.margins: Config.scaled(10, previewWindow.uiScale)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        // Vertical-only - previewTextItem's own width is
                        // already capped to fit (see textContentWidth
                        // above), so there's never anything to scroll
                        // sideways.
                        contentWidth: width
                        contentHeight: previewTextItem.contentHeight

                        TextEdit {
                            id: previewTextItem
                            // Bound to the pane's own computed target,
                            // not parent.width - the pane's size is
                            // DERIVED from this text, so binding back to
                            // the parent it's sizing would be circular.
                            width: previewWindow.textContentWidth
                            text: root.previewText
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.WordWrap
                            readOnly: true
                            selectByMouse: true
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, previewWindow.uiScale)
                        }
                    }
                }
            }
        }
    }
}

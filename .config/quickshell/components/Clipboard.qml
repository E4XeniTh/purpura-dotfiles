import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import "../Config.js" as Config

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

    property bool open: false

    // The LazyLoader gate below (root.open && previewedEntryId !== "")
    // only ever hides the preview WINDOW when the clipboard closes - it
    // never actually clears previewedEntryId itself, so without this the
    // very next open (via any path: the shortcut, IpcHandler, selecting
    // an entry) immediately re-satisfied that same gate and reopened the
    // preview on the same entry, looking exactly like it had never
    // closed at all.
    onOpenChanged: {
        if (!root.open) {
            root.previewedEntryId = ""
            root.previewedIsImage = false
            root.previewedImagePath = ""
            root.previewText = ""
        }
    }

    // Click-outside-to-close, without a full-screen invisible catcher
    // window that would have to consume (and so swallow) every outside
    // click just to notice one happened. Both panel windows request
    // WlrKeyboardFocus.OnDemand and their own focused Item reports its
    // activeFocus back into these two flags (PanelWindow itself has no
    // "active"/window-activation concept at all - wlr-layer-shell only
    // has keyboard-interactivity, no separate activation state the way
    // an xdg-toplevel gets - but activeFocus on the item WITHIN it still
    // genuinely tracks whether this surface currently holds real
    // keyboard focus). Hyprland hands an on-demand layer surface that
    // focus while it's actually being interacted with and takes it back
    // the moment focus legitimately moves to some other real window, so
    // "we lost focus and neither of our own two windows has it now"
    // already means "the user clicked something else" on its own, with
    // that other window's own click still reaching it completely
    // normally - nothing here ever intercepts it.
    property bool clipWindowActive: false
    property bool previewWindowActive: false

    // Debounced rather than closing the instant either window's active
    // flips false - clicking from the clipboard panel INTO the preview
    // pane (two separate windows) hands focus from one to the other,
    // and without this they'd be seen one tick apart as "both inactive"
    // in between, closing everything just for switching which of our
    // own two panels you clicked into.
    Timer {
        id: closeCheckTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (root.open && !root.clipWindowActive && !root.previewWindowActive) {
                root.open = false
            }
        }
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

    // First click on an entry previews it; clicking a DIFFERENT entry
    // just swaps which one is previewed; a second click on the SAME
    // (already-previewing) entry is what actually selects it - so a
    // quick double-click still copies+closes in one motion, same as a
    // single click used to.
    function previewOrSelectEntry(entryId, isImage, imagePath) {
        if (root.previewedEntryId === entryId) {
            root.selectEntry(entryId)
            return
        }

        root.previewedEntryId = entryId
        root.previewedIsImage = isImage
        root.previewedImagePath = imagePath
        root.previewText = ""

        if (!isImage) {
            previewTextProcess.command = ["cliphist", "decode", entryId]
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
                    return
                }
                root.lastListText = listCollector.text

                clipModel.clear()

                const lines = listCollector.text.split("\n").filter(l => l.length > 0)

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

                    clipModel.append({
                        entryId: entryId,
                        preview: preview,
                        isImage: isImage,
                        imagePath: isImage ? ("/tmp/quickshell-clip-" + entryId + ".img") : ""
                    })
                }

                if (root.pendingDeleteClose) {
                    root.pendingDeleteClose = false
                    if (clipModel.count === 0) root.open = false
                }
            }
        }
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

        stdout: StdioCollector {
            id: previewTextCollector
            onStreamFinished: root.previewText = previewTextCollector.text
        }
    }

    // Only mounted while open, same reasoning as VolumeOsd/BrightnessOsd -
    // no point keeping the panel's render tree alive for something
    // nobody's looking at.
    LazyLoader {
        active: root.open

        PanelWindow {
            id: clipWindow

            anchors { bottom: true; right: true }
            margins { bottom: 10; right: 10 }

            implicitWidth: 400
            // +20 = the 10px top + 10px bottom margins contentCol below
            // sits inside - without it, panelBox/mainRect were exactly
            // contentCol's own height with only a bottom margin applied,
            // so contentCol's top edge landed 10px above mainRect's top
            // and mainRect's clip:true cut the title row off.
            implicitHeight: Math.max(contentCol.implicitHeight + 20, 1)
            color: "transparent"

            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Component.onCompleted: {
                root.refresh()
                panelBox.forceActiveFocus()
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

                focus: true
                Keys.onEscapePressed: root.open = false

                // activeFocus (a plain Item property, always present) -
                // not PanelWindow's own "active", which doesn't exist at
                // all: wlr-layer-shell has no window-activation concept
                // the way an xdg-toplevel does, only keyboard-interactivity.
                // activeFocus still correctly tracks real keyboard focus
                // moving to/away from this surface, since that's exactly
                // what OnDemand keyboard-interactivity governs.
                onActiveFocusChanged: {
                    root.clipWindowActive = activeFocus
                    // Only ever check on LOSING focus, never on gaining
                    // it - otherwise the very first time this becomes
                    // focused (which can be the only change since window
                    // creation, if previewWindowActive still reads false
                    // at that instant) would trip the check and close
                    // the panel the moment it opens.
                    if (!activeFocus) closeCheckTimer.restart()
                }

                // Anchored to the window's bottom (not top, like
                // Notification's own top-right panel) so it grows upward
                // as it opens instead of downward off the bottom edge.
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                width: contentCol.width
                height: contentCol.implicitHeight + 20

                color: "transparent"

                Rectangle {
                    id: mainRect
                    anchors.fill: parent
                    color: Config.fillcolor
                    border.width: 2
                    border.color: Config.fgcolor
                    clip: true

                    ColumnLayout {
                        id: contentCol
                        width: 380

                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            margins: 10
                        }
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: "Clipboard"
                                color: Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: 14
                                font.bold: true
                            }

                            Text {
                                visible: clipModel.count > 0
                                text: "Clear all"
                                color: clearAllMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                                font.family: Config.fontfamily
                                font.pixelSize: 12

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
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ListView {
                            id: clipList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, 420)
                            visible: clipModel.count > 0
                            clip: true
                            spacing: 8
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
                                height: Math.max(48, contentRow.implicitHeight + 16)
                                color: entryMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                border.width: entryDelegate.isPreviewed ? 3 : 2
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
                                        margins: 8
                                    }
                                    spacing: 8

                                    Image {
                                        id: thumb
                                        visible: entryDelegate.isImage
                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 80
                                        Layout.alignment: Qt.AlignTop
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
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                    }
                                }

                                // Blur + "Previewing" overlay only ever
                                // covers THIS entry's own row - every
                                // other delegate keeps its own independent
                                // isPreviewed check, so only the one
                                // that's actually selected shows either.
                                FastBlur {
                                    anchors.fill: contentRow
                                    source: contentRow
                                    radius: 48
                                    visible: entryDelegate.isPreviewed
                                }

                                Text {
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        rightMargin: 12
                                    }
                                    visible: entryDelegate.isPreviewed
                                    text: "Copy 🖱️"
                                    color: Config.fgcolorlight
                                    font.family: Config.fontfamily
                                    font.pixelSize: 16
                                    font.bold: true
                                }

                                MouseArea {
                                    id: entryMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            root.deleteEntry(entryDelegate.entryId, entryDelegate.preview)
                                        } else {
                                            root.previewOrSelectEntry(entryDelegate.entryId, entryDelegate.isImage, entryDelegate.imagePath)
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

                        Item { height: 8 }
                    }
                }

                states: [
                    State {
                        name: "spread"
                        PropertyChanges { target: panelBox; width: 400; height: 2 }
                    },
                    State {
                        name: "open"
                        PropertyChanges { target: panelBox; width: 400; height: contentCol.implicitHeight + 20 }
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
                    panelBox.height = 4
                    panelBox.state = "spread"
                    openTimer.start()
                }

                Timer {
                    id: openTimer
                    interval: 300
                    repeat: false
                    onTriggered: panelBox.state = "open"
                }
            }
        }
    }

    // Full-content preview pane, to the left of the clipboard panel -
    // gated on root.open too (not just previewedEntryId), so closing the
    // clipboard for any reason (selecting an entry, re-pressing META + V,
    // an IpcHandler hide()) always takes this down with it instead of
    // needing every one of those paths to separately remember to clear
    // previewedEntryId.
    LazyLoader {
        active: root.open && root.previewedEntryId !== ""

        PanelWindow {
            anchors { bottom: true; right: true }
            // 10 (screen gap, matching clipWindow's own) + 400
            // (clipWindow's width) + 10 (gap between the two panels).
            margins { bottom: 10; right: 420 }

            // Fixed square - not tied to the clipboard panel's own
            // (variable) height.
            implicitWidth: 500
            implicitHeight: 500
            color: "transparent"

            // OnDemand (not None) so the previewTextItem TextEdit below
            // can actually receive real keyboard focus when clicked -
            // needed for Ctrl+C to do anything - without permanently
            // grabbing it away from the clipboard panel the way
            // Exclusive (LockScreen/PowerMenu's own choice) would.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Component.onCompleted: outerBox.forceActiveFocus()

            Rectangle {
                id: outerBox

                focus: true
                Keys.onEscapePressed: root.open = false

                onActiveFocusChanged: {
                    root.previewWindowActive = activeFocus
                    if (!activeFocus) closeCheckTimer.restart()
                }

                anchors.fill: parent
                color: Config.fillcolor
                border.width: 2
                border.color: Config.fgcolor

                // Inner container holding the actual copied contents -
                // its own fillcolor background + lighter inner border
                // gives the double-border "nested card" look already
                // used elsewhere in this shell (e.g. DashCard.qml).
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 10
                    color: Config.fillcolor
                    border.width: 2
                    border.color: Config.fgcolorlight

                    Image {
                        visible: root.previewedIsImage
                        anchors.fill: parent
                        anchors.margins: 10
                        source: root.previewedIsImage ? ("file://" + root.previewedImagePath) : ""
                        // Scale to fill as much of the square as possible
                        // without cropping or distorting - including
                        // upscaling an image that's smaller than the pane,
                        // which plain PreserveAspectFit already does on its
                        // own (Image always scales to its target size here).
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }

                    Flickable {
                        visible: !root.previewedIsImage
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        // Vertical-only - contentWidth pinned to the
                        // Flickable's own width (matching previewTextItem
                        // wrapping to that same width below) means there's
                        // never anything to scroll sideways.
                        contentWidth: width
                        contentHeight: previewTextItem.contentHeight

                        TextEdit {
                            id: previewTextItem
                            width: parent.width
                            text: root.previewText
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.WordWrap
                            readOnly: true
                            selectByMouse: true
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}

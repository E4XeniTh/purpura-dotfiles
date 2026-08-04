import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

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

    function refresh() {
        listProcess.running = true
    }

    function selectEntry(entryId) {
        selectProcess.command = ["bash", "-c", 'cliphist decode "$1" | wl-copy', "clipboard-select", entryId]
        selectProcess.running = true
        root.open = false
    }

    Process {
        id: listProcess
        command: ["cliphist", "list"]

        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                clipModel.clear()

                const lines = listCollector.text.split("\n").filter(l => l.length > 0)

                for (const line of lines) {
                    const tab = line.indexOf("\t")
                    if (tab === -1) continue

                    const entryId = line.substring(0, tab)
                    const preview = line.substring(tab + 1)
                    const isImage = /binary data/i.test(preview)

                    clipModel.append({
                        entryId: entryId,
                        preview: preview,
                        isImage: isImage,
                        imagePath: isImage ? ("/tmp/quickshell-clip-" + entryId + ".img") : ""
                    })
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
        id: wipeProcess
        command: ["cliphist", "wipe"]
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    // Only mounted while open, same reasoning as VolumeOsd/BrightnessOsd -
    // no point keeping the panel's render tree alive for something
    // nobody's looking at.
    LazyLoader {
        active: root.open

        PanelWindow {
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

            Component.onCompleted: root.refresh()

            Rectangle {
                id: panelBox

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

                                width: clipList.width
                                height: 48
                                color: entryMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor
                                border.width: 2
                                border.color: Config.fgcolor

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Image {
                                        id: thumb
                                        visible: entryDelegate.isImage
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: entryDelegate.isImage ? "Image" : entryDelegate.preview
                                        color: Config.fgcolor
                                        font.family: Config.fontfamily
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: entryMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.selectEntry(entryDelegate.entryId)
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
}

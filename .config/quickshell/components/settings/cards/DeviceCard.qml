import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../../Config.js" as Config
import "../../common"
import "../controls"

// One playback/recording device: name + mute button + volume slider inside
// a DashCard. Right-clicking anywhere on the card - including over the
// name, the mute icon, or the slider - makes it the default device, which
// gets an fgcolorlight border (the rest fgcolordark) and a [Default] tag by its name. Middle-
// clicking renames it in place, for the shell only (`names`, an
// AliasStore.qml over audioaliases.json - nothing changes for PipeWire or
// other apps): Enter keeps the name, Escape drops it, and a blank one goes
// back to the device's own.
// Left click is reserved for the mute icon/slider: this card's own
// MouseArea only accepts the right and middle buttons, so left-button
// presses fall through to whichever of those sits underneath.
DashCard {
    id: root

    required property var device
    property bool isPrimary: false
    property real uiScale: 1.0
    // The shell's names for devices, kept by PipeWire's node name - or null.
    property var names: null

    signal selected()

    // nickname is generally more human-readable than description, which is
    // generally more human-readable than the raw name - fall back down that
    // chain as each one turns out empty.
    readonly property string systemName: root.device.nickname.length > 0 ? root.device.nickname
        : root.device.description.length > 0 ? root.device.description
        : root.device.name
    readonly property string displayName: root.names ? root.names.name(root.device.name, root.systemName) : root.systemName

    property bool renaming: false

    // Once it's over the card gives up the keyboard - hidden, the name box
    // would keep it, and Escape would never reach Settings to close it.
    onRenamingChanged: {
        if (!root.renaming) renameInput.focus = false
    }

    function startRename() {
        if (!root.names) return
        root.renaming = true
        renameInput.text = root.displayName
        renameInput.selectAll()
        renameInput.forceActiveFocus()
    }

    function finishRename(newName) {
        if (!root.renaming) return
        root.renaming = false
        root.names.rename(root.device.name, newName, root.systemName)
    }

    readonly property bool muted: root.device.audio ? root.device.audio.muted : false

    border.color: root.isPrimary ? Config.fgcolorlight : Config.fgcolordark

    Column {
        anchors {
            fill: parent
            margins: Config.scaled(12, root.uiScale)
        }
        spacing: Config.scaled(8, root.uiScale)

        RowLayout {
            width: parent.width
            spacing: Config.scaled(8, root.uiScale)

            // Takes the room the tag leaves, so the tag sits at the right
            // edge and the name only elides when the card's too narrow.
            Text {
                Layout.fillWidth: true
                visible: !root.renaming
                text: root.displayName
                textFormat: Text.PlainText
                // fgcolorlight on the default device, like its border.
                color: root.isPrimary ? Config.fgcolorlight : Config.fgcolor
                font.bold: true
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(16, root.uiScale)
                elide: Text.ElideRight
            }

            TextInput {
                id: renameInput

                Layout.fillWidth: true
                visible: root.renaming
                color: Config.fgcolorlight
                selectionColor: Config.fgcolor
                selectedTextColor: "#000000"
                font.bold: true
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(16, root.uiScale)
                selectByMouse: true
                clip: true

                onAccepted: root.finishRename(renameInput.text)
                Keys.onEscapePressed: root.renaming = false
                // Clicking away keeps what was typed.
                onActiveFocusChanged: {
                    if (!activeFocus && root.renaming) root.finishRename(renameInput.text)
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.bottom
                    }
                    height: Config.scaled(1, root.uiScale)
                    color: Config.fgcolorlight
                }
            }

            Tag {
                visible: root.isPrimary
                uiScale: root.uiScale
                label: "Default"
            }
        }

        RowLayout {
            width: parent.width
            spacing: Config.scaled(8, root.uiScale)

            // Fixed-size box, not a direct RowLayout child with its own
            // anchors - IconImage/ColorOverlay need anchors.fill, and a
            // layout fights children that also try to set their own
            // geometry, same reasoning as the hint icon in AudioSettings.
            Item {
                Layout.preferredWidth: Config.scaled(32, root.uiScale)
                Layout.preferredHeight: Config.scaled(32, root.uiScale)

                IconImage {
                    id: muteIcon
                    anchors.fill: parent
                    source: Quickshell.iconPath(root.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic")
                }

                ColorOverlay {
                    anchors.fill: muteIcon
                    source: muteIcon
                    color: muteMouseArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
                }

                MouseArea {
                    id: muteMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (root.device.audio) {
                            root.device.audio.muted = !root.device.audio.muted
                        }
                    }
                }
            }

            DeviceSlider {
                Layout.fillWidth: true
                uiScale: root.uiScale
                muted: root.muted
                value: root.device.audio ? root.device.audio.volume : 0
                onMoved: (v) => {
                    if (root.device.audio) {
                        root.device.audio.volume = v
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) root.startRename()
            else root.selected()
        }

        // Scroll anywhere on the card as a shortcut for dragging the
        // slider - wheel events aren't gated by acceptedButtons, so this
        // fires independently of the right-click-to-select handling above.
        onWheel: (wheel) => {
            if (root.device.audio) {
                const step = 0.02
                const delta = wheel.angleDelta.y > 0 ? step : -step
                root.device.audio.volume = Math.max(0, Math.min(1, root.device.audio.volume + delta))
            }
        }
    }
}

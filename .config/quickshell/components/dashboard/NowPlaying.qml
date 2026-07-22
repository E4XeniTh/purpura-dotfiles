import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import "../"

// Media controls + album art, with a cava audio visualizer running behind
// it. Loaded lazily via Loader from Dashboard.qml so a wrong MPRIS/cava API
// guess only blanks this panel instead of breaking the whole shell - this
// is the least-verified part of the dashboard, check it live.
Item {
    id: root

    property var player: null

    // Picks the first available player without indexing into the model
    // directly (Mpris.players is an ObjectModel; going through a Repeater
    // is the one access pattern already proven safe elsewhere in this repo).
    Repeater {
        model: Mpris.players

        delegate: Item {
            required property var modelData

            Component.onCompleted: {
                if (!root.player) {
                    root.player = modelData
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            width: parent.width
            height: parent.width * 0.65
            border.width: 2
            border.color: Theme.fgcolor
            color: "transparent"

            Image {
                anchors.fill: parent
                source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                visible: source != ""
                asynchronous: true
            }

            Text {
                anchors.centerIn: parent
                visible: !root.player
                text: "♪"
                color: Theme.fgcolor
                font.pixelSize: 72
                font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Text {
            width: parent.width
            text: root.player && root.player.trackTitle ? root.player.trackTitle : "No media detected"
            color: Theme.fgcolor
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root.player && root.player.trackArtist ? root.player.trackArtist : ""
            color: Theme.fgcolor
            font.pixelSize: 11
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Item {
            width: 1
            height: 6   // however much space you want
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Shuffle. Recolored via ColorOverlay (same technique as the
            // weather icon in Dashboard.qml) rather than the button
            // background, so the icon glyph itself reflects on/off state.
            Rectangle {
                width: 36
                height: 36

                color: shuffleMouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                border.width: 1
                border.color: Theme.fgcolor

                IconImage {
                    id: shuffleIcon
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: Quickshell.iconPath("media-playlist-shuffle-symbolic")
                }

                ColorOverlay {
                    anchors.fill: shuffleIcon
                    source: shuffleIcon
                    color: root.player && root.player.shuffle ? Theme.fgcolor : Theme.fgcolordark
                }

                MouseArea {
                    id: shuffleMouseArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: {
                        if (root.player) {
                            root.player.shuffle = !root.player.shuffle
                        }
                    }
                }
            }

            Rectangle {
                width: 36
                height: 36

                color: prevMouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                border.width: 1
                border.color: Theme.fgcolor

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: Quickshell.iconPath("media-skip-backward-symbolic")
                }

                MouseArea {
                    id: prevMouseArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: {
                        if (root.player) {
                            root.player.previous()
                        }
                    }
                }
            }

            // Play/pause. Best-effort: assumes MprisPlayer exposes a plain
            // isPlaying bool. This is a property *read*, not a type
            // reference, so a wrong guess just always shows the play icon -
            // it can't crash the shell the way a wrong enum type name
            // would (same reasoning as the rest of this file).
            Rectangle {
                width: 36
                height: 36

                color: playMouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                border.width: 1
                border.color: Theme.fgcolor

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: Quickshell.iconPath(root.player && root.player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic")
                }

                MouseArea {
                    id: playMouseArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: {
                        if (root.player) {
                            root.player.togglePlaying()
                        }
                    }
                }
            }

            Rectangle {
                width: 36
                height: 36

                color: nextMouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                border.width: 1
                border.color: Theme.fgcolor

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: Quickshell.iconPath("media-skip-forward-symbolic")
                }

                MouseArea {
                    id: nextMouseArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: {
                        if (root.player) {
                            root.player.next()
                        }
                    }
                }
            }

            // Repeat. Same best-effort caveat as play/pause: treats
            // loopState as a plain number, with "off" assumed to be 0/
            // falsy. The click handler cycles it by arithmetic (+1 mod 3)
            // instead of naming enum values, since referencing a wrongly-
            // named enum *type* would be a hard crash, unlike a property
            // read/write. This button was previously a no-op - clicking it
            // never actually did anything.
            Rectangle {
                width: 36
                height: 36

                color: repeatMouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                border.width: 1
                border.color: Theme.fgcolor

                IconImage {
                    id: repeatIcon
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: Quickshell.iconPath("media-playlist-repeat-symbolic")
                }

                ColorOverlay {
                    anchors.fill: repeatIcon
                    source: repeatIcon
                    color: root.player && root.player.loopState ? Theme.fgcolor : Theme.fgcolordark
                }

                MouseArea {
                    id: repeatMouseArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: {
                        if (root.player) {
                            // Plain on/off, not a 3-way cycle: 0 is
                            // assumed to be "off", so this just flips
                            // between that and 1 ("repeat one").
                            root.player.loopState = root.player.loopState ? 0 : 1
                        }
                    }
                }
            }
        }
    }
}

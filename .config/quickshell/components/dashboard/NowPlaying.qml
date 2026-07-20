import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
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
                text: "N/A"
                color: Theme.fgcolor
                font.pixelSize: 96
            }
        }

        Text {
            width: parent.width
            text: root.player && root.player.trackTitle ? root.player.trackTitle : ""
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

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [
                    { icon: "media-playlist-shuffle-symbolic", action: function() { if (root.player) root.player.shuffle = !root.player.shuffle } },
                    { icon: "media-skip-backward-symbolic", action: function() { if (root.player) root.player.previous() } },
                    { icon: "media-playback-start-symbolic", action: function() { if (root.player) root.player.togglePlaying() } },
                    { icon: "media-skip-forward-symbolic", action: function() { if (root.player) root.player.next() } },
                    { icon: "media-playlist-repeat-symbolic", action: function() {} }
                ]

                delegate: Rectangle {
                    required property var modelData

                    width: 36
                    height: 36

                    color: mouseArea.containsMouse ? Theme.fgcolorhover : "transparent"
                    border.width: 1
                    border.color: Theme.fgcolor

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 18
                        source: Quickshell.iconPath(modelData.icon)
                    }

                    MouseArea {
                        id: mouseArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: modelData.action()
                    }
                }
            }
        }
    }
}

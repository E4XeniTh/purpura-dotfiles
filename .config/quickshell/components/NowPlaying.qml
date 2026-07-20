import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris

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

    property var barLevels: []

    Process {
        id: cavaProcess

        command: ["cava", "-p", Quickshell.shellDir + "/cava/config"]
        running: true

        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.split(";").filter(p => p.length > 0)
                if (parts.length > 0) {
                    root.barLevels = parts.map(p => parseInt(p, 10) || 0)
                }
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: 1

        Repeater {
            model: root.barLevels

            delegate: Rectangle {
                required property int modelData

                anchors.bottom: parent.bottom

                width: parent.width / Math.max(root.barLevels.length, 1)
                height: parent.height * (modelData / 100)

                color: Qt.rgba(0, 0, 0, 0.25)
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            width: parent.width
            height: parent.width * 0.65

            color: Qt.rgba(0, 0, 0, 0.15)

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
                text: "Nothing playing"
                color: "black"
                font.pixelSize: 12
            }
        }

        Text {
            width: parent.width
            text: root.player && root.player.trackTitle ? root.player.trackTitle : ""
            color: "black"
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root.player && root.player.trackArtist ? root.player.trackArtist : ""
            color: "black"
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

                    width: 26
                    height: 26

                    color: "transparent"
                    border.width: 1
                    border.color: "black"

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 15
                        source: Quickshell.iconPath(modelData.icon)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: modelData.action()
                    }
                }
            }
        }
    }
}

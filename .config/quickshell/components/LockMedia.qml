import QtQuick
import Quickshell.Services.Mpris
import "../Config.js" as Config

// What's playing, beside the lock screen's login box. Its own file, loaded
// through a Loader in LockScreen.qml - the same way the dashboard loads
// NowPlaying.qml - so anything wrong with MPRIS only ever costs this box,
// never the lock itself.
//
// Shows the first player that's playing, opening rightward from its left
// edge. It keeps showing that player while it closes, and closes a moment
// after playback stops rather than straight away: skipping to the next
// track can report nothing playing for an instant.
Rectangle {
    id: root

    // Set on the Loader that loads this (LockScreen.qml): the screen's
    // scale, the size to open to, and whether it may open yet - not until
    // the login box has finished opening.
    readonly property real uiScale: root.parent && root.parent.uiScale > 0 ? root.parent.uiScale : 1
    readonly property real openWidth: root.parent && root.parent.openWidth > 0 ? root.parent.openWidth : Config.scaled(400, root.uiScale)
    readonly property bool allowed: !!root.parent && root.parent.allowed === true

    readonly property var playingPlayer: Mpris.players.values.find(p => p.isPlaying) || null
    property QtObject shownPlayer: null
    property bool playing: false

    onPlayingPlayerChanged: root.update()
    Component.onCompleted: root.update()

    function update() {
        if (root.playingPlayer) {
            hideTimer.stop()
            root.shownPlayer = root.playingPlayer
            root.playing = true
        } else if (root.playing) {
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer

        interval: 1500
        repeat: false

        onTriggered: root.playing = false
    }

    // Position only updates when asked to (see MprisPlayer.position).
    Timer {
        interval: 1000
        repeat: true
        running: root.width > 0 && !!root.shownPlayer && root.shownPlayer.isPlaying

        onTriggered: root.shownPlayer.positionChanged()
    }

    width: root.allowed && root.playing ? root.openWidth : 0
    height: root.parent && root.parent.boxHeight > 0 ? root.parent.boxHeight : Config.scaled(100, root.uiScale)
    visible: width > 0

    color: Qt.rgba(0, 0, 0, 1)
    clip: true

    Behavior on width {
        NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
        }
    }

    // Full size and pinned to the edge the box opens from, so opening
    // uncovers it rather than squeezing it - the same way the login box
    // uncovers its own content.
    Item {
        id: content

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: root.openWidth

        readonly property var player: root.shownPlayer
        readonly property real pad: Config.scaled(12, root.uiScale)

        // How far into the track, 0-1, or -1 when the player doesn't say
        // how long it is.
        readonly property real progress: {
            const p = content.player
            if (!p || !p.lengthSupported || !(p.length > 0)) return -1
            return Math.max(0, Math.min(1, p.position / p.length))
        }

        Item {
            id: art

            x: content.pad
            y: content.pad
            width: content.height - 2 * content.pad
            height: art.width

            Image {
                id: artImage

                anchors.fill: parent

                source: content.player && content.player.trackArtUrl ? content.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: artImage.status === Image.Ready
            }

            Text {
                anchors.centerIn: parent

                visible: !artImage.visible
                text: "♪"
                color: Config.fgcolor
                font.pixelSize: Config.scaled(36, root.uiScale)
                font.bold: true
            }

            Rectangle {
                anchors.fill: parent

                color: "transparent"

                border.color: Config.fgcolor
                border.width: Config.scaled(2, root.uiScale)

                z: 10
            }
        }

        Column {
            anchors {
                left: art.right
                leftMargin: content.pad
                right: parent.right
                rightMargin: content.pad
                verticalCenter: parent.verticalCenter
            }

            spacing: Config.scaled(3, root.uiScale)

            Text {
                width: parent.width

                text: "Now playing" + (content.player && content.player.identity ? " · " + content.player.identity : "")
                color: Config.fgcolordarklight
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(10, root.uiScale)
                elide: Text.ElideRight
            }

            Text {
                width: parent.width

                text: content.player && content.player.trackTitle ? content.player.trackTitle : "Unknown track"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(14, root.uiScale)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                width: parent.width

                visible: text.length > 0
                text: content.player && content.player.trackArtist ? content.player.trackArtist : ""
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                elide: Text.ElideRight
            }

            Item {
                width: parent.width
                height: Config.scaled(6, root.uiScale)

                visible: content.progress >= 0

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: Config.scaled(2, root.uiScale)

                    color: Config.fgcolordark

                    Rectangle {
                        width: parent.width * Math.max(0, content.progress)
                        height: parent.height

                        color: Config.fgcolor
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent

        color: "transparent"

        border.color: Config.fgcolor
        border.width: Config.scaled(2, root.uiScale)

        z: 10
    }
}

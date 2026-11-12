import QtQuick
import Quickshell.Services.Mpris
import "../../Config.js" as Config

// What's playing, beside the lock screen's login box: the dashboard's own
// now-playing card (dashboard/NowPlaying.qml - album art, title, artist,
// the transport buttons, right-click to switch players), in a box of the
// lock screen's style with the dashboard card's 4:5 shape. Its own file,
// loaded through a Loader in LockScreen.qml - the same way the dashboard
// loads NowPlaying.qml - so anything wrong with MPRIS only ever costs this
// box, never the lock itself.
//
// Opens rightward from its left edge while something's playing. It keeps
// showing that player while it closes, and closes a moment after playback
// stops rather than straight away: skipping to the next track can report
// nothing playing for an instant.
Rectangle {
    id: root

    // Set on the Loader that loads this (LockScreen.qml): the screen's
    // scale, the size to open to, and whether it may open yet - not until
    // the login box has finished opening.
    readonly property real uiScale: root.parent && root.parent.uiScale > 0 ? root.parent.uiScale : 1
    readonly property real openWidth: root.parent && root.parent.openWidth > 0 ? root.parent.openWidth : Config.scaled(320, root.uiScale)
    readonly property real boxHeight: root.parent && root.parent.boxHeight > 0 ? root.parent.boxHeight : Config.scaled(400, root.uiScale)
    readonly property bool allowed: !!root.parent && root.parent.allowed === true

    readonly property var players: Mpris.players.values
    readonly property var playingPlayer: root.players.find(p => p.isPlaying) || null
    property bool playing: false

    onPlayingPlayerChanged: root.update()
    Component.onCompleted: root.update()

    function update() {
        if (root.playingPlayer) {
            hideTimer.stop()
            root.playing = true
            root.showPlaying()
        } else if (root.playing) {
            hideTimer.restart()
        }
    }

    // NowPlaying.qml shows the first player unless told otherwise, which
    // could be a paused one - so it's pointed at the one that's playing.
    // Right-clicking still switches, as on the dashboard.
    function showPlaying() {
        const card = nowPlaying.item
        const index = root.players.indexOf(root.playingPlayer)
        if (card && index >= 0) card.playerIndex = index
    }

    Timer {
        id: hideTimer

        interval: 1500
        repeat: false

        onTriggered: root.playing = false
    }

    width: root.allowed && root.playing ? root.openWidth : 0
    height: root.boxHeight
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
    // uncovers the card rather than squeezing it - the same way the login
    // box uncovers its own content.
    Item {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: root.openWidth

        // The dashboard's own margin around it.
        Loader {
            id: nowPlaying

            anchors {
                fill: parent
                margins: Config.scaled(12, root.uiScale)
            }

            source: "../dashboard/NowPlaying.qml"

            onLoaded: root.showPlaying()
        }

        Binding {
            target: nowPlaying.item
            property: "uiScale"
            value: root.uiScale
            when: nowPlaying.item !== null
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

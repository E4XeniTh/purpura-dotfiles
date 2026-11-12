import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config
import "IdleLogic.js" as Logic

// One monitor's dimmed screen: black at the dim opacity, the moon - with a
// padlock on the primary monitor while it's locked - and the countdown
// (primary monitor) or the monitors still active. Or nothing but black:
// the other monitors while the primary counts down to suspending without
// auto-dim.
//
// Drawn in two places - by Idle.qml's layer over the desktop, and by the
// lock screen on top of itself - so the dim is the topmost thing whether
// or not the screen's locked. See Idle.qml for why it takes both.
//
// While it's up it hides the cursor and keeps clicks from landing on
// what's underneath.
Item {
    id: root

    // Idle.qml, and the monitor this is on.
    property var idle: null
    property string screenName: ""
    property real uiScale: 1.0

    // The moon and the text. Idle.qml's layer leaves them to the lock
    // screen while it's locked.
    property bool decorated: true

    readonly property string mode: root.idle ? root.idle.overlayFor(root.screenName) : "none"
    readonly property bool shown: root.mode !== "none"
    readonly property bool isPrimary: !!root.idle && root.screenName === root.idle.primaryName

    // What it's drawn as: the mode, held through the fade out once that's
    // "none", so nothing on it changes while it fades - an all-black
    // monitor doesn't show the moon on its way out.
    property string look: root.mode
    onModeChanged: {
        if (root.mode !== "none") root.look = root.mode
    }
    // Only the handler above sets it from here on.
    Component.onCompleted: root.look = root.mode

    // Up, or still fading out. A window holding this goes by this, never by
    // `visible`: Quickshell deletes a layer window once it's hidden and
    // takes this out of it, and an item outside any window never counts as
    // visible - so a window waiting on `visible` would never come back.
    readonly property bool active: root.shown || root.opacity > 0

    // A slow fade to black, and straight back on activity. Already dimmed
    // when it's created (a lock surface coming up on a dimmed monitor), it
    // starts out dark rather than fading in - so it needs its monitor
    // from the start: one set afterwards would fade in from undimmed.
    opacity: root.shown ? 1 : 0
    visible: root.opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? 1500 : 300
            easing.type: Easing.InOutQuad
        }
    }

    // How dark the screen goes: "Dim opacity", or all the way for "black".
    // The moon and the text stay solid.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.look === "black" ? 1 : (root.idle ? root.idle.dimOpacity : 100) / 100
    }

    Column {
        anchors.centerIn: parent

        visible: root.decorated && root.look !== "black"
        spacing: Config.scaled(24, root.uiScale)

        // A crescent moon: a disc with another, offset disc cut out of it.
        // fgcolor once it's counting down, the dimmer purple while only
        // dimmed.
        Canvas {
            id: moon

            anchors.horizontalCenter: parent.horizontalCenter

            width: Config.scaled(160, root.uiScale)
            height: moon.width

            property color tint: root.look === "dimmed" ? Config.fgcolordark : Config.fgcolor

            Behavior on tint {
                ColorAnimation { duration: 400 }
            }

            onTintChanged: moon.requestPaint()
            onWidthChanged: moon.requestPaint()
            Component.onCompleted: moon.requestPaint()

            onPaint: {
                const ctx = moon.getContext("2d")
                ctx.reset()
                const r = moon.width / 2
                ctx.fillStyle = moon.tint.toString()
                ctx.beginPath()
                ctx.arc(r, r, r * 0.9, 0, 2 * Math.PI)
                ctx.fill()
                ctx.globalCompositeOperation = "destination-out"
                ctx.beginPath()
                ctx.arc(r + r * 0.42, r - r * 0.28, r * 0.74, 0, 2 * Math.PI)
                ctx.fill()
                ctx.globalCompositeOperation = "source-over"
            }

            // Locked: a small padlock in the moon's top right corner - the
            // crescent's hollow - on the primary monitor. The power menu's
            // lock icon, in the moon's colour.
            Item {
                anchors.top: parent.top
                anchors.right: parent.right

                width: Config.scaled(40, root.uiScale)
                height: Config.scaled(40, root.uiScale)
                visible: root.isPrimary && !!root.idle && root.idle.locked

                IconImage {
                    id: lockBadge

                    anchors.fill: parent
                    visible: false
                    source: Quickshell.iconPath("system-lock-screen-symbolic")
                }

                ColorOverlay {
                    anchors.fill: lockBadge
                    source: lockBadge
                    color: moon.tint
                }
            }
        }

        // The countdown to locking or suspending - the primary monitor only.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: root.isPrimary && !!root.idle && root.idle.countdown >= 0
            text: root.idle ? Logic.countdownText(root.idle.countdown, root.idle.countdownFor) : ""
            color: Config.fgcolordark
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(15, root.uiScale)
            font.italic: true
        }

        // Per-monitor and Manual dim: which monitors are still active
        // ("Show active monitors").
        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: root.look === "dimmed" && !!root.idle && root.idle.dimShowActive && root.idle.activeNames.length > 0
            text: root.idle ? Logic.activeText(root.idle.activeNames) : ""
            color: root.idle ? root.idle.darkRed : "darkred"
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(15, root.uiScale)
        }
    }

    // Hides the cursor while dimmed - back to the arrow the moment it
    // starts fading out - and keeps a click from landing on whatever's
    // underneath.
    //
    // Hovering isn't activity, though: Qt sends hover events when this
    // appears under a cursor that isn't moving, and on every frame of the
    // fade in, which would wake the very monitor that was dimming. Real
    // movement is input Idle.qml's idle monitors see, put down to the
    // monitor with focus - the one the mouse is on.
    MouseArea {
        anchors.fill: parent

        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: root.shown ? Qt.BlankCursor : Qt.ArrowCursor
    }
}

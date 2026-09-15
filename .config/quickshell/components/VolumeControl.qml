import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import "../Config.js" as Config

// Bar widget: mute icon + a horizontal "digital"/segmented volume bar
// (DigitalBar.qml - a row of lit/unlit blocks, like a level meter,
// instead of a continuous slider track) + a percentage readout - click
// or drag anywhere on the segmented area to set volume directly,
// scroll anywhere on the widget to nudge it, click the icon to toggle
// mute. Same sink-selection precedence VolumeOsd.qml uses (Dashboard's
// explicitly-picked sink overrides Pipewire's own defaultAudioSink,
// which doesn't reliably emit a change once quickshell is already
// running) - fed in from Bar.qml the same way root.dashboard already is.
Rectangle {
    id: root

    property real uiScale: 1.0
    property var dashboard: null
    // Set from Bar.qml, same reason Tray.qml needs it - so the
    // right-click playback menu below opens on the right monitor.
    property var screen: null

    readonly property var activeSink: (root.dashboard && root.dashboard.audioSelectedSinkId !== null)
        ? (Pipewire.nodes.values.find(n => n.audio && !n.isStream && n.isSink && n.id === root.dashboard.audioSelectedSinkId) ?? Pipewire.defaultAudioSink)
        : Pipewire.defaultAudioSink

    readonly property var playbackNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)

    // Right-click quick menu: pick the primary playback device without
    // opening the full Sound settings tab. Same box-grow-open PanelWindow
    // popup Tray.qml's own right-click menu uses, anchored below this
    // widget instead of below a tray icon.
    property bool menuOpen: false

    // Computed once, at the moment the menu opens (see the right-click
    // MouseArea below) - same as Tray.qml's own menuMarginLeft, rather
    // than a live binding straight to root.x from inside the popup
    // window below. A plain snapshot is what Tray.qml already proved
    // works for positioning a layer-shell popup off a sibling item's
    // geometry; a live cross-window binding to root.x here visibly
    // did not (confirmed live - the popup opened well to the left of
    // this widget instead of underneath it).
    property real menuMarginLeft: 0

    function closeMenu() {
        root.menuOpen = false
    }

    // Bind the node so its volume/muted actually update reactively -
    // same requirement VolumeOsd.qml documents for this same service.
    PwObjectTracker {
        objects: [ root.activeSink ]
    }

    readonly property bool muted: (root.activeSink && root.activeSink.audio) ? root.activeSink.audio.muted : false
    readonly property real volume: (root.activeSink && root.activeSink.audio) ? root.activeSink.audio.volume : 0

    function setVolumeFromX(mx) {
        if (!root.activeSink || !root.activeSink.audio) return
        root.activeSink.audio.volume = Math.max(0, Math.min(1, mx / bar.totalWidth))
    }

    color: "transparent"
    border.width: Config.scaled(2, root.uiScale)
    border.color: Config.fgcolor
    radius: 0

    implicitHeight: Config.scaled(34, root.uiScale)
    implicitWidth: content.implicitWidth + Config.scaled(20, root.uiScale)

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Config.scaled(8, root.uiScale)

        Item {
            width: Config.scaled(20, root.uiScale)
            height: Config.scaled(20, root.uiScale)
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
                id: volIcon
                anchors.fill: parent
                source: Quickshell.iconPath(root.muted || root.volume <= 0
                    ? "audio-volume-muted-symbolic"
                    : (root.volume < 0.5 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic"))
            }

            ColorOverlay {
                anchors.fill: volIcon
                source: volIcon
                color: iconArea.containsMouse ? Config.fgcolorlight : Config.fgcolor
            }

            MouseArea {
                id: iconArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (root.activeSink && root.activeSink.audio) {
                        root.activeSink.audio.muted = !root.activeSink.audio.muted
                    }
                }
            }
        }

        Item {
            id: segmentsBox
            width: bar.implicitWidth
            height: bar.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            // No anchors/explicit size on bar itself - it sizes to its
            // own implicitWidth/Height (computed from segmentCount/
            // segmentWidth/segmentSpacing, see DigitalBar.qml), which
            // segmentsBox above mirrors. Anchoring bar to fill
            // segmentsBox instead would be a binding cycle, since
            // segmentsBox's own size comes *from* bar in the first
            // place.
            DigitalBar {
                id: bar
                uiScale: root.uiScale
                value: root.volume
                segmentCount: 18
                // Same red-on-mute treatment as VolumeOsd.qml/DeviceSlider.qml.
                litColor: root.muted ? Config.fgcolorred : (dragArea.containsMouse ? Config.fgcolorlight : Config.fgcolor)
                unlitColor: root.muted ? Qt.darker(Config.fgcolorred, 2.5) : Config.fgcolordark
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onPressed: (mouse) => root.setVolumeFromX(mouse.x)
                onPositionChanged: (mouse) => {
                    if (pressed) root.setVolumeFromX(mouse.x)
                }
            }
        }

        // Fixed width (fits "100%") regardless of digit count, so the
        // widget's own overall width doesn't jitter as the volume changes.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Config.scaled(40, root.uiScale)
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.volume * 100) + "%"
            color: Config.fgcolor
            font.family: Config.fontfamily
            font.pixelSize: Config.scaled(13, root.uiScale)
            font.bold: true
        }
    }

    // Scroll anywhere on the widget (icon or bar) as a volume shortcut,
    // same convention DeviceCard.qml uses - acceptedButtons: NoButton so
    // this MouseArea only ever intercepts wheel events, never clicks
    // meant for iconArea/dragArea underneath it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            if (!root.activeSink || !root.activeSink.audio) return
            const step = 0.02
            const delta = wheel.angleDelta.y > 0 ? step : -step
            root.activeSink.audio.volume = Math.max(0, Math.min(1, root.activeSink.audio.volume + delta))
        }
    }

    // Right-click anywhere on the widget opens the playback-picker menu
    // below - only ever intercepts the right button, so it never
    // competes with iconArea/dragArea's own left-click handling or the
    // wheel MouseArea above.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: {
            root.menuMarginLeft = Config.scaled(10, root.uiScale) + root.x
            root.menuOpen = !root.menuOpen
        }
    }

    // Small quick menu for picking the primary playback device - same
    // box-grow-open PanelWindow popup Tray.qml's own right-click menu
    // uses, anchored below this widget instead of below a tray icon.
    PanelWindow {
        id: menuWindow

        screen: root.screen

        visible: root.menuOpen

        WlrLayershell.namespace: "volumeMenu"
        WlrLayershell.layer: WlrLayer.Overlay

        exclusiveZone: 0

        anchors {
            top: true
            left: true
        }

        margins {
            // exclusiveZone: 0 (not -1, unlike SettingsScreen.qml's own
            // full-dim overlay) means this window still gets pushed
            // below the bar's own reserved exclusive zone automatically,
            // same as Tray.qml's own menu - this is just the small extra
            // gap on top of that auto-push, not the bar's full height.
            // left is a snapshot taken when the menu opens (see the
            // right-click MouseArea above), not a live binding to
            // root.x - see menuMarginLeft's own comment for why.
            top: Config.scaled(4, root.uiScale)
            left: root.menuMarginLeft
        }

        implicitWidth: root.width
        implicitHeight: Math.max(menuColumn.height + Config.scaled(10, root.uiScale), 1)

        color: "transparent"

        Rectangle {
            id: menuBox

            width: 0
            height: 2
            color: Config.fillcolor

            states: [

                State {
                    name: "horizontal"

                    PropertyChanges {
                        target: menuBox

                        width: menuWindow.implicitWidth
                        height: 3
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: menuBox

                        width: menuWindow.implicitWidth
                        height: menuWindow.implicitHeight
                    }
                }

            ]

            transitions: [

                Transition {

                    NumberAnimation {
                        properties: "width,height"
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                }

            ]

            Item {
                anchors.fill: parent
                anchors.topMargin: Config.scaled(5, root.uiScale)
                anchors.bottomMargin: Config.scaled(5, root.uiScale)
                clip: true

                Column {
                    id: menuColumn
                    width: menuWindow.implicitWidth

                    Repeater {
                        model: ScriptModel { values: root.playbackNodes }

                        delegate: Item {
                            id: entryDelegate

                            required property var modelData

                            width: menuColumn.width
                            height: Config.scaled(32, root.uiScale)

                            readonly property bool isActive: root.activeSink && entryDelegate.modelData.id === root.activeSink.id

                            Rectangle {
                                anchors.fill: parent
                                color: entryMouse.containsMouse ? Config.fgcolordark : "transparent"

                                Text {
                                    anchors {
                                        fill: parent
                                        leftMargin: Config.scaled(10, root.uiScale)
                                        rightMargin: Config.scaled(10, root.uiScale)
                                    }

                                    verticalAlignment: Text.AlignVCenter

                                    text: entryDelegate.modelData.nickname.length > 0 ? entryDelegate.modelData.nickname
                                        : entryDelegate.modelData.description.length > 0 ? entryDelegate.modelData.description
                                        : entryDelegate.modelData.name
                                    color: entryDelegate.isActive ? Config.fgcolorlight : Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(13, root.uiScale)
                                    font.bold: entryDelegate.isActive
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: entryMouse

                                    anchors.fill: parent
                                    hoverEnabled: true

                                    onClicked: {
                                        Pipewire.preferredDefaultAudioSink = entryDelegate.modelData
                                        if (root.dashboard) root.dashboard.audioSelectedSinkId = entryDelegate.modelData.id
                                        root.closeMenu()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent

                color: "transparent"

                border.width: Config.scaled(2, root.uiScale)
                border.color: Config.fgcolor

                radius: 0

                z: 10
            }
        }

        onVisibleChanged: {
            if (visible) {
                menuBox.width = 0
                menuBox.height = 4

                menuBox.state = "horizontal"
                menuOpenTimer.start()
            }
        }

        Timer {
            id: menuOpenTimer

            // Must match the transition's duration above, so phase 1
            // (width) fully finishes before phase 2 (height) starts.
            interval: 200
            repeat: false

            onTriggered: {
                menuBox.state = "open"
            }
        }
    }
}

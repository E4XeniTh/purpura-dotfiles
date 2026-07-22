import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import "../Config.js" as Config

// Bar-row tray icons plus their right-click context menu, in one file since
// the menu needs no state beyond what a right-click on one of these icons
// provides (which QsMenuHandle, which screen, where to anchor).
Rectangle {
    id: root

    // Set from Bar.qml so right-clicked items open their menu on the
    // right monitor.
    property var screen: null

    // Was TrayMenuState.
    property var openMenu: null
    property var menuScreen: null
    property real menuMarginLeft: 0
    property real menuMarginTop: 0
    readonly property bool menuOpen: openMenu !== null

    function closeMenu() {
        openMenu = null
        menuScreen = null
    }

    color: "transparent"

    property alias trayWidth: trayRow.width
    implicitHeight: 24
    implicitWidth: trayRow.width

    IpcHandler {
        target: "trayMenu"

        // hide() only - no toggle/show. Opening a specific menu needs
        // that tray item's QsMenuHandle, its screen, and click-position
        // margins (see the right-click handler below), none of which a
        // bare IPC call carries. Closing whatever's currently open is
        // the one action that needs no context.
        function hide(): void { root.closeMenu() }
    }

    Process {
        id: killProcess
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem

                required property var modelData

                width: 26
                height: width

                Image {
                    anchors.fill: parent
                    source: trayItem.modelData.icon
                }

                MouseArea {
                    anchors.fill: parent

                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            trayItem.modelData.activate()
                        }

                        if (mouse.button === Qt.RightButton) {
                            if (root.menuOpen && root.openMenu === trayItem.modelData.menu) {
                                // Right-clicking the same item again toggles it shut.
                                root.closeMenu()
                            } else if (trayItem.modelData.menu) {
                                // Bar.qml's own margins (10 left, 10 top, 48 tall) plus
                                // this item's offset within the tray row. Keep these in
                                // sync if the bar's layout ever changes.
                                root.menuMarginLeft = 10 + trayItem.x
                                root.menuMarginTop = 4
                                root.menuScreen = root.screen
                                root.openMenu = trayItem.modelData.menu
                            } else {
                                trayItem.modelData.secondaryActivate()
                            }
                        }
                    }
                }
            }
        }
    }

    // Themed right-click context menu. This Tray instance already belongs
    // to one specific screen (set from Bar.qml below), so the popup just
    // pins to that same screen directly - no need to iterate
    // Quickshell.screens again and filter, the way a truly global overlay
    // (like PowerMenu/LockScreen) would.
    PanelWindow {
        id: menuWindow

        screen: root.screen

        visible: root.menuOpen

        WlrLayershell.namespace: "trayMenu"
        WlrLayershell.layer: WlrLayer.Overlay

        exclusiveZone: 0

        anchors {
            top: true
            left: true
        }

        margins {
            top: root.menuMarginTop
            left: root.menuMarginLeft
        }

        implicitWidth: 160
        implicitHeight: Math.max(entryColumn.height + (2 * 5), 1)

        color: "transparent"

        QsMenuOpener {
            id: opener
            menu: root.openMenu
        }

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

                        width: 160
                        height: 2
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: menuBox

                        width: 160
                        height: Math.max(entryColumn.height + (2 * 5), 1)
                    }
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

            Item {
                id: contentMask
                anchors.fill: parent
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                clip: true


                Column {
                    id: entryColumn
                    width: 160

                    Repeater {
                        model: opener.children

                        delegate: Item {
                            id: entryDelegate

                            required property var modelData

                            width: entryColumn.width
                            height: entryDelegate.modelData.isSeparator ? 9 : 28

                            Rectangle {
                                visible: entryDelegate.modelData.isSeparator

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 8
                                    rightMargin: 8
                                }

                                height: 1
                                color: Config.fgcolordark
                            }

                            Rectangle {
                                visible: !entryDelegate.modelData.isSeparator

                                anchors.fill: parent

                                color: entryMouse.containsMouse ? Config.fgcolordark : "transparent"

                                Text {
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                    }

                                    verticalAlignment: Text.AlignVCenter

                                    text: entryDelegate.modelData.isSeparator ? "" : entryDelegate.modelData.text
                                    color: entryDelegate.modelData.enabled ? Config.fgcolor : Qt.rgba(1, 1, 1, 0.35)
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: entryMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !entryDelegate.modelData.isSeparator && entryDelegate.modelData.enabled

                                    onClicked: {
                                        entryDelegate.modelData.triggered()
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

                border.width: 2
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

            // Must match the transition's duration below, so phase 1
            // (width) fully finishes before phase 2 (height) starts.
            interval: 300
            repeat: false

            onTriggered: {
                menuBox.state = "open"
            }
        }
    }
}

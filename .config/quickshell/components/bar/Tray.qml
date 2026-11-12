import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import "../../Config.js" as Config

// Bar-row tray icons plus their right-click context menu, in one file since
// the menu needs no state beyond what a right-click on one of these icons
// provides (which QsMenuHandle, which screen, where to anchor).
Rectangle {
    id: root

    // Set from Bar.qml so right-clicked items open their menu on the
    // right monitor.
    property var screen: null

    // Fed in by Bar.qml (the per-screen Config.uiScale), for the icons
    // and the context menu alike.
    property real uiScale: 1.0

    // Bar.qml's Variants instantiate one Tray per connected screen (the
    // bar's PanelWindow only shows on the primary one, but the whole
    // tree - this IpcHandler included - still gets built for every
    // screen). Left true by default so a single-instance/standalone use
    // of this component isn't affected. See `enabled` below.
    property bool isPrimary: true

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

    // Case-insensitive substring match against whichever of id/title the
    // app actually set (see Config.hiddenTrayApps) - naming isn't
    // consistent enough across tray apps to require an exact match on
    // just one field.
    function isHiddenTrayItem(item) {
        const idLower = (item.id ?? "").toLowerCase()
        const titleLower = (item.title ?? "").toLowerCase()
        return Config.hiddenTrayApps.some(name => {
            const needle = name.toLowerCase()
            return idLower.includes(needle) || titleLower.includes(needle)
        })
    }

    color: "transparent"

    property alias trayWidth: trayRow.width
    implicitHeight: Config.scaled(24, root.uiScale)
    implicitWidth: trayRow.width

    IpcHandler {
        target: "trayMenu"

        // Only the primary screen's instance actually registers -
        // every other screen's Tray would otherwise try to claim the
        // same "trayMenu" target too, and only the first one to
        // register wins ("Handler was registered but will not be used
        // because another handler is registered for target trayMenu",
        // seen live on any multi-monitor startup).
        enabled: root.isPrimary

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
        spacing: Config.scaled(8, root.uiScale)

        Repeater {
            // Filtering the model itself (not hiding delegates after
            // the fact) so trayRow's own width - and implicitWidth
            // above, which Bar.qml reads to decide how much space to
            // reserve - shrinks to match, same as any other filtered
            // list in this shell.
            model: SystemTray.items.values.filter(item => !root.isHiddenTrayItem(item))

            delegate: Item {
                id: trayItem

                required property var modelData

                width: Config.scaled(26, root.uiScale)
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
                                root.menuMarginLeft = Config.scaled(10, root.uiScale) + trayItem.x
                                root.menuMarginTop = Config.scaled(4, root.uiScale)
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

        implicitWidth: Config.scaled(160, root.uiScale)
        implicitHeight: Math.max(entryColumn.height + 2 * Config.scaled(5, root.uiScale), 1)

        color: "transparent"

        QsMenuOpener {
            id: opener
            menu: root.openMenu
        }

        Rectangle {
            id: menuBox

            width: 0
            height: Config.scaled(2, root.uiScale)
            color: Config.fillcolor

            states: [

                State {
                    name: "horizontal"

                    PropertyChanges {
                        target: menuBox

                        width: Config.scaled(160, root.uiScale)
                        height: Config.scaled(3, root.uiScale)
                    }
                },

                State {
                    name: "open"

                    PropertyChanges {
                        target: menuBox

                        width: Config.scaled(160, root.uiScale)
                        height: Math.max(entryColumn.height + 2 * Config.scaled(5, root.uiScale), 1)
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
                id: contentMask
                anchors.fill: parent
                anchors.topMargin: Config.scaled(5, root.uiScale)
                anchors.bottomMargin: Config.scaled(5, root.uiScale)
                clip: true


                Column {
                    id: entryColumn
                    width: Config.scaled(160, root.uiScale)

                    Repeater {
                        model: opener.children

                        delegate: Item {
                            id: entryDelegate

                            required property var modelData

                            width: entryColumn.width
                            height: Config.scaled(entryDelegate.modelData.isSeparator ? 9 : 28, root.uiScale)

                            Rectangle {
                                visible: entryDelegate.modelData.isSeparator

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Config.scaled(8, root.uiScale)
                                    rightMargin: Config.scaled(8, root.uiScale)
                                }

                                height: Config.scaled(1, root.uiScale)
                                color: Config.fgcolordark
                            }

                            Rectangle {
                                visible: !entryDelegate.modelData.isSeparator

                                anchors.fill: parent

                                color: entryMouse.containsMouse ? Config.fgcolordark : "transparent"

                                Text {
                                    anchors {
                                        fill: parent
                                        leftMargin: Config.scaled(10, root.uiScale)
                                        rightMargin: Config.scaled(10, root.uiScale)
                                    }

                                    verticalAlignment: Text.AlignVCenter

                                    text: entryDelegate.modelData.isSeparator ? "" : entryDelegate.modelData.text
                                    color: entryDelegate.modelData.enabled ? Config.fgcolor : Qt.rgba(1, 1, 1, 0.35)
                                    elide: Text.ElideRight
                                    // The system's default font (no Config.fontfamily
                                    // here), just scaled with the screen like the
                                    // rest of the menu.
                                    font.pointSize: (Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize : 10) * root.uiScale
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

                border.width: Config.scaled(2, root.uiScale)
                border.color: Config.fgcolor

                radius: 0

                z: 10
            }
        }

        onVisibleChanged: {
            if (visible) {
                menuBox.width = 0
                menuBox.height = Config.scaled(4, root.uiScale)

                menuBox.state = "horizontal"
                menuOpenTimer.start()
            }
        }

        Timer {
            id: menuOpenTimer

            // Must match the transition's duration below, so phase 1
            // (width) fully finishes before phase 2 (height) starts.
            interval: 200
            repeat: false

            onTriggered: {
                menuBox.state = "open"
            }
        }
    }
}

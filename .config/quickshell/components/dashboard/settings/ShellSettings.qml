import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../../../Config.js" as Config

// Shell-level settings (as opposed to Sound/Network/Bluetooth/Display,
// which all configure a piece of hardware) - one tab of
// SettingsScreen.qml's fullscreen tabbed panel (see there for the tab
// bar/coordinator). Categories down the left (only "Bar" for now,
// mirrors Network/Bluetooth's own left icon-tab strip) pick which
// group of settings shows on the right.
//
// Everything here is a plain, immediately-saved toggle - no Apply
// button, unlike ScreenSettings.qml's staged monitor edits - persisted
// to its own barsettings.json rather than monitors.json, so a Display
// tab Apply can never clobber a Bar setting (or vice versa) by
// overwriting the wrong file wholesale. WorkspaceRow.qml/WorkspaceOsd.qml/
// Bar.qml each watch that same file directly for the same reason they
// already watched monitors.json - no property-passing chain needed.
Item {
    id: root

    property real panelWidth: 800
    property real uiScale: 1.0
    property bool active: false

    anchors.fill: parent

    // 0 = Bar (only category for now).
    property int currentCategory: 0

    property var barStore: ({})

    function loadBarStore() {
        barStoreProcess.running = false
        barStoreProcess.running = true
    }

    function setBarSetting(key, value) {
        const updated = Object.assign({}, root.barStore, { [key]: value })
        root.barStore = updated
        barSettingsFile.setText(JSON.stringify(updated, null, 2) + "\n")
    }

    readonly property bool strictWorkspaceWidget: !!root.barStore.strictWorkspaceWidget
    readonly property bool showEmptyWidget: !!root.barStore.showEmptyWidget
    readonly property bool showEmptyOsd: !!root.barStore.showEmptyOsd
    // Defaults true (rather than !! which would default false) - matches
    // BrightnessControl.qml's own always-on-until-told-otherwise default,
    // so a fresh install with no barsettings.json yet still shows it.
    readonly property bool showBrightnessControl: root.barStore.showBrightnessControl !== false

    function toggleStrictWorkspaceWidget() { root.setBarSetting("strictWorkspaceWidget", !root.strictWorkspaceWidget) }
    function toggleShowEmptyWidget() { root.setBarSetting("showEmptyWidget", !root.showEmptyWidget) }
    function toggleShowEmptyOsd() { root.setBarSetting("showEmptyOsd", !root.showEmptyOsd) }
    function toggleShowBrightnessControl() { root.setBarSetting("showBrightnessControl", !root.showBrightnessControl) }

    onActiveChanged: if (root.active) root.loadBarStore()
    Component.onCompleted: root.loadBarStore()

    // Read via `cat`, same idiom ScreenSettings.qml uses for monitors.json -
    // a missing file (first run) just yields empty stdout instead of
    // needing to reason about FileView's own missing-file behavior.
    Process {
        id: barStoreProcess
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/barsettings.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.barStore = JSON.parse(text)
                } catch (e) {
                    root.barStore = {}
                }
            }
        }
    }

    // Write-only from here - WorkspaceRow.qml/WorkspaceOsd.qml/Bar.qml
    // each read this file back themselves via their own watchChanges
    // FileView, same split ScreenSettings.qml/monitorsFile already uses.
    FileView {
        id: barSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/barsettings.json"
        preload: false
    }

    Item {
        id: contentWrapper

        anchors.fill: parent

        RowLayout {
            id: contentRow

            readonly property real margins: Config.scaled(18, root.uiScale)

            anchors {
                fill: parent
                margins: contentRow.margins
            }
            spacing: Config.scaled(12, root.uiScale)

            readonly property real dividerWidth: Config.scaled(2, root.uiScale)
            readonly property real leftWidth: Config.scaled(140, root.uiScale)

            // ---------------- LEFT: categories ----------------
            ColumnLayout {
                id: categoryColumn

                Layout.preferredWidth: contentRow.leftWidth
                Layout.fillHeight: true
                spacing: Config.scaled(8, root.uiScale)

                DashCard {
                    id: barCategoryCard

                    Layout.fillWidth: true
                    Layout.preferredHeight: Config.scaled(40, root.uiScale)
                    uiScale: root.uiScale
                    color: barCategoryMouse.containsMouse ? Config.fgcolorhover : Config.fillcolor
                    border.color: root.currentCategory === 0 ? Config.fgcolorlight : Config.fgcolor

                    Text {
                        anchors.centerIn: parent
                        text: "Bar"
                        color: barCategoryCard.border.color
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(14, root.uiScale)
                        font.bold: true
                    }

                    MouseArea {
                        id: barCategoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.currentCategory = 0
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ---------------- divider ----------------
            Rectangle {
                Layout.preferredWidth: contentRow.dividerWidth
                Layout.fillHeight: true
                color: Config.fgcolor
            }

            // ---------------- RIGHT: current category's settings ----------------
            ColumnLayout {
                id: categoryContent

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Config.scaled(10, root.uiScale)

                Text {
                    text: "Bar"
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, root.uiScale)
                    font.bold: true
                }

                // ---------------- only managed workspaces in widget ----------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.scaled(8, root.uiScale)
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Only managed workspaces in widget:"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleStrictWorkspaceWidget()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.strictWorkspaceWidget ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleStrictWorkspaceWidget()
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ---------------- show empty workspaces (widget + osd) ----------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Show empty workspaces:"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true
                    }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.showEmptyWidget ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleShowEmptyWidget()
                        }
                    }

                    Text {
                        text: "In widget"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleShowEmptyWidget()
                        }
                    }

                    Item { Layout.preferredWidth: Config.scaled(16, root.uiScale) }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.showEmptyOsd ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleShowEmptyOsd()
                        }
                    }

                    Text {
                        text: "In OSD"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleShowEmptyOsd()
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ---------------- brightness control ----------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.scaled(8, root.uiScale)

                    Text {
                        text: "Brightness Control:"
                        color: Config.fgcolor
                        font.family: Config.fontfamily
                        font.pixelSize: Config.scaled(13, root.uiScale)
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleShowBrightnessControl()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Config.scaled(20, root.uiScale)
                        Layout.preferredHeight: Config.scaled(20, root.uiScale)
                        color: root.showBrightnessControl ? Config.fgcolor : Config.fillcolor
                        border.width: Config.scaled(2, root.uiScale)
                        border.color: Config.fgcolor
                        radius: 0

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleShowBrightnessControl()
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}

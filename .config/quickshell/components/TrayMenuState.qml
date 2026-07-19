pragma Singleton

import QtQuick

QtObject {

    property var menu: null
    property var screen: null

    property real marginLeft: 0
    property real marginTop: 0

    readonly property bool open: menu !== null

    function close() {
        menu = null
        screen = null
    }

}

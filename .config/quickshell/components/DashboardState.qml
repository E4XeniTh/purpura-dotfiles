pragma Singleton

import QtQuick

QtObject {

    property bool open: false
    property var screen: null

    function close() {
        open = false
        screen = null
    }

    function toggle(screen_) {
        if (open && screen === screen_) {
            close()
        } else {
            open = true
            screen = screen_
        }
    }

}

pragma Singleton

import Quickshell
import QtQuick

Singleton {
    // Transparent-ish black - deliberately independent of the accent
    // color, doesn't change when fgcolor is re-derived below.
    readonly property color fillcolor: "#aa000000"

    // Fallback until ThemeLoader.qml (loaded lazily from shell.qml) reads
    // Hyprland's col.active_border and overwrites this. Not readonly, since
    // that's exactly what needs to happen for the auto-follow to work.
    property color fgcolor: "#9600fa"

    // Derived from fgcolor via Qt's own color math, so they stay in sync
    // automatically whenever fgcolor changes - no separate hex to maintain.
    readonly property color fgcolordark: Qt.darker(fgcolor, 1.5)
    readonly property color fgcolorlight: Qt.lighter(fgcolor, 1.5)
    readonly property color fgcolorhover: Qt.darker(fgcolor, 5.0)

}

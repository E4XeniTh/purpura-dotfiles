.pragma library

// Central shell config. Import from QML as:
//   import "../Config.js" as Config      (from components/*.qml)
//   import "../../Config.js" as Config   (from components/<subfolder>/*.qml)
// then reference values as Config.fgcolor, Config.fillcolor, etc.
//
// Static values now - no more auto-following Hyprland's col.active_border
// (that was ThemeLoader.qml, removed). This is also where notification
// and options-menu settings will live once those get built.

var fillcolor = "#aa000000"
var fgcolor = "#9600fa"
var fgcolordark = Qt.darker(fgcolor, 1.5)
var fgcolorlight = Qt.lighter(fgcolor, 1.5)
var fgcolorhover = Qt.darker(fgcolor, 5.0)

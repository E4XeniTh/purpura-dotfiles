
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
var fgfillcolor = "#aa9600fa"
var fgcolordark = Qt.darker(fgcolor, 2.5)
var fgcolorlight = Qt.lighter(fgcolor, 1.55)
var fgcolorhover = Qt.darker(fgfillcolor, 2.5)

var fontfamily = "Hack"

var notificationtimeout = 5000

// Rounds px to the nearest whole pixel scaled by a component-local
// uiScale factor, clamped to never disappear entirely. Used anywhere a
// size/font was tuned at a reference resolution and needs to scale with
// the screen instead of staying a fixed pixel count.
function scaled(px, uiScale) {
    return Math.max(1, Math.round(px * uiScale))
}

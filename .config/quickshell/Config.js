
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
// Mildly dimmed fgcolorlight (not the harsh 2.5x of fgcolordark) - for
// states that are still fgcolorlight-worthy (e.g. a workspace holding a
// fullscreen app) but shouldn't compete with something that's also
// currently active/selected.
var fgcolordarklight = Qt.darker(fgcolorlight, 1.3)
var fgcolorhover = Qt.darker(fgfillcolor, 2.5)
var fgcolorred = "#e00030"

var fontfamily = "Hack"

var notificationtimeout = 5000

// Master switch for all Solaar (Logitech Unifying/Bolt) integration -
// Dashboard.qml never even starts the `solaar show` Process at all
// while this is false (not just "runs it but ignores the result"), so
// a machine without solaar installed, or a user who just doesn't want
// it polled, can turn this off entirely. Restart `qs` after changing,
// same as any other value in this file.
var solaarEnabled = true

// Tray icons to hide, matched case-insensitively as a substring against
// each item's own StatusNotifierItem id/title (whichever the app set -
// naming isn't consistent across apps, e.g. solaar's tray icon sets id
// "solaar", but plenty of others only ever set a title). Empty by
// default - add whatever you don't want cluttering the bar, e.g.:
//   var hiddenTrayApps = ["solaar", "firefox"]
var hiddenTrayApps = []

// Bar.qml's own base height, before Config.scaled()'s per-screen
// uiScale is applied to it.
var barheight = 48

// Rounds px to the nearest whole pixel scaled by a component-local
// uiScale factor, clamped to never disappear entirely. Used anywhere a
// size/font was tuned at a reference resolution and needs to scale with
// the screen instead of staying a fixed pixel count.
function scaled(px, uiScale) {
    return Math.max(1, Math.round(px * uiScale))
}

// Icon-theme battery name for a given percentage/charging state, e.g.
// "battery-040-charging-symbolic" at 43% while charging - the icon
// theme buckets in increments of 10 (battery-000 .. battery-100), not a
// per-percent name, and inserts "-charging" before the "-symbolic"
// suffix rather than having wholly separate charging icon names (the
// "-symbolic" suffix itself isn't optional - Dashboard.qml's own
// systemicons row already uses "battery-100-symbolic" as a known-good
// icon; omitting it here silently failed every lookup and fell back to
// the same generic icon regardless of percentage/charging). Used by
// BatteryControl.qml (bar widget) and BatterySettings.qml instead of
// trusting UPower's own iconName, since that's also the only source of
// an icon for Solaar/Bluetooth/UPower-tracked devices (which have no
// icon of their own) - one shared scheme for all of them.
function batteryIconName(percentage, charging) {
    const clamped = Math.max(0, Math.min(100, Math.round(percentage)))
    const bucket = Math.floor(clamped / 10) * 10
    const base = "battery-" + String(bucket).padStart(3, "0")
    return (charging ? base + "-charging" : base) + "-symbolic"
}

.pragma library

// Hyprland events that change none of what the shell works out from Hyprland:
// which window has the focus, where the windows are, what's fullscreen. A
// window's title changing - which some apps do many times a second - comes as
// windowtitle and windowtitlev2, and, when it's the focused window's, as
// activewindow and activewindowv2 again, for the same window. Then the keyboard
// layout, a window asking for attention, a submap, screen sharing, a bell. And
// workspace.lua's own ("custom"), many a second during a drag. Anything not
// named here counts, so an event Hyprland adds later counts too.
var QUIET = {
    custom: true,
    windowtitle: true,
    windowtitlev2: true,
    activelayout: true,
    urgent: true,
    submap: true,
    screencast: true,
    bell: true
}

// Whether `event` (a Hyprland raw event) can be passed over. `seen` is an object
// of the caller's own, kept from one call to the next.
//
// activewindow ("<class>,<title>") always comes just before activewindowv2
// ("<address>"), so it's passed over itself, its class kept for the
// activewindowv2 after it - which counts when the focus has moved to another
// window, or the focused window's class has changed (its icon with it), not
// when only its title has.
function quiet(event, seen) {
    if (!event) return true
    if (event.name === "activewindow") {
        const data = String(event.data)
        const comma = data.indexOf(",")
        seen.nextClass = comma >= 0 ? data.substring(0, comma) : data
        return true
    }
    if (QUIET[event.name] === true) return true
    if (event.name !== "activewindowv2") return false
    const same = seen.focused === event.data && seen.focusedClass === seen.nextClass
    seen.focused = event.data
    seen.focusedClass = seen.nextClass
    return same
}

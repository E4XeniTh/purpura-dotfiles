.pragma library

// Settings > Shortcuts' mouse, kept apart from ShortcutSettings.qml so it
// can be tested on its own.
//
// Hyprland binds a mouse button as mouse:<code>, the kernel's code for it
// (BTN_LEFT is 272), and the wheel as mouse_up, mouse_down, mouse_left and
// mouse_right (a wheel that tilts). Buttons are counted from 1 in code order:
// 1 left, 2 right, 3 middle, 4 back (BTN_SIDE), 5 forward (BTN_EXTRA), then
// 6 - 16 for the extras up to code 287 - as far as Qt names buttons, so as
// far as pressing one in the more-buttons panel can tell which it was.

var firstButtonCode = 272
var lastButton = 16

function buttonSym(number) {
    return "mouse:" + (firstButtonCode + number - 1)
}

// Drag and resize follow the mouse while a button is held, so only buttons
// (not the wheel or keys) are offered them.
function isButton(sym) {
    return typeof sym === "string" && sym.startsWith("mouse:")
}

// ---------------- the drawing ----------------
// In key units, like the keyboard: the body's left edge at `left`, as tall as
// the keyboard (6.25). Square shoulders, then a round end as wide as the body.
// LMB and RMB fill the top with the wheel between them (up, its click, down);
// + sits below the wheel, where a logo would be; Forward and Back stick out
// of the left edge, under the thumb.
var bodyWidth = 3.5
var bodyHeight = 6.25
var shoulder = 0.5
// The stretch of the left edge the side buttons cover, from Forward's top to
// Back's bottom, which the outline leaves open.
var sideTop = 3.0
var sideBottom = 4.4

function layout(left) {
    const buttons = [
        { label: "LMB", name: "Left button", sym: buttonSym(1), x: 0.2, y: 0.2, w: 1.15, h: 2.6 },
        { label: "▲", name: "Wheel up", sym: "mouse_up", x: 1.35, y: 0.45, w: 0.8, h: 0.7, small: true },
        { label: "MMB", name: "Middle button", sym: buttonSym(3), x: 1.35, y: 1.15, w: 0.8, h: 0.7, small: true },
        { label: "▼", name: "Wheel down", sym: "mouse_down", x: 1.35, y: 1.85, w: 0.8, h: 0.7, small: true },
        { label: "RMB", name: "Right button", sym: buttonSym(2), x: 2.15, y: 0.2, w: 1.15, h: 2.6 },
        { label: "+", name: "More buttons", more: true, x: 1.35, y: 2.95, w: 0.8, h: 0.7 },
        { label: "Fwd", name: "Forward", sym: buttonSym(5), x: -0.45, y: sideTop, w: 1, h: 0.7, small: true },
        { label: "Back", name: "Back", sym: buttonSym(4), x: -0.45, y: sideTop + 0.7, w: 1, h: 0.7, small: true }
    ]
    return buttons.map(b => Object.assign({}, b, { x: left + b.x, mouse: true }))
}

// ---------------- the more-buttons panel ----------------
// What + offers, in groups: the wheel's tilt, the extra buttons, and F13 -
// F24, the keys many mice with a row of extra buttons send instead (or are
// set to, in Solaar or Piper) - not on the keyboard drawn above.
var moreGroups = ["Wheel tilt", "Extra buttons", "Keys some mice send instead"]

function moreButtons() {
    const out = [
        { label: "Wheel left", name: "Wheel left", sym: "mouse_left", mouse: true, group: 0 },
        { label: "Wheel right", name: "Wheel right", sym: "mouse_right", mouse: true, group: 0 }
    ]
    for (let n = 6; n <= lastButton; n++)
        out.push({ label: String(n), name: "Button " + n, sym: buttonSym(n), mouse: true, group: 1 })
    for (let n = 13; n <= 24; n++)
        out.push({ label: "F" + n, name: "F" + n, sym: "F" + n, group: 2 })
    return out
}

// The button a press reported, from Qt's flag for it. Qt's flags run in code
// order too - LeftButton 1, RightButton 2, MiddleButton 4, BackButton 8
// (BTN_SIDE), ForwardButton 16 (BTN_EXTRA), then ExtraButton3 32 up to
// ExtraButton13 0x8000 (code 287) - so the flag's bit is the button's number.
// Empty for anything else.
function pressedSym(qtButton) {
    for (let n = 1; n <= lastButton; n++) {
        if (qtButton === Math.pow(2, n - 1)) return buttonSym(n)
    }
    return ""
}

// Which way a wheel event went, from Qt's angleDelta: y above 0 is rolled
// away (up), x above 0 tilted left. The stronger axis wins; empty for none.
function wheelSym(dx, dy) {
    if (Math.abs(dy) >= Math.abs(dx)) {
        if (dy > 0) return "mouse_up"
        if (dy < 0) return "mouse_down"
        return ""
    }
    return dx > 0 ? "mouse_left" : "mouse_right"
}

// F13 - F24 from Qt's key code. Qt.Key_F1 is 0x01000030, and the rest follow
// on from it.
var qtKeyF1 = 0x01000030

function functionKeySym(qtKey) {
    const n = qtKey - qtKeyF1 + 1
    return n >= 13 && n <= 24 ? "F" + n : ""
}

// Each mouse part's name by its sym (lowercase), from layout() and
// moreButtons() - the F-keys aren't mouse parts and keep their own.
function namesBySym(entries) {
    const names = {}
    for (const e of entries) {
        if (e.mouse && e.sym) names[e.sym.toLowerCase()] = e.name
    }
    return names
}

// A combo as the panel shows it: a mouse part by name rather than by what
// Hyprland calls it - "SUPER + mouse:272" reads "SUPER + Left button".
function prettyCombo(combo, names) {
    const parts = combo.split("+").map(p => p.trim())
    const key = parts.pop()
    return parts.concat([names[key.toLowerCase()] || key]).join(" + ")
}

// Left click on its own would take every click there is - this screen's
// too, leaving nothing to undo it with - so it needs a modifier.
function needsModifier(sym, modifiers) {
    return sym === buttonSym(1) && modifiers.length === 0
}

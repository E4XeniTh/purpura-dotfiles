.pragma library

// How NightLight.qml fades, kept apart from it so it can be tested on its
// own.
//
// hyprsunset only has a colour for every 100 K: it divides the temperature
// by 100 as a whole number before working the colour out (matrixForKelvin
// in its Hyprsunset.cpp), so 3456 K looks exactly like 3400 K. A fade can
// only move through those steps.
//
// Hyprland eases every colour change hyprsunset makes, over the length of
// its __internal_fadeCTM animation - half a second unless set, ten at most
// (hl.animation's speed tops out at 100 tenths). So a fade hands it one
// 100 K step at a time, each to glide to over the time until the fade's
// path gets there, and the screen moves smoothly from end to end. Anything
// left that fits in one glide goes as a single glide to the end.

var maxGlideMs = 10000

function level(kelvin) {
    return Math.floor(kelvin / 100) * 100
}

// A fade from `from` to `to` (mireds - see NightLight.qml) over `duration`
// ms, `elapsed` ms in, with hyprsunset showing `shown` (K, a step): the next
// thing to hand Hyprland.
//   kelvin   to glide to
//   glideMs  over this long
//   waitMs   until the next step (or the end)
//   last     this one ends the fade
// A step the path has already gone past is skipped, so a late timer (or a
// suspend mid-fade) catches up instead of crawling through every step.
function nextStep(from, to, duration, elapsed, shown) {
    const left = duration - elapsed
    const endKelvin = Math.round(1e6 / to)
    if (left <= maxGlideMs) {
        const ms = Math.max(0, left)
        return { kelvin: endKelvin, glideMs: ms, waitMs: ms, last: true }
    }

    // Mireds going up is kelvin going down: warmer.
    const warming = to > from
    const msAt = kelvin => duration * (1e6 / kelvin - from) / (to - from)
    let next = warming ? level(shown) - 100 : level(shown) + 100
    for (;;) {
        const pastEnd = warming ? next <= endKelvin : next >= endKelvin
        if (pastEnd) {
            const glide = Math.min(left, maxGlideMs)
            return { kelvin: endKelvin, glideMs: glide, waitMs: left, last: true }
        }
        const wait = msAt(next) - elapsed
        if (wait > 0) return { kelvin: next, glideMs: Math.min(wait, maxGlideMs), waitMs: wait, last: false }
        next += warming ? -100 : 100
    }
}

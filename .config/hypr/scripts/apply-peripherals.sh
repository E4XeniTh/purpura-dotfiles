#!/bin/bash
# Replays the settings saved by the quickshell General > Input settings
# panel (components/settings/ShellSettings.qml) at login, before the shell
# is up - the shell's InputDevices.qml applies the same ones again once it
# is, and after every config reload:
#  - the mouse: sensitivity and acceleration, always. Acceleration off is
#    libinput's flat profile rather than force_no_accel, which skips
#    libinput - and with it sensitivity - altogether; flat at sensitivity 0
#    moves the cursor as far as the mouse says, as force_no_accel did. No
#    saved sensitivity is 0 (hyprland.lua's own value only ever had an
#    effect without force_no_accel).
#  - the input languages (kb_layout), once some are saved - until then
#    hyprland.lua's own kb_layout stays.
#  - whether Solaar starts (default yes), replacing hyprland.lua's old
#    unconditional `hl.exec_cmd("solaar --window hide")` autostart line.
#
# All through `hyprctl eval`: this config is parsed by hyprlang's Lua
# frontend, which rejects `hyprctl keyword` outright ("keyword can't work
# with non-legacy parsers. Use eval."), same as apply-monitors.sh.
#
# Run once at startup (see hyprland.lua's autostart block).
CONF="$HOME/.config/quickshell/peripheralsettings.json"

SOLAAR_ENABLED="true"
SENSITIVITY="0"
ACCEL_PROFILE="flat"
LAYOUTS=""

if [ -f "$CONF" ]; then
    value=$(jq -r 'if (.mouseSensitivity | type) == "number"
        then (if .mouseSensitivity < -1 then -1 elif .mouseSensitivity > 1 then 1 else .mouseSensitivity end)
        else empty end' "$CONF" 2>/dev/null)
    [ -n "$value" ] && SENSITIVITY="$value"

    [ "$(jq -r '.mouseAcceleration == true' "$CONF" 2>/dev/null)" = "true" ] && ACCEL_PROFILE="adaptive"

    LAYOUTS=$(jq -r 'if (.keyboardLayouts | type) == "array"
        then [.keyboardLayouts[] | tostring | select(test("^[A-Za-z0-9_-]+$"))] | join(",")
        else empty end' "$CONF" 2>/dev/null)

    value=$(jq -r 'if .solaarStartupEnabled == false then "false" else "true" end' "$CONF" 2>/dev/null)
    [ -n "$value" ] && SOLAAR_ENABLED="$value"
fi

hyprctl eval "hl.config({ input = { force_no_accel = false, accel_profile = \"$ACCEL_PROFILE\", sensitivity = $SENSITIVITY } })"
[ -n "$LAYOUTS" ] && hyprctl eval "hl.config({ input = { kb_layout = \"$LAYOUTS\", kb_variant = \"\" } })"

[ "$SOLAAR_ENABLED" = "false" ] || solaar --window hide &

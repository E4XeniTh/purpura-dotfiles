#!/bin/bash
# Replays the peripheral settings saved by the quickshell Shell >
# Peripherals settings panel (components/dashboard/settings/
# ShellSettings.qml): mouse sensitivity via `hyprctl eval` - this config
# is parsed by hyprlang's Lua frontend, which rejects `hyprctl keyword`
# outright ("keyword can't work with non-legacy parsers. Use eval."),
# same reasoning apply-monitors.sh's own header comment explains - and
# whether Solaar autostarts at all, replacing hyprland.lua's old
# unconditional `hl.exec_cmd("solaar --window hide")` autostart line.
#
# Run once at startup (see hyprland.lua's autostart block), same as
# apply-monitors.sh, so a setting changed through the panel survives a
# restart. A missing settings file, or one with no mouseSensitivity key
# yet (first run, before the panel's slider has ever been touched),
# deliberately skips the sensitivity eval entirely rather than forcing
# some hardcoded fallback - leaving hyprland.lua's own static `input.
# sensitivity` default (set once, earlier, at config parse time) in
# effect untouched. Solaar's own default (no key yet) is enabled,
# matching hyprland.lua's previous unconditional behavior.
CONF="$HOME/.config/quickshell/peripheralsettings.json"

SOLAAR_ENABLED="true"

if [ -f "$CONF" ]; then
    sensitivity=$(jq -r 'if has("mouseSensitivity") then .mouseSensitivity else empty end' "$CONF" 2>/dev/null)
    if [ -n "$sensitivity" ] && [ "$sensitivity" != "null" ]; then
        hyprctl eval "hl.config({ input = { sensitivity = $sensitivity } })"
    fi

    value=$(jq -r 'if .solaarStartupEnabled == false then "false" else "true" end' "$CONF" 2>/dev/null)
    [ -n "$value" ] && SOLAAR_ENABLED="$value"
fi

[ "$SOLAAR_ENABLED" = "false" ] || solaar --window hide &

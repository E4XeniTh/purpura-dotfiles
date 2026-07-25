#!/bin/bash
# Replays the monitor layout saved by the quickshell Screen settings panel
# (components/dashboard/settings/ScreenSettings.qml), one hyprctl eval
# call per line - each line is already a full "hl.monitor({ ... })" Lua
# expression, since that's what ScreenSettings.qml itself writes out on
# Apply. This config is parsed by hyprlang's Lua frontend, which rejects
# `hyprctl keyword` outright ("keyword can't work with non-legacy
# parsers. Use eval."), so `eval` is the only working write path here.
#
# Run once at startup (see hyprland.lua's autostart block) so a layout
# built through the settings panel survives a restart - hyprland.lua
# itself only defines the primary display now.
CONF="$HOME/.config/hypr/monitors.conf"

[ -f "$CONF" ] || exit 0

while IFS= read -r line; do
    [ -n "$line" ] && hyprctl eval "$line"
done < "$CONF"

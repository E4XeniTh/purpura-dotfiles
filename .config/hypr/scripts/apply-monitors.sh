#!/bin/bash
# Replays the monitor layout saved by the quickshell Screen settings panel
# (components/dashboard/settings/ScreenSettings.qml), one hyprctl keyword
# call per line - each line is already in the exact
# "name,WxH@R,XxY,scale" / "name,disable" syntax hyprctl expects, since
# that's what ScreenSettings.qml itself writes out on Apply.
#
# Run once at startup (see hyprland.lua's autostart block) so a layout
# built through the settings panel survives a restart - hyprland.lua
# itself only defines the primary display now.
CONF="$HOME/.config/hypr/monitors.conf"

[ -f "$CONF" ] || exit 0

while IFS= read -r line; do
    [ -n "$line" ] && hyprctl keyword monitor "$line"
done < "$CONF"

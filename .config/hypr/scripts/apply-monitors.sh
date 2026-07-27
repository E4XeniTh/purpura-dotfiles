#!/bin/bash
# Replays the monitor layout saved by the quickshell Screen settings panel
# (components/dashboard/settings/ScreenSettings.qml), one hyprctl eval
# call per monitor entry's precomputed "line" field - each one is already
# a full "hl.monitor({ ... })" Lua expression, since that's what
# ScreenSettings.qml itself writes into every entry on Apply. This config
# is parsed by hyprlang's Lua frontend, which rejects `hyprctl keyword`
# outright ("keyword can't work with non-legacy parsers. Use eval."), so
# `eval` is the only working write path here.
#
# Also replays each monitor's "workspaces" array (workspace numbers
# pinned to it via the numbered buttons next to the mode toggle) as
# hl.workspace_rule({ workspace = "N", monitor = "Name" }) calls - same
# eval-only reasoning, and same file, since a monitor's workspace
# bindings are just as much "this monitor's saved layout" as its
# resolution/position are.
#
# Lives under quickshell's own config dir (not hypr's) since that panel
# is the only thing that reads or writes it - one JSON file combining
# what used to be a separate monitors.conf (this script's input) and
# screens.json (remembered per-monitor geometry, used only by the QML
# side).
#
# Run once at startup (see hyprland.lua's autostart block) so a layout
# built through the settings panel survives a restart - hyprland.lua
# itself only defines the primary display now.
CONF="$HOME/.config/quickshell/monitors.json"

[ -f "$CONF" ] || exit 0

jq -r '
    to_entries[] as $e
    | $e.value.line // empty,
      ( $e.value.workspaces // [] | .[] | "hl.workspace_rule({ workspace = \"" + (tostring) + "\", monitor = \"" + $e.key + "\" })" )
' "$CONF" | while IFS= read -r line; do
    [ -n "$line" ] && hyprctl eval "$line"
done

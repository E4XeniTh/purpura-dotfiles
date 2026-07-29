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

# "Remember on boot" checkbox in Screen Settings (__rememberOnBoot,
# same global-flag convention as __strictWorkspaceWidget etc. below) -
# defaults to true so a monitors.json from before this checkbox existed
# keeps replaying exactly as it always has. Explicitly false skips this
# script entirely, leaving hyprland.lua's own static hl.monitor({...})
# block as the only thing that runs - monitors.json itself is untouched
# either way, still written on every Apply.
#
# `// true` alone doesn't work here - confirmed live that jq's `//`
# falls back to the right-hand side for a literal `false` too, not just
# null/missing, which would silently ignore the checkbox entirely. Only
# `has()` actually distinguishes "key present and false" from "key
# absent".
REMEMBER_ON_BOOT=$(jq -r 'if has("__rememberOnBoot") then .__rememberOnBoot else true end' "$CONF" 2>/dev/null)
[ "$REMEMBER_ON_BOOT" = "false" ] && exit 0

# "__"-prefixed keys (__strictWorkspaceWidget, __showEmptyWidget,
# __showEmptyOsd - the global bar/OSD toggles, plain booleans not
# monitor entries, see ScreenSettings.qml) have to be filtered out
# before anything touches .line/.workspaces on them: jq raises a hard
# runtime error ("Cannot index boolean with string") the moment it
# tries to index a non-object value, which aborts the whole script with
# zero output rather than just skipping that one entry - confirmed
# live as the actual reason nothing in monitors.json was being replayed
# at startup at all once these keys existed, despite Apply's own
# hyprctl eval calls working fine (that path never goes through this
# script or jq).
jq -r '
    to_entries[]
    | select(.key | startswith("__") | not)
    | . as $e
    | $e.value.line // empty,
      ( $e.value.workspaces // [] | .[] | "hl.workspace_rule({ workspace = \"" + (tostring) + "\", monitor = \"" + $e.key + "\" })" )
' "$CONF" | while IFS= read -r line; do
    [ -n "$line" ] && hyprctl eval "$line"
done

#!/bin/bash
# Replays the monitor layout saved by the quickshell Screen settings panel
# (components/settings/ScreenSettings.qml), one hyprctl eval
# call per monitor entry's precomputed "line" field - each one is already
# a full "hl.monitor({ ... })" Lua expression, since that's what
# ScreenSettings.qml itself writes into every entry on Set Default. This config
# is parsed by hyprlang's Lua frontend, which rejects `hyprctl keyword`
# outright ("keyword can't work with non-legacy parsers. Use eval."), so
# `eval` is the only working write path here.
#
# Then hands each monitor's "workspaces" (the ones pinned to it with the
# numbered buttons, 1-5) to workspace.lua's book of workspaces, in one
# purpura.workspaces.assign() call - see WORKSPACES in ~/.config/hypr/workspace.lua.
# The book makes them persistent rules on their monitors, each monitor's lowest
# its default, so Hyprland itself keeps them there, makes the missing ones and
# moves the misplaced ones home; gives a monitor with none of 1-5 a spare; and,
# as asked here (home), switches every monitor to its default, the primary
# (Set Default's "__primary", or else the one holding workspace 1) focused last,
# so that's where the focus ends up. That replaces what this did by hand before:
# a rule line per workspace, every pinned workspace moved onto its monitor, each
# monitor switched to its lowest pin - Hyprland gives every connected monitor a
# starting workspace of its own before this runs, numbered in the order it found
# them, so a monitor monitors.json then switches off left its workspace on
# whichever monitor Hyprland picked (with DP-1 on 1 2 3, DP-2 on 4 5 and HDMI-A-1
# off, DP-2 came up showing 3).
#
# The book also writes $XDG_RUNTIME_DIR/purpura-workspaces.json, which the bar's
# workspace widget, the workspace OSD and Display settings read - so there's no
# liveworkspaces.json to seed here any more.
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

# "__"-prefixed keys have to be filtered out before anything touches
# .line/.workspaces on them: jq raises a hard runtime error ("Cannot
# index boolean with string") the moment it tries to index a
# non-object value, which aborts the whole script with zero output
# rather than just skipping that one entry - confirmed live as the
# actual reason nothing in monitors.json was being replayed at startup
# at all once these keys existed, despite Apply's own hyprctl eval
# calls working fine (that path never goes through this script or jq).
# The global bar/OSD toggles that used to live under keys like this
# (__strictWorkspaceWidget etc) have since moved to their own
# barsettings.json (see ShellSettings.qml), but Set Default does still
# write "__primary" (which monitor is primary, read back by
# Dashboard.qml) - so this filter is load-bearing, not just defensive.
jq -r '
    to_entries[]
    | select((.key | startswith("__") | not) and (.value | type == "object"))
    | .value.line // empty
' "$CONF" | while IFS= read -r line; do
    [ -n "$line" ] && hyprctl eval "$line"
done

# Hyprland takes a monitor line some moments after accepting it - a monitor
# being switched off hands its workspace to another monitor only then. Wait
# (2.5 s at most) until every connected monitor monitors.json mentions is on
# or off as it asks, so that hand-over is done before anything's moved. A
# monitor that isn't connected has nothing to wait for.
want=$(jq -c '
    [ to_entries[]
      | select((.key | startswith("__") | not) and (.value | type == "object"))
      | { name: .key, disabled: (.value.disabled == true) } ]
' "$CONF")
for _ in $(seq 1 25); do
    if hyprctl -j monitors all 2>/dev/null | jq -e --argjson want "$want" '
        . as $live
        | all($want[]; . as $w
            | ($live | map(select(.name == $w.name))) as $found
            | ($found | length) == 0 or $found[0].disabled == $w.disabled)
    ' >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

# The book's assignment: every monitor that's on, with its workspaces (whole
# numbers - the book keeps 1-5 and gives one with none a spare) and its pins (the
# same, 1-5 only), then home and the primary. Names are checked, so nothing but
# them and numbers goes into the Lua.
assign=$(jq -r '
    def valid: test("^[A-Za-z0-9_.-]{1,64}$");
    def numbers: map(select(type == "number" and . == floor));
    def table(f): map("[\"" + .key + "\"] = { " + ((.value.workspaces // []) | numbers | f | map(tostring) | join(", ")) + " }") | join(", ");
    (to_entries
        | map(select((.key | startswith("__") | not) and (.key | valid)
            and (.value | type == "object") and (.value.disabled != true)))) as $on
    | ((.__primary // "") as $saved
        | if ($on | any(.key == $saved)) then $saved
          else ([ $on[] | select((.value.workspaces // []) | any(. == 1)) | .key ][0] // "")
          end) as $primary
    | if ($on | length) == 0 then empty
      else "purpura.workspaces.assign({ " + ($on | table(.)) + " }, { "
          + ($on | table(map(select(. >= 1 and . <= 5)))) + " }, { home = true"
          + (if $primary != "" then ", primary = \"" + $primary + "\"" else "" end) + " })"
      end
' "$CONF")
[ -n "$assign" ] && hyprctl eval "$assign"

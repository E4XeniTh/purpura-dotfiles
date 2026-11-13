#!/bin/bash
# Replays the monitor layout saved by the quickshell Screen settings panel
# (components/settings/ScreenSettings.qml), one hyprctl eval
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
# A rule only steers where a workspace is created, though, and by the time
# this runs Hyprland has already given every connected monitor a starting
# workspace of its own, numbered in the order it found them - a monitor
# monitors.json then switches off included, whose workspace lands on
# whichever monitor Hyprland picks. With DP-1 on 1 2 3, DP-2 on 4 5 and
# HDMI-A-1 off, DP-2 came up showing workspace 3 (unmanaged there, and
# missing from DP-1) - so, once the monitors have settled, every pinned
# workspace that exists is moved onto its monitor (the same rule + move
# pairing ScreenSettings.qml's Apply sends), and each monitor is switched
# to its lowest pin, the primary last so focus ends up there. These moves
# were here once before (99f57f1) and went with an unrelated revert.
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
#
# Also seeds ~/.config/quickshell/liveworkspaces.json from this same
# file's own "workspaces" fields (stripped of everything else) - since
# ScreenSettings.qml's own Apply button no longer writes monitors.json
# at all (Set Default is now the only thing that does), WorkspaceRow.qml/
# WorkspaceOsd.qml read liveworkspaces.json instead for which workspace
# pins are actually live, and this is what keeps that file in sync with
# reality from the moment Hyprland starts, before this session's first
# Apply (or if there never is one) rather than leaving it stale/missing.
CONF="$HOME/.config/quickshell/monitors.json"
LIVE_CONF="$HOME/.config/quickshell/liveworkspaces.json"

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
    | select(.key | startswith("__") | not)
    | . as $e
    | $e.value.line // empty,
      ( $e.value.workspaces // [] | .[] | "hl.workspace_rule({ workspace = \"" + (tostring) + "\", monitor = \"" + $e.key + "\" })" )
' "$CONF" | while IFS= read -r line; do
    [ -n "$line" ] && hyprctl eval "$line"
done

jq '
    to_entries
    | map(select(.key | startswith("__") | not))
    | map({ (.key): { workspaces: (.value.workspaces // []) } })
    | add // {}
' "$CONF" > "$LIVE_CONF"

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

# Every pinned workspace that exists onto its monitor (one that doesn't yet
# is a harmless no-op - its rule places it when it's first opened), then each
# monitor that's on to its lowest pin, so none is left showing a leftover
# startup workspace - the primary (Set Default's "__primary", or else the
# one holding workspace 1) last, so that's where focus ends up.
jq -r '
    (to_entries
        | map(select((.key | startswith("__") | not)
            and (.value | type == "object")
            and (.value.disabled != true)
            and ((.value.workspaces // []) | length > 0)))) as $on
    | ((.__primary // "") as $saved
        | if ($on | any(.key == $saved)) then $saved
          else ([ $on[] | select(.value.workspaces | any(. == 1)) | .key ][0] // "")
          end) as $primary
    | ( $on[] | . as $e | $e.value.workspaces[]
        | "hl.dispatch(hl.dsp.workspace.move({ workspace = \"" + tostring + "\", monitor = \"" + $e.key + "\" }))" ),
      ( ($on | map(select(.key != $primary)) + map(select(.key == $primary)))[]
        | "hl.dispatch(hl.dsp.focus({ monitor = \"" + .key + "\" }))",
          "hl.dispatch(hl.dsp.focus({ workspace = \"" + (.value.workspaces | min | tostring) + "\" }))" )
' "$CONF" | while IFS= read -r line; do
    [ -n "$line" ] && hyprctl eval "$line"
done

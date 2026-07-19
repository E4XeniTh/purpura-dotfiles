#!/bin/bash
PRIMARY="DP-1"
TV="HDMI-A-1"
STATE_FILE="/tmp/hypr-display-toggle"

if [ ! -f "$STATE_FILE" ]; then
    echo "tv" > "$STATE_FILE"
fi
STATE=$(cat "$STATE_FILE")

if [ "$STATE" = "tv" ]; then
    hyprctl keyword monitor "$TV,preferred,auto,1.5"
    hyprctl keyword monitor "$PRIMARY,disable"
    echo "primary" > "$STATE_FILE"
else
    hyprctl keyword monitor "$PRIMARY,1920x1080@144,0x0,1"
    hyprctl keyword monitor "$TV,disable"
    echo "tv" > "$STATE_FILE"
fi

#!/usr/bin/env bash
# Copies a finished screenshot to the clipboard and says so. A copy of it is
# kept in the cache so that clicking the notification can save it: the hint
# tells Notification.qml which file it is, and screenshot-save.sh does the
# saving. Notification.qml also deletes the copy once it's no longer offered.
#
# usage: screenshot-finish.sh SRC
set -euo pipefail

src=$1
icon=camera-photo-symbolic
dir=${XDG_CACHE_HOME:-$HOME/.cache}/purpura/screenshots

wl-copy --type image/png < "$src"

# Failing to keep a copy only costs the offer to save, not the screenshot.
if mkdir -p "$dir" && kept=$(mktemp -p "$dir" XXXXXXXX.png) && cp "$src" "$kept"; then
    notify-send -i "$icon" -h "string:x-purpura-screenshot:$kept" \
        "Screenshot copied to clipboard." "Click to save in ~"
else
    notify-send -i "$icon" "Screenshot copied to clipboard."
fi

#!/usr/bin/env bash
# Crops one of Screenshot.qml's frozen frames (grim output written before
# the picker overlay ever appeared) and copies the result to the clipboard.
# Never touches the live screen, so the overlay can't end up in the image.
#
# usage: screenshot-crop.sh SRC X Y W H LOGICAL_W LOGICAL_H
#   X Y W H              crop rect, in logical (compositor layout) units,
#                        relative to SRC's top-left
#   LOGICAL_W LOGICAL_H  SRC's full extent in those same logical units
#
# The pixel scale comes from SRC's real pixel size against its logical
# extent rather than from any assumed monitor scale, so HiDPI, fractional
# scaling, and grim's combined all-monitor frame (rendered at the highest
# scale of any output) all map correctly.
set -euo pipefail

# Launched detached from the picker, so stderr goes nowhere useful -
# report through the same notification a successful capture uses.
fail() {
    echo "screenshot-crop: $1" >&2
    notify-send "Screenshot failed" "$1" || true
    exit 1
}

if [[ $# -ne 7 ]]; then
    echo "usage: $0 SRC X Y W H LOGICAL_W LOGICAL_H" >&2
    exit 2
fi

src=$1 x=$2 y=$3 w=$4 h=$5 lw=$6 lh=$7

# ImageMagick 7 ships `magick`; fall back to 6's separate binaries.
if command -v magick >/dev/null 2>&1; then
    identify=(magick identify)
    convert=(magick)
elif command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
    identify=(identify)
    convert=(convert)
else
    fail "Region/window capture needs ImageMagick - install the imagemagick package."
fi

read -r pw ph < <("${identify[@]}" -format '%w %h\n' "$src") || true
if [[ ! ${pw:-} =~ ^[0-9]+$ || ! ${ph:-} =~ ^[0-9]+$ ]]; then
    fail "Couldn't read the frozen frame ($src)."
fi

# Each edge is rounded independently (not origin + rounded size), so two
# adjacent selections never gain or lose a pixel between them.
geom=$(awk -v pw="$pw" -v ph="$ph" -v lw="$lw" -v lh="$lh" \
           -v x="$x" -v y="$y" -v w="$w" -v h="$h" '
    function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v) }
    function edge(v) { return v < 0 ? 0 : int(v + 0.5) }
    BEGIN {
        if (lw <= 0 || lh <= 0) exit 1
        sx = pw / lw
        sy = ph / lh
        x0 = clamp(edge(x * sx), 0, pw); x1 = clamp(edge((x + w) * sx), 0, pw)
        y0 = clamp(edge(y * sy), 0, ph); y1 = clamp(edge((y + h) * sy), 0, ph)
        if (x1 - x0 < 1 || y1 - y0 < 1) exit 1
        printf "%dx%d+%d+%d\n", x1 - x0, y1 - y0, x0, y0
    }') || fail "The selected area is empty."

# Through a temp file rather than a pipe: a failed crop piped straight
# into wl-copy would still replace the clipboard, with nothing.
out=$(mktemp --suffix=.png)
trap 'rm -f "$out"' EXIT
"${convert[@]}" "$src" -crop "$geom" +repage "png:$out" || fail "ImageMagick couldn't crop the frame."
wl-copy --type image/png < "$out"
notify-send "Screenshot copied to clipboard."

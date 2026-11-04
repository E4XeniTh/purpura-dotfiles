#!/usr/bin/env bash
# Moves a screenshot kept by screenshot-finish.sh to ~/screenshotNNN.png, one
# number past the highest already there, and says where it went.
#
# usage: screenshot-save.sh KEPT
set -uo pipefail

kept=$1
icon=accessories-screenshot-tool

fail() {
    notify-send -i "$icon" "Screenshot not saved" "$1" || true
    exit 1
}

[[ -f $kept ]] || fail "It's no longer available."

shopt -s nullglob
highest=0
for existing in "$HOME"/screenshot[0-9]*.png; do
    number=${existing##*/screenshot}
    number=${number%.png}
    if [[ $number =~ ^[0-9]+$ ]] && ((10#$number > highest)); then
        highest=$((10#$number))
    fi
done

# Claims the name first, so that two saves at once can't pick the same one.
number=$((highest + 1))
while true; do
    printf -v target '%s/screenshot%03d.png' "$HOME" "$number"
    (set -o noclobber; : > "$target") 2>/dev/null && break
    [[ -e $target ]] || fail "Couldn't write to ~."
    number=$((number + 1))
done

if ! mv -f "$kept" "$target"; then
    rm -f "$target"
    fail "Couldn't write to ~."
fi
notify-send -i "$icon" "Screenshot saved" "~/${target##*/}"

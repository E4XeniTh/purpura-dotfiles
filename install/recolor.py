#!/usr/bin/env python3
"""Recolor purpura's theme files from one highlight color to another.

Every themed config writes its accent shades as literal colors, each in
its own format. A color counts as part of the theme when its hue is
within HUE_WINDOW degrees of the current highlight and it isn't a grey.
Each such color moves the way the highlight itself moves: hue rotated by
the same amount, saturation scaled by the same factor, and lightness
remapped with 0, the highlight's own lightness and 1 as fixed points. So
the highlight becomes exactly the new color, a shade like
Qt.darker(highlight, 2.5) stays exactly that relative to it, and
near-black / near-white tints stay near-black / near-white. Everything
else (error reds, stock link blues, neutral greys) is left alone.

usage:
  recolor.py --from 9600fa --to 00c8ff FILE...
      rewrite the files in place; files no rule below covers are skipped
  recolor.py --from 9600fa --to 00c8ff --modulate
      print ImageMagick -modulate arguments making the same hue and
      saturation move on an image (lightness can't be anchored there)
"""

import argparse
import colorsys
import re
import sys
from pathlib import Path

HUE_WINDOW = 40.0      # degrees either side of the current highlight
MIN_SATURATION = 0.15  # HSL saturation below this reads as grey
MIN_CHROMA = 8         # max - min channel (0-255): near-white/black noise


def parse_hex(text):
    digits = text.lstrip("#").lower()
    if not re.fullmatch(r"[0-9a-f]{6}", digits):
        raise ValueError(f"not a 6-digit hex color: {text!r}")
    return tuple(int(digits[i:i + 2], 16) for i in (0, 2, 4))


def to_hsl(rgb):
    h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
    return h * 360, s, l


def from_hsl(h, s, l):
    rgb = colorsys.hls_to_rgb((h % 360) / 360, l, s)
    return tuple(max(0, min(255, round(c * 255))) for c in rgb)


def hue_distance(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def chroma(rgb):
    return max(rgb) - min(rgb)


class Recolor:
    def __init__(self, source, target):
        self.source, self.target = source, target
        self.sh, self.ss, self.sl = to_hsl(source)
        self.th, self.ts, self.tl = to_hsl(target)
        if self.ss < MIN_SATURATION or chroma(source) < MIN_CHROMA:
            raise ValueError("the current highlight is a grey, so its shades "
                             "can't be told apart from the theme's neutral greys")

    def in_theme(self, rgb):
        h, s, _ = to_hsl(rgb)
        return (chroma(rgb) >= MIN_CHROMA and s >= MIN_SATURATION
                and hue_distance(h, self.sh) <= HUE_WINDOW)

    def lightness(self, l):
        if l <= self.sl:
            return l * self.tl / self.sl
        return self.tl + (l - self.sl) * (1 - self.tl) / (1 - self.sl)

    def __call__(self, rgb):
        if rgb == self.source:
            return self.target
        if not self.in_theme(rgb):
            return rgb
        h, s, l = to_hsl(rgb)
        return from_hsl(h + self.th - self.sh,
                        min(1.0, s * self.ts / self.ss),
                        self.lightness(l))

    def modulate(self):
        # ImageMagick: hue 100 = unchanged, +100 = +180 degrees.
        rotation = (self.th - self.sh + 180) % 360 - 180
        return f"100,{100 * self.ts / self.ss:.1f},{100 + rotation * 100 / 180:.1f}"


# ---------------- formats ----------------
# Each handler rewrites one way of writing a color, keeping everything
# around the RGB part (alpha, spacing, letter case) as it was.

def hex_text(rgb, upper):
    text = "".join(f"{c:02x}" for c in rgb)
    return text.upper() if upper else text


def is_upper(rgb_hex, token, file_default):
    """Case of the RGB digits themselves, else of the whole token (its
    alpha), else of the file."""
    for text in (rgb_hex, token):
        letters = [c for c in text if c.isalpha()]
        if letters:
            return any(c.isupper() for c in letters)
    return file_default


def file_prefers_upper(text):
    tokens = re.findall(r"(?:#|0x|rgba?\()([0-9a-fA-F]{6,8})|\$\w+\s*=\s*([0-9a-fA-F]{6})\b", text)
    digits = "".join(a or b for a, b in tokens)
    return sum(c.isupper() for c in digits) > sum(c.islower() for c in digits)


class Counter:
    def __init__(self):
        self.changed = 0


def sub_hex(pattern, split):
    """split(digits) -> (prefix, rgb_hex, suffix) around the RGB digits."""
    def handler(text, rc, upper, count):
        def replace(m):
            prefix, rgb_hex, suffix = split(m.group(2))
            old = parse_hex(rgb_hex)
            new = rc(old)
            if new == old:
                return m.group(0)
            count.changed += 1
            return m.group(1) + prefix + hex_text(new, is_upper(rgb_hex, m.group(2), upper)) + suffix + m.group(3)
        return pattern.sub(replace, text)
    return handler


def split_rgb_alpha_last(digits):
    return "", digits[:6], digits[6:]


def split_alpha_first(digits):
    return (digits[:2], digits[2:], "") if len(digits) == 8 else ("", digits, "")


# #RRGGBB, plus 8 digits as #RRGGBBAA (CSS) or #AARRGGBB (Qt).
HASH_HEX = re.compile(r"(#)([0-9a-fA-F]{8}|[0-9a-fA-F]{6})((?![0-9a-fA-F]))")
css_hex = sub_hex(HASH_HEX, split_rgb_alpha_last)
qt_hex = sub_hex(HASH_HEX, split_alpha_first)
# hyprtoolkit: 0xAARRGGBB
argb_0x = sub_hex(re.compile(r"(0x)([0-9a-fA-F]{8})((?![0-9a-fA-F]))"), split_alpha_first)
# Hyprland: rgba(RRGGBBAA) / rgb(RRGGBB)
hypr_rgb = sub_hex(re.compile(r"((?i:rgba?)\()([0-9a-fA-F]{8}|[0-9a-fA-F]{6})(\))"), split_rgb_alpha_last)
# hypr/scheme: `$name = RRGGBB`
scheme_hex = sub_hex(re.compile(r"(^[ \t]*\$\w+[ \t]*=[ \t]*)([0-9a-fA-F]{6})([ \t]*$)", re.M),
                     split_rgb_alpha_last)


def sub_decimal(pattern):
    def handler(text, rc, upper, count):
        def replace(m):
            old = tuple(int(m.group(i)) for i in (2, 4, 6))
            if max(old) > 255:
                return m.group(0)
            new = rc(old)
            if new == old:
                return m.group(0)
            count.changed += 1
            return f"{m.group(1)}{new[0]}{m.group(3)}{new[1]}{m.group(5)}{new[2]}"
        return pattern.sub(replace, text)
    return handler


# rofi: rgba ( 150, 0, 250, 100 % )
rofi_rgb = sub_decimal(re.compile(r"((?i:rgba?)\s*\(\s*)(\d{1,3})(\s*,\s*)(\d{1,3})(\s*,\s*)(\d{1,3})"))
# KDE: Key=150,0,255 (optionally ,alpha)
kde_rgb = sub_decimal(re.compile(r"(^[^=\n\[]+=[ \t]*)(\d{1,3})(,)(\d{1,3})(,)(\d{1,3})(?=(?:,\d{1,3})?[ \t]*$)", re.M))


def rules_for(path):
    name, suffix = path.name, path.suffix
    if name == "Config.js" or "qt6ct" in path.parts:
        return [qt_hex]
    if suffix in (".css", ".svg", ".kvconfig", ".cts") or name == "kitty.conf":
        return [css_hex]
    if suffix == ".rasi":
        return [rofi_rgb, css_hex]
    if name == "kdeglobals" or suffix == ".colors":
        return [kde_rgb]
    if name in ("hyprland.lua", "hyprland.lua.example"):
        return [hypr_rgb]
    if name == "hyprtoolkit.conf":
        return [argb_0x]
    if path.parent.name == "scheme" and suffix == ".conf":
        return [scheme_hex]
    return []


def recolor_text(text, handlers, rc):
    count = Counter()
    upper = file_prefers_upper(text)
    for handler in handlers:
        text = handler(text, rc, upper, count)
    return text, count.changed


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from", dest="source", required=True, help="current highlight, e.g. 9600fa")
    parser.add_argument("--to", dest="target", required=True, help="new highlight")
    parser.add_argument("--modulate", action="store_true", help="print ImageMagick -modulate args instead")
    parser.add_argument("files", nargs="*", type=Path)
    args = parser.parse_args()

    try:
        rc = Recolor(parse_hex(args.source), parse_hex(args.target))
    except ValueError as error:
        print(f"recolor: {error}", file=sys.stderr)
        return 2

    if args.modulate:
        print(rc.modulate())
        return 0
    if rc.source == rc.target:
        return 0

    colors = files = 0
    for path in args.files:
        handlers = rules_for(path)
        if not handlers:
            continue
        # surrogateescape round-trips any byte that isn't valid UTF-8.
        text = path.read_text(encoding="utf-8", errors="surrogateescape")
        new_text, changed = recolor_text(text, handlers, rc)
        if changed:
            path.write_text(new_text, encoding="utf-8", errors="surrogateescape")
            colors += changed
            files += 1
    print(f"{colors} colors in {files} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())

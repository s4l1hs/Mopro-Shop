#!/usr/bin/env bash
# normalize-image.sh <path-to-png> — make a theme-adaptive PNG truly transparent.
#
# For a single-hue mark sitting on an opaque near-white or near-black field:
#   1. back up the original to mobile/assets/images/_originals/ (gitignored),
#   2. key the background colour to alpha=0 (fuzz-tolerant, preserves AA edges),
#   3. re-encode losslessly with oxipng,
#   4. guard the silhouette: abort + flag if the new alpha disagrees with the
#      original luminance on more than 5% of pixels.
#
# No theme-adaptive PNGs exist this turn (every asset is a brand-locked Mopro
# logo owned by MoproLogo — see assets MANIFEST.md), so this is provided for
# future single-colour icons. Requires ImageMagick 7 + oxipng.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-png>" >&2; exit 64; }
src="$1"
[ -f "$src" ] || { echo "normalize-image: no such file: $src" >&2; exit 66; }
command -v magick  >/dev/null 2>&1 || { echo "normalize-image: need ImageMagick" >&2; exit 2; }
command -v oxipng  >/dev/null 2>&1 || { echo "normalize-image: need oxipng" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
orig_dir="$ROOT/mobile/assets/images/_originals"
mkdir -p "$orig_dir"
cp "$src" "$orig_dir/$(basename "$src")"

# Pick the background colour from the corner; key it out with a small fuzz.
bg="$(magick "$src[0]" -format '%[pixel:p{0,0}]' info:)"
work="$(mktemp -t normimg).png"
magick "$src[0]" -alpha off -bordercolor "$bg" -border 1 \
  -fuzz 8% -fill none -draw "alpha 0,0 floodfill" -shave 1x1 "$work"

# Silhouette guard: compare new alpha mask vs original luminance threshold.
orig_mask="$(mktemp -t normorig).png"
new_mask="$(mktemp -t normnew).png"
magick "$src[0]" -alpha off -colorspace Gray -threshold 50% -negate "$orig_mask"
magick "$work" -alpha extract -threshold 50% "$new_mask"
disagree="$(magick compare -metric AE "$orig_mask" "$new_mask" null: 2>&1 || true)"
total="$(magick identify -format '%[fx:w*h]' "$src[0]")"
pct="$(awk -v d="${disagree:-0}" -v t="$total" 'BEGIN{ if(t>0) printf "%.2f", (d/t)*100; else print "100" }')"

if awk -v p="$pct" 'BEGIN{exit !(p>5)}'; then
  echo "normalize-image: $src — silhouette drift ${pct}% > 5%; FLAGGED, leaving original untouched." >&2
  rm -f "$work" "$orig_mask" "$new_mask"
  exit 3
fi

oxipng --opt max --strip safe --quiet "$work"
mv "$work" "$src"
rm -f "$orig_mask" "$new_mask"
echo "normalize-image: $src normalized (silhouette drift ${pct}%). Original backed up to _originals/."

#!/bin/bash
#
#  build.sh
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  Renders the cinema environments and copies them into Packages/CinemaContent as HEIC, with
#  each one's anchors file. Needs Blender (5.2 or later) in /Applications and uv, which fetches
#  Pillow, numpy and resvg-py for make_textures.py.
#
#    scripts/cinema/build.sh            # full size, for the app
#    scripts/cinema/build.sh --preview  # 2048 wide, quick look in out/
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
DEST="$ROOT/Packages/CinemaContent/Sources/CinemaContent/Environments"
# HEIC quality, picked by comparing against the rendered PNG; see README.md.
HEIC_QUALITY=88
mkdir -p "$HERE/cache" "$HERE/out"

# Poly Haven "Sunset Forest" (CC0), the view out of the tent's door and windows.
HDRI="$HERE/cache/sunset_forest_4k.hdr"
if [ ! -f "$HDRI" ]; then
	curl -sfL -o "$HDRI" https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/sunset_forest_4k.hdr
fi

# Pinned so a new release can't quietly change the artwork.
uv run --quiet --with pillow==13.0.0 --with numpy==2.5.4 --with resvg-py==0.5.0 python "$HERE/make_textures.py"

# Renders one environment script, <name>.py, and ships <name>.heic and <name>_anchors.json.
environment() {
	local name="$1"
	# Blender exits 0 when a script raises unless told otherwise, and a failed render would
	# otherwise leave the last run's image and anchors here to be shipped.
	rm -f "$HERE/out/$name.png" "$HERE/out/${name}_preview.png" "$HERE/out/${name}_anchors.json"
	if [ "$PREVIEW" = 1 ]; then
		"$BLENDER" -b --python-exit-code 1 -P "$HERE/$name.py" -- --out "$HERE/out/${name}_preview.png" --width 2048 --samples 48
		return
	fi
	"$BLENDER" -b --python-exit-code 1 -P "$HERE/$name.py" -- --out "$HERE/out/$name.png" --width 4096 --samples 160
	sips -s format heic -s formatOptions "$HEIC_QUALITY" "$HERE/out/$name.png" --out "$DEST/$name.heic" >/dev/null
	# Where the app puts its live panels; must ship with the image it was rendered with.
	cp "$HERE/out/${name}_anchors.json" "$DEST/${name}_anchors.json"
	echo "Wrote $DEST/$name.heic and ${name}_anchors.json"
}

PREVIEW=0
if [ "${1:-}" = "--preview" ]; then
	PREVIEW=1
fi

environment sar_tent

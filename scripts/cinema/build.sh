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

# Downloads a Poly Haven HDRI (CC0) into cache/ as <name>_<res>.hdr, the file an environment
# names in render_room().
hdri() {
	local name="$1" res="$2"
	local file="$HERE/cache/${name}_${res}.hdr"
	if [ ! -f "$file" ]; then
		# To a temporary name first, so a broken download is never taken for a finished one.
		curl -sfL -o "$file.part" "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/$res/${name}_${res}.hdr"
		mv "$file.part" "$file"
	fi
}

# "Sunset Forest", the view out of the tent's door and windows.
hdri sunset_forest 4k
# "Kiara 8" at sunset, the mountains round the fire lookout. 8K, since it is most of the view.
hdri kiara_8_sunset 8k
# A clear sunset sky with no horizon in it, for the lookout when the app draws real terrain.
hdri kloppenheim_06_puresky 4k

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

# Renders an HDRI alone as <name>.heic, the sky an environment with a cutout image shows behind
# its glass: sky <name> <hdri file> <rotation> <strength>.
sky() {
	local name="$1" file="$2" rotation="$3" strength="$4"
	rm -f "$HERE/out/$name.png"
	if [ "$PREVIEW" = 1 ]; then
		"$BLENDER" -b --python-exit-code 1 -P "$HERE/sky.py" -- --hdri "$file" --rotation "$rotation" --strength "$strength" --out "$HERE/out/${name}_preview.png" --width 2048 --samples 16
		return
	fi
	"$BLENDER" -b --python-exit-code 1 -P "$HERE/sky.py" -- --hdri "$file" --rotation "$rotation" --strength "$strength" --out "$HERE/out/$name.png" --width 4096 --samples 16
	sips -s format heic -s formatOptions "$HEIC_QUALITY" "$HERE/out/$name.png" --out "$DEST/$name.heic" >/dev/null
	echo "Wrote $DEST/$name.heic"
}

PREVIEW=0
if [ "${1:-}" = "--preview" ]; then
	PREVIEW=1
fi

environment sar_tent
environment ham_shack
environment fire_lookout
# The lookout's skies: the sunset it was lit by, and a clear sky with the sun in the same place
# (both suns were found by rendering each sky alone and looking for its brightest pixel) and no
# mountains in it, for behind real terrain.
sky fire_lookout_sky kiara_8_sunset_8k.hdr 3 1
sky fire_lookout_puresky kloppenheim_06_puresky_4k.hdr 5.5 1

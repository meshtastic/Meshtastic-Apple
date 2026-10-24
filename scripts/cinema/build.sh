#!/bin/bash
#
#  build.sh
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  Renders the cinema environments and copies them into Packages/CinemaContent.
#  Needs Blender (5.2 or later) in /Applications and python3 with Pillow and numpy.
#
#    scripts/cinema/build.sh            # full size, for the app
#    scripts/cinema/build.sh --preview  # 2048 wide, quick look in out/
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
DEST="$ROOT/Packages/CinemaContent/Sources/CinemaContent/Environments"
mkdir -p "$HERE/cache" "$HERE/out"

# Poly Haven "Sunset Forest" (CC0), the view out of the tent door.
HDRI="$HERE/cache/sunset_forest_4k.hdr"
if [ ! -f "$HDRI" ]; then
	curl -sfL -o "$HDRI" https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/sunset_forest_4k.hdr
fi

python3 "$HERE/make_textures.py"

if [ "${1:-}" = "--preview" ]; then
	"$BLENDER" -b -P "$HERE/sar_tent.py" -- --out "$HERE/out/preview.png" --width 2048 --samples 48
	exit 0
fi

"$BLENDER" -b -P "$HERE/sar_tent.py" -- --out "$HERE/out/sar_tent.png" --width 4096 --samples 160
sips -s format jpeg -s formatOptions 85 "$HERE/out/sar_tent.png" --out "$DEST/sar_tent.jpg" >/dev/null
echo "Wrote $DEST/sar_tent.jpg"

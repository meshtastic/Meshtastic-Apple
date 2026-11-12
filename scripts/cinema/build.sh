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

# Downloads one of NASA's Earth images (public domain) into cache/ as <file>, from its path
# under NASA's Earth Observatory image assets.
nasa() {
	local file="$1" path="$2"
	if [ ! -f "$HERE/cache/$file" ]; then
		curl -sfL -o "$HERE/cache/$file.part" "https://assets.science.nasa.gov/content/dam/science/esd/eo/images/$path"
		mv "$HERE/cache/$file.part" "$HERE/cache/$file"
	fi
}

# "Sunset Forest", the view out of the tent's door and windows.
hdri sunset_forest 4k
# "Kiara 8" at sunset, the light on the fire lookout's cab.
hdri kiara_8_sunset 8k
# A clear sunset sky with no horizon in it, over the lookout's forest view and real terrain.
hdri kloppenheim_06_puresky 4k
# The ground and the city lights in the view out of the space station's cupola: NASA's Blue Marble
# Next Generation for July, with topography and bathymetry, cut down to 16384 wide, the largest
# texture Blender's GPU render takes; and NASA's Black Marble 2016.
nasa world.topo.bathy.200407.3x21600x10800.jpg bmng/bmng-topography-bathymetry/july/world.topo.bathy.200407.3x21600x10800.jpg
nasa BlackMarble_2016_3km_gray.jpg imagerecords/144000/144897/BlackMarble_2016_3km_gray.jpg
# The clouds over the globe the app turns behind the cupola: the Blue Marble 2002 cloud layer.
nasa_feature() {
	local file="$1"
	if [ ! -f "$HERE/cache/$file" ]; then
		curl -sfL -o "$HERE/cache/$file.part" "https://assets.science.nasa.gov/content/dam/science/esd/eo/content-feature/bluemarble/images/$file"
		mv "$HERE/cache/$file.part" "$HERE/cache/$file"
	fi
}
nasa_feature cloud_combined_2048.jpg
if [ ! -f "$HERE/cache/blue_marble_july_16384.jpg" ]; then
	sips -Z 16384 -s formatOptions 95 "$HERE/cache/world.topo.bathy.200407.3x21600x10800.jpg" --out "$HERE/cache/blue_marble_july_16384.jpg" >/dev/null
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

# Renders <script>.py in one of its stones as <script>_<stone>.heic, and ships <script>_anchors.json,
# which is the same for every stone: stone_environment <script> <stone>.
stone_environment() {
	local script="$1" stone="$2"
	local name="${script}_${stone}"
	rm -f "$HERE/out/$name.png" "$HERE/out/${name}_preview.png" "$HERE/out/${name}_anchors.json"
	if [ "$PREVIEW" = 1 ]; then
		"$BLENDER" -b --python-exit-code 1 -P "$HERE/$script.py" -- --out "$HERE/out/${name}_preview.png" --width 2048 --samples 48 --stone "$stone"
		return
	fi
	"$BLENDER" -b --python-exit-code 1 -P "$HERE/$script.py" -- --out "$HERE/out/$name.png" --width 4096 --samples 160 --stone "$stone"
	sips -s format heic -s formatOptions "$HEIC_QUALITY" "$HERE/out/$name.png" --out "$DEST/$name.heic" >/dev/null
	# Every stone shares one anchors file, so a stone whose anchors differ from one rendered
	# earlier in this run is an error.
	if [ "${STONE_ANCHORS:-}" = "$script" ] && ! cmp -s "$HERE/out/${name}_anchors.json" "$DEST/${script}_anchors.json"; then
		echo "error: ${name}_anchors.json differs from the other stones' anchors" >&2
		exit 1
	fi
	cp "$HERE/out/${name}_anchors.json" "$DEST/${script}_anchors.json"
	STONE_ANCHORS="$script"
	echo "Wrote $DEST/$name.heic and ${script}_anchors.json"
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

# Renders <script>.py as <name>.heic, a view that needs no HDRI, which an environment with a cutout
# image shows behind its glass: painted <name> <script>.
painted() {
	local name="$1" script="$2"
	rm -f "$HERE/out/$name.png"
	if [ "$PREVIEW" = 1 ]; then
		"$BLENDER" -b --python-exit-code 1 -P "$HERE/$script.py" -- --out "$HERE/out/${name}_preview.png" --width 2048 --samples 32
		return
	fi
	"$BLENDER" -b --python-exit-code 1 -P "$HERE/$script.py" -- --out "$HERE/out/$name.png" --width 4096 --samples 128
	sips -s format heic -s formatOptions "$HEIC_QUALITY" "$HERE/out/$name.png" --out "$DEST/$name.heic" >/dev/null
	echo "Wrote $DEST/$name.heic"
}

# Renders <script>.py as <name>.heic, a landscape an environment with a cutout image shows behind
# its glass: view <name> <script> <hdri file> <rotation> <strength>.
view() {
	local name="$1" script="$2" file="$3" rotation="$4" strength="$5"
	rm -f "$HERE/out/$name.png"
	if [ "$PREVIEW" = 1 ]; then
		"$BLENDER" -b --python-exit-code 1 -P "$HERE/$script.py" -- --hdri "$file" --rotation "$rotation" --strength "$strength" --out "$HERE/out/${name}_preview.png" --width 2048 --samples 32
		return
	fi
	"$BLENDER" -b --python-exit-code 1 -P "$HERE/$script.py" -- --hdri "$file" --rotation "$rotation" --strength "$strength" --out "$HERE/out/$name.png" --width 4096 --samples 128
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
# The lookout's skies, both with the sun where the Kiara sunset that lights the cab has it (each
# sun was found by rendering the sky alone and looking for its brightest pixel): forested ridges
# seen from the tower under a clear sunset, and that clear sky alone, for behind real terrain.
view fire_lookout_sky forest_view kloppenheim_06_puresky_4k.hdr 5.5 1
sky fire_lookout_puresky kloppenheim_06_puresky_4k.hdr 5.5 1
# The castle tower, lit as the lookout is so it shares the lookout's skies, in each of its stones.
stone_environment castle_tower gray
stone_environment castle_tower pink
# The lighthouse, lit by the same sunset as the lookout turned so the sun is low over the sea on the
# viewer's left, and its skies with the sun in the same place: the sea seen from the lantern, and
# the clear sky alone, for behind real terrain.
environment lighthouse
view lighthouse_sky sea_view kloppenheim_06_puresky_4k.hdr 131.5 1
sky lighthouse_puresky kloppenheim_06_puresky_4k.hdr 131.5 1
# The city rooftop, lit by the clear sunset the lookout's skies are painted from, at their turn:
# behind real buildings it shows fire_lookout_puresky, and with none, a made-up city under that sky.
environment city_rooftop
view city_rooftop_sky city_view kloppenheim_06_puresky_4k.hdr 5.5 1

# The sky deck, lit as the rooftop is, so it shares the rooftop's skies: its streets show under the
# glass floor.
environment sky_deck

# The space station's module under its cupola, lit by its own lights, and Earth from orbit, the
# view behind its windows.
environment space_cupola
painted space_earth space_earth
# The globe the app turns behind the cupola's windows: its ground, its night side's city lights and
# its clouds, as textures. space_earth above stays as the view shown if they can't be loaded.
# A preview leaves the shipped textures alone, like the rooms.
if [ "$PREVIEW" = 0 ]; then
	uv run --quiet --with pillow==13.0.0 --with numpy==2.5.4 python "$HERE/earth_textures.py"
	for name in space_earth_ground space_earth_lights space_earth_clouds; do
		sips -s format heic -s formatOptions "$HEIC_QUALITY" "$HERE/out/$name.png" --out "$DEST/$name.heic" >/dev/null
		echo "Wrote $DEST/$name.heic"
	done
fi

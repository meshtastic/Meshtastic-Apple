# Cinema environments

The 360° images the visionOS cinema wraps around the viewer. Each is rendered in Blender from a script here, so it can be rebuilt and changed, and so we know where every part of it came from.

Run `build.sh` to render them at full size and copy them into `Packages/CinemaContent`. Run `build.sh --preview` for a quick 2048-wide render in `out/`. It needs Blender 5.2 or later in /Applications, and python3 with Pillow and numpy.

## Search and rescue tent

`sar_tent.py` models a 5 × 7 m frame tent at dusk and renders it as an equirectangular panorama from a seated viewer at its middle. The center of the image is the front wall, left plain for the app window. The comms table is on the left, the door and map table on the right, and gear along the back.

Sources:

- The tent, furniture, gear and lighting are modeled in `sar_tent.py`.
- The topo map, the team status board and the laptop screens are drawn by `make_textures.py`. Board lettering uses macOS's Chalkboard font.
- The forest seen through the door is the "Sunset Forest" HDRI from Poly Haven (https://polyhaven.com/a/sunset_forest), released under CC0. `build.sh` downloads it into `cache/`.

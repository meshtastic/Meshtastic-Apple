# Cinema environments

The 360° images the visionOS cinema wraps around the viewer. Each is rendered in Blender from a script here, so it can be rebuilt and changed, and so we know where every part of it came from.

Run `build.sh` to render them at full size and copy them into `Packages/CinemaContent`. Run `build.sh --preview` for a quick 2048-wide render in `out/`. It needs Blender 5.2 or later in /Applications, and python3 with Pillow and numpy.

## Search and rescue tent

`sar_tent.py` models a 5 × 7 m frame tent at dusk and renders it as an equirectangular panorama from a seated viewer at its middle. The center of the image is the front wall, left plain for the app window. The comms table is on the left, the door and map table on the right. The floor is left clear. The whiteboard behind the viewer's left shoulder is blank: the app draws the live team roster over it.

The render also writes `sar_tent_anchors.json`, which `build.sh` copies next to the image. It says where each board the app draws on sits, relative to the camera, in RealityKit's axes. The app places its panels from it, so moving a board in `sar_tent.py` and re-rendering moves the panel with it. The app pushes each panel out along the lines from the camera until it sits just inside the backdrop sphere, and grows it to match, so it covers the same part of the view and has the same stereo depth as the painted tent around it.

Sources:

- The tent, furniture, gear and lighting are modeled in `sar_tent.py`.
- The topo map, the whiteboard and the laptop screens are drawn by `make_textures.py`.
- The forest seen through the door is the "Sunset Forest" HDRI from Poly Haven (https://polyhaven.com/a/sunset_forest), released under CC0. `build.sh` downloads it into `cache/`.

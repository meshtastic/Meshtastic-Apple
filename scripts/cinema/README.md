# Cinema environments

The 360° images the visionOS cinema wraps around the viewer. Each is rendered in Blender from a script here, so it can be rebuilt and changed, and so we know where every part of it came from.

Run `build.sh` to render them at full size and copy them into `Packages/CinemaContent` as HEIC. Run `build.sh --preview` for a quick 2048-wide render in `out/`. It needs Blender 5.2 or later in /Applications and [uv](https://docs.astral.sh/uv/), which fetches Pillow, numpy and resvg-py for `make_textures.py`.

## The tent and its furnishings

The scenes are split in two:

- `tent_base.py` is the tent every environment shares: a 5.6 × 5.6 m frame tent, with the viewer in the middle about 2.8 m from every wall, with canvas walls, clear vinyl windows, a groundsheet floor, the string lights, the Meshtastic branding, the dusk forest outside, the seated camera, the render settings, and the anchors file. Its `Layout` says where the windows, banner, poster and plaque go.
- An environment script, such as `sar_tent.py`, adds its own furniture, lights and boards in a `furnish(layout)` function and calls `tent_base.render(furnish)`.

Blender's +Y is the image's center: the front wall, left plain for the app window. +X is the viewer's right and Z is up, with the viewer at the origin at seated eye height.

### Adding an environment

1. Copy `sar_tent.py` to `<name>.py` and change `furnish()`. Keep the front wall clear. To move the windows or the branding away from your furniture, pass your own `tent_base.Layout(...)` to `render()`; set an item to None to leave it out. `furnish()` gets the same layout.
2. For each board the app should draw on, make a plane and call `anchor("<id>", plane, width, height)`. The plane's +X is the board's right and its +Z faces the viewer.
3. Add `environment <name>` at the end of `build.sh` and run it. It writes `<name>.heic` and `<name>_anchors.json` into `Packages/CinemaContent`.
4. Add a case to `CinemaEnvironment` with `imageName` set to `<name>`.

Since the camera, eye height and axes come from `tent_base.py`, the anchors an environment writes line up with its image the same way the tent's do.

## Search and rescue tent

`sar_tent.py` furnishes the tent as a search and rescue command post. The comms table is on the left, with the "Comms equipment provided by Meshtastic Solutions" plaque and Chirpy's poster on the wall above it. The door and the map table are on the right, with a lit work lamp hanging over the map and a mesh node on a tripod by the door. The Meshtastic banner hangs on the back wall, behind the viewer. There is a clear vinyl window high on each side wall, with its cover rolled up above it; the vinyl catches soft reflections of the string lights. The floor is a ripstop groundsheet with seams, fold creases and a darker band at the walls, and nothing on it but the tables, the tripod and the whiteboard's stand. The whiteboard behind the viewer's left shoulder is blank: the app draws the live team roster over it. A hidden light on the board makes the painted board as bright as the panel the app draws, so the frame around the panel matches it.

The render also writes `sar_tent_anchors.json`, which `build.sh` copies next to the image. It says where each board the app draws on sits, relative to the camera, in RealityKit's axes. The app places its panels from it, so moving a board and re-rendering moves the panel with it. The app pushes each panel out along the lines from the camera until it sits just inside the backdrop sphere, and grows it to match, so it covers the same part of the view and has the same stereo depth as the painted tent around it.

## The front wall

The panorama sits on a 50 m sphere, so in stereo everything in it looks far away, while the app window is about 2 m from the viewer. To make the window look set into the wall, the render also writes the front wall on its own, `<name>_front.png`, which `build.sh` ships as `<name>_front.heic`. The app draws it as a flat wall just behind the window, at the window's depth, with a black frame round the window, and turns the tent so the painted front wall faces the window. The front wall stays in the panorama too, behind it.

The image is a perspective view from the seat, cropped to the wall: 5.6 m wide, from the floor to the ridge, at about 400 pixels per meter. From the seat it lines up with the panorama exactly, including the bits of the corner tables and the last string-light bulbs that are in front of the wall, which a flat-on (orthographic) view would leave out. The anchors file gives the wall's distance from the camera, the part of the wall's plane the image covers (`bounds`) and the wall's outline, a pentagon because of the gable. The app shrinks it about the viewer's eye by the window's distance over the wall's (2.8 m), so it covers the same part of the view as the painted wall.

## HEIC

`build.sh` converts the rendered PNG with `sips` at HEIC quality 88. That quality was picked by decoding the HEIC and comparing it with the PNG (PSNR and SSIM, over the whole image and over crops of the canvas, the banner, the plaque, the forest through the door and a window), and by looking at the same crops side by side. Quality 88 matched or beat the old JPEG at quality 85 in every crop, and no difference from the PNG could be seen in the crops at 3× zoom. For the tent at 4096 × 2048:

| | Size | PSNR (whole / forest through the door) | SSIM (whole / forest) |
|---|---|---|---|
| PNG | 8.5 MB | | |
| JPEG 85 (before) | 653 KB | 47.9 / 43.5 dB | 0.9922 / 0.976 |
| HEIC 80 | 235 KB | 47.6 / 42.3 dB | 0.9920 / 0.971 |
| HEIC 88 | 352 KB | 48.2 / 43.6 dB | 0.9926 / 0.978 |

`sips` gives the same file for every quality from 80 to 85.

## Sources

- The tent, furniture and lighting are modeled in `tent_base.py` and `sar_tent.py`.
- The topo map, the whiteboard and the laptop screens are drawn by `make_textures.py`.
- The banner, poster and plaque use the app's own artwork, rasterized from its SVGs by `make_textures.py` with resvg (the `resvg-py` package; chosen because it needs no system libraries, unlike cairosvg, and keeps transparency, unlike `qlmanage`): the Meshtastic mark (`Meshtastic/Resources/AppIcon.icon/Assets/Meshtastic Logo.svg`), the wordmark (`meshtastic-wordmark-white.imageset`), Chirpy (`Chirpy.imageset`) and the Meshtastic Solutions mark (`MeshtasticSolutionsMark.imageset`). The plaque follows the layout of the one in the visionOS Hardware Showcase.
- The forest seen through the door and the windows is the "Sunset Forest" HDRI from Poly Haven (https://polyhaven.com/a/sunset_forest), released under CC0. `build.sh` downloads it into `cache/`.

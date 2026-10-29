# Cinema environments

The 360° images the visionOS cinema wraps around the viewer. Each is rendered in Blender from a script here, so it can be rebuilt and changed, and so we know where every part of it came from.

Run `build.sh` to render them at full size and copy them into `Packages/CinemaContent` as HEIC. Run `build.sh --preview` for a quick 2048-wide render in `out/`. It needs Blender 5.2 or later in /Applications and [uv](https://docs.astral.sh/uv/), which fetches Pillow, numpy and resvg-py for `make_textures.py`.

## How the scenes are built

- `room_base.py` is what every environment shares, whatever the room: the seated camera at the origin, the sky and light from an HDRI, the render settings, `anchor()` and `screen_anchor()`, the anchors file, and small helpers for building the scene. `render_room(build, hdri)` starts an empty scene, calls `build()`, renders and writes the anchors. The build fails if `build()` places no screen or the HDRI isn't in `cache/`.
- `tent_base.py` builds the tent on top of that: a 5.6 × 5.6 m frame tent, with the viewer in the middle about 2.8 m from every wall, with canvas walls, clear vinyl windows, a groundsheet floor, the string lights, the Meshtastic branding, the dusk forest outside, and the "screen" anchor on the front wall where the app puts its screen (an anchor only; nothing is drawn there). Its `Layout` says where the windows, banner, poster and plaque go.
- An environment script, such as `sar_tent.py`, adds its own furniture, lights and boards in a `furnish(layout)` function and calls `tent_base.render(furnish)`.

Blender's +Y is the image's center: where the screen goes, on the tent's plain front wall. +X is the viewer's right and Z is up, with the viewer at the origin at seated eye height.

### Adding an environment

See [Cinema Environments](../../docs/developer/cinema-environments.md) for what makes a place work in the cinema and the rules for its assets.

1. For a tent, copy `sar_tent.py` to `<name>.py` and change `furnish()`. Keep the front wall clear. To move the windows or the branding away from your furniture, pass your own `tent_base.Layout(...)` to `render()`; set an item to None to leave it out. `furnish()` gets the same layout.
   For any other room, write `<name>.py` with a `build()` that makes the room and calls `screen_anchor(center, rotation)` on a plain surface the viewer faces, and end it with `room_base.render_room(build, "<hdri file>")`. Like `sar_tent.py`, it adds its own folder to `sys.path` before importing from `room_base`; the guide has a starting script.
2. For each board the app should draw on, make a plane and call `anchor("<id>", plane, width, height)`. The plane's +X is the board's right and its +Z faces the viewer.
3. For a new HDRI, add `hdri <polyhaven-name> <resolution>` to `build.sh`. It downloads to `cache/<name>_<resolution>.hdr`.
4. Add `environment <name>` at the end of `build.sh` and run it. It writes `<name>.heic` and `<name>_anchors.json` into `Packages/CinemaContent`.
5. Add a case to `CinemaEnvironment` with `imageName` set to `<name>`.

Since the camera, eye height and axes come from `room_base.py`, the anchors an environment writes line up with its image the same way the tent's do.

## Search and rescue tent

`sar_tent.py` furnishes the tent as a search and rescue command post. The comms table is on the left, with the "Comms equipment provided by Meshtastic Solutions" plaque on the wall above it. The door is on the right, with a SenseCAP Solar Node on a tripod just past it (the app's own model of it, `Meshtastic/Resources/DeviceModels/seeed_solar.usdz`) and a blank print in a thin dark frame on the wall beside it, hung from the eave. The map table is on the back wall to the right, with a lit work lamp hanging over it. The Meshtastic banner hangs on the back wall, behind the viewer, with Chirpy's poster to its left. There is a clear vinyl window high on each side wall, with its cover rolled up above it; the vinyl catches soft reflections of the string lights. The floor is a ripstop groundsheet with seams, fold creases and a darker band at the walls, and nothing on it but the tables, the tripod and the whiteboard's stand. The whiteboard behind the viewer's left shoulder is blank: the app draws the live team roster over it. The print is blank too: the app draws the latest trace route's share card on it. A hidden light on each makes the painted board as bright as the panel the app draws, so the frame around the panel matches it.

The render also writes `sar_tent_anchors.json`, which `build.sh` copies next to the image. It says where each board the app draws on sits, relative to the camera, in RealityKit's axes. The app places its panels from it, so moving a board and re-rendering moves the panel with it. The app pushes each panel out along the lines from the camera until it sits just inside the backdrop sphere, and grows it to match, so it covers the same part of the view and has the same stereo depth as the painted tent around it.

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

- The tent, furniture and lighting are modeled in `room_base.py`, `tent_base.py` and `sar_tent.py`.
- The topo map and the whiteboard are drawn by `make_textures.py`.
- The banner, poster and plaque use the app's own artwork, rasterized from its SVGs by `make_textures.py` with resvg (the `resvg-py` package; chosen because it needs no system libraries, unlike cairosvg, and keeps transparency, unlike `qlmanage`): the Meshtastic mark (`Meshtastic/Resources/AppIcon.icon/Assets/Meshtastic Logo.svg`), the wordmark (`meshtastic-wordmark-white.imageset`), Chirpy (`Chirpy.imageset`) and the Meshtastic Solutions mark (`MeshtasticSolutionsMark.imageset`). The plaque follows the layout of the one in the visionOS Hardware Showcase.
- The forest seen through the door and the windows is the "Sunset Forest" HDRI from Poly Haven (https://polyhaven.com/a/sunset_forest), released under CC0. `build.sh` downloads it into `cache/`.

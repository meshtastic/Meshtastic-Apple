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

`sar_tent.py` furnishes the tent as a search and rescue command post. The comms table is on the left, with the "Comms equipment provided by Meshtastic Solutions" plaque on the wall above it. The door is on the right, with a SenseCAP Solar Node on a tripod just past it (the app's own model of it, `Meshtastic/Resources/DeviceModels/seeed_solar.usdz`) and a blank print in a thin dark frame on the wall beside it, hung from the eave. The map table is on the back wall to the right, with a lit work lamp hanging over it. The Meshtastic banner hangs on the back wall, behind the viewer. Chirpy's poster is pinned to the front wall, to the left of the screen. There is a clear vinyl window high on each side wall, with its cover rolled up above it; the vinyl catches soft reflections of the string lights. The floor is a ripstop groundsheet with seams, fold creases and a darker band at the walls, and nothing on it but the tables, the tripod and the two whiteboards' stands. The whiteboard behind the viewer's left shoulder is blank: the app draws the live team roster over it. The print is blank too: the app draws the latest trace route's share card on it. A second, portrait whiteboard stands at the front wall to the right of the screen: the app draws the nodes' status messages over it. A hidden light on each makes the painted board as bright as the panel the app draws, so the frame around the panel matches it.

The render also writes `sar_tent_anchors.json`, which `build.sh` copies next to the image. It says where each board the app draws on sits, relative to the camera, in RealityKit's axes. The app places its panels from it, so moving a board and re-rendering moves the panel with it. The app pushes each panel out along the lines from the camera until it sits just inside the backdrop sphere, and grows it to match, so it covers the same part of the view and has the same stereo depth as the painted tent around it.

## Ham shack

`ham_shack.py` builds an amateur radio shack on `room_base.py`, with no tent: a 5.4 × 5.4 m room, every wall 2.7 m from the viewer, with knotty pine paneling, a dark green carpet and a flush ceiling light. The front wall is plain plaster for the screen, with Chirpy's poster to its left and a portrait whiteboard, net control's check-in board, to its right: the app draws the nodes' status messages on it.

- **Left wall:** the operating desk runs along it. On the desk:
  - an HF radio with its amber display on the 20 meter FT8 frequency
  - a power supply and an SWR meter
  - a desk mic and a straight key
  - a computer running FT8
  - the open log and an arm lamp
  - three Meshtastic radios, from the app's own models at real size: a T-Deck, a T1000-E and a WisMesh Pocket

  Coax runs up the wall to a feedthrough panel. Above the back of the desk is a shelf with two stacks of radios, each on a different band, with headphones hung under it and round UTC and local clocks above it. The whiteboard the app draws the team roster on is above the front of the desk, and a band plan chart hangs past the far end of the desk.
- **Right wall:** a paneled door, then a double-hung window looking out on the dusk forest and a lattice tower with a beam and a vertical. The print the app draws the latest trace route on hangs between the door and the front corner.
- **Back wall:** the Meshtastic banner and a corkboard of QSL cards over a bookcase of made-up ham books (*SWR: It's Fine*, *The Joy of Coax*, *Morse Code in 30 Years* and more, by authors like Anne Tenna and Watt Ever), with four stood face out on top. The titles and authors are in `ham_books.py`.

The QSL cards, the clock dials, the radio displays, the meter faces, the FT8 screen, the band plan and the book spines and covers are drawn by `make_textures.py`. The QSL cards and the FT8 screen show no call signs, so none belongs to a real station.

## Fire lookout

`fire_lookout.py` builds a fire lookout on `room_base.py`, with no tent: a 4.6 × 4.6 m glass-walled cab on a 34 m tower on a summit, with a low wall all round, windows above it on every side, a wide sill shelf under them, and a catwalk with a railing outside, low enough that the sill hides it from the seat. The storm shutters are all propped open as awnings, tipped up more steeply than the line of sight through the top of the glass from the seat, so they stay out of the view; the eaves are short so the shutters clear them. The screen hangs in the two middle bays in front, the whiteboards the app draws the team roster and the nodes' status messages on in two bays on the left, and the print it draws the latest trace route on in one on the right, all with the view round them. Inside are the fire finder, a cot with a sleeping bag and pillow, a box stove on a hearth pad with split firewood stacked beside it, a stool, a lit kerosene lantern, and on the sill binoculars, a mug, the logbook, a radio and a T-Echo; outside, a Solar Node on the railing.

The image is a cutout (`render_room(..., cutout=True)`): the sunset HDRI lights the cab but isn't painted, so the image is transparent through the glass, reflections and all. The app draws a sky sphere behind it: `fire_lookout_sky.heic`, the view from the tower that `forest_view.py` renders (forested slopes falling away to valleys and blue ridges, under the clear sunset sky below); or, when it draws real terrain from the elevation tiles downloaded for the spatial map, `fire_lookout_puresky.heic`, a clear sunset sky turned so its sun is in the same place (each sun was found by rendering the sky alone and looking for its brightest pixel). The app shades that terrain to the same sun (`CinemaEnvironment.sun`), and takes the cab's front to face 156° true, so the sunset is in the west-northwest.

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

- The tent, the ham shack, their furniture and lighting are modeled in `room_base.py`, `tent_base.py`, `sar_tent.py` and `ham_shack.py`.
- The radios on the shack's desk and the Solar Node in the tent are the app's own device models from `Meshtastic/Resources/DeviceModels`.
- The topo map, the whiteboard and the ham shack's cards, clocks, displays, meters and chart are drawn by `make_textures.py`.
- The banner, poster and plaque use the app's own artwork, rasterized from its SVGs by `make_textures.py` with resvg (the `resvg-py` package; chosen because it needs no system libraries, unlike cairosvg, and keeps transparency, unlike `qlmanage`): the Meshtastic mark (`Meshtastic/Resources/AppIcon.icon/Assets/Meshtastic Logo.svg`), the wordmark (`meshtastic-wordmark-white.imageset`), Chirpy (`Chirpy.imageset`) and the Meshtastic Solutions mark (`MeshtasticSolutionsMark.imageset`). The plaque follows the layout of the one in the visionOS Hardware Showcase.
- The forest seen through the door and the windows is the "Sunset Forest" HDRI from Poly Haven (https://polyhaven.com/a/sunset_forest), released under CC0. `build.sh` downloads it into `cache/`.
- The lookout's cab is lit by the "Kiara 8 Sunset" HDRI from Poly Haven (https://polyhaven.com/a/kiara_8_sunset), CC0; the sky over the forest view and behind real terrain is "Kloppenheim 06 (Pure Sky)" from Poly Haven (https://polyhaven.com/a/kloppenheim_06_puresky), CC0.
- The display of the lookout's radio on its sill is drawn by `make_textures.py`. The T-Echo and the Solar Node are the app's own models.

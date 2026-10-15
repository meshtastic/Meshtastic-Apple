# Device models

Builds real-size `.usdz` models of devices from the front-view SVGs on the
flasher, for the visionOS app and for `public/models/devices/` in web-flasher.

```bash
scripts/device-models/build.sh                 # build every spec, check, render
scripts/device-models/build.sh thinknode_m1    # just one
scripts/device-models/build.sh --install       # also copy into Meshtastic/Resources/DeviceModels
scripts/device-models/publish-flasher.sh       # open a web-flasher PR with out/*.usdz and a GLB of each
```

Needs `uv` (`brew install uv`); the Python packages are fetched on first run.
Review `out/contact-sheet.html` before installing or publishing. The build
lists any vendor SVGs in the API that don't have a spec yet.

Each model takes its name from its SVG (`thinknode_m1.svg` → `thinknode_m1.usdz`),
so a device's `images` entry maps to its model by swapping the extension. The
copyright notice is written into every file's layer metadata. The models are only
bundled in the visionOS build (`EXCLUDED_SOURCE_FILE_NAMES` in `project.yml`).

## Specs

`specs/<svg name>.toml` gives the real size and, optionally, how to build parts.

```toml
[size]
width_mm = 51.6          # published dimensions of the device
height_mm = 82.0
depth_mm = 26.3
covers = "case, excludes antenna"
source = "https://…"     # where the numbers came from
confidence = "vendor"    # vendor, retailer or estimated
```

By default the drawing is scaled so its width matches `width_mm`. The outline
is extruded to `depth_mm`, and each color region sits on the front as a thin raised
layer. Optional `[size]` keys:

- `fit_bbox = [x0, y0, x1, y1]`: the SVG region the dimensions refer to, when the
  drawing includes more than the device (an antenna drawn out to the side, for example).
- `appendage`: when the drawing is taller than the published height, the extra is
  built thin. `"top"` (default) or `"bottom"` say where it is, `"outside"` makes
  everything outside `fit_bbox` thin, and `"none"` turns this off.
- `body_height_mm`: the full-depth height, when the published height includes an antenna.
- `appendage_depth_mm`: thickness of those thin parts.
- `board_mm`: for a bare board, the PCB thickness. The outline is built this
  thin, and `depth_mm` stays the overall height of the stack.
- `edge_radius_mm`, `front_edge_radius_mm`: round the case's back and front
  edges. Keep the front small when the drawing has a bezel at the edge.
- `body_color`: the case color, when the drawing's main color is a panel or
  label rather than the case.

Other optional entries, with coordinates in SVG units:

- `[[block]]`: a component that stands above a board: a `bbox` and a height
  `h` in mm. The face details inside the bbox sit on its top. See `specs/rak4631.toml`.
  `base_mm` raises it on standoffs, `hollow_under = true` leaves no board under
  it (for a board that overhangs), `back = true` puts it under the board, and
  `side_color` colors its sides.
- `[[antenna]]`: a round antenna from `start` (its base) to `end` (its tip),
  at any angle. The radius is measured from the drawing, or set with `radius_mm`
  for an antenna drawn end-on, and `min_radius_mm` bridges small gaps in the
  drawing. Each color band becomes its own part. Unless `dome = false`, the tip
  ends in an even dome as wide as the shaft just below it. Don't add a wider
  cap at the tip; end the whip (or a `[[lathe]]`) with `dome = true` instead.
- `[[thin]]`: a region (`bbox` or `polygon`) built at its own `depth_mm`
  instead of full depth, for lanyards, clips, side buttons, stands and flat
  antennas. `edge_radius_mm` rounds its edges.

`[materials]` entries take `color`, `roughness`, `metallic` and `opacity`.

When the flasher's illustration isn't a front view (a perspective drawing, or
several views in one), draw the front ourselves from the device's measurements
and point the spec at it with a top-level `drawing = "drawings/<name>.svg"`.
build.sh then uses that file instead of downloading the flasher's. Draw it in
mm so it can be checked against the measurements.

`[[solid]]` places a block by measurement instead of by the drawing, for ports,
buttons and screws on the sides, top and back, and for stands:

```toml
[[solid]]
name = "USBC"
material = "port"
center_mm = [0, -0.1, 1.25]  # x from the center line, y up from the bottom, z out of the front (0 = middle of the body)
size_mm = [8.9, 0.4, 3.2]
radius_mm = 1.6              # rounds the corners of its two largest sides
rotate_deg = [0, 0, 0]       # about x, y, then z, around its own center
source = "Seeed STEP, measured"
```

For a round part such as an SMA connector or a hinge, set `shape = "cylinder"`
and `axis` (`"x"`, `"y"` or `"z"`): `size_mm` is then its length along the axis
and its diameter across. `sides = 6` makes a hex nut.

For a hand-tuned model, set `auto = false` and describe the parts with
`[[part]]` rules (match an SVG class and place it as body or a raised layer),
`[[lathe]]` (round parts such as antennas) and `[[box]]` (simple blocks such as
buttons). Coordinates are SVG units. See `specs/rak_wismesh_pocket.toml`.

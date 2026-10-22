# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "usd-core",
#   "trimesh",
#   "shapely",
#   "svgelements",
#   "numpy",
#   "scipy",
#   "mapbox-earcut",
#   "manifold3d",
# ]
# ///
# Copyright(c) Garth Vander Houwen 10/14/26.
"""Turn a front-view device SVG from the flasher into a real-size 3D USDZ.

    uv run svg2usdz.py <spec.toml> <device.svg> <out.usdz> [--source-url URL]

The spec gives the device's real width/height/depth in mm and, optionally,
how individual SVG classes should be built. With no part rules, the drawn
outline is extruded to full depth and every visible color region sits on the
front face as a thin raised layer, so any flasher SVG gives a usable model.

Part rules (in document order, first match wins) can make a class the body,
put it at a given height on the face, or skip it; lathes turn round parts such
as antennas; boxes add simple rounded blocks such as buttons. All coordinates
in rules are SVG user units, so they can be read straight off the file.
"""
import argparse
import colorsys
import io
import math
import re
import os
import sys
import tempfile
import tomllib

import numpy as np
import shapely
import trimesh
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils
from scipy.spatial import Delaunay
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from svgelements import SVG, Circle, Ellipse, Line, Path, Shape, SimpleLine

COPYRIGHT = (
    "Copyright © 2026 Meshtastic LLC. All Rights Reserved. "
    "This 3D model is not covered by the GNU GPLv3. It depicts a device sold by its "
    "manufacturer; the product, and that manufacturer's logos, marks, and trade dress, "
    "remain theirs, and this notice grants no right to either."
)
GENERATOR = "Meshtastic-Apple scripts/device-models/svg2usdz.py"

AUTO_LAYER_MM = 0.3      # relief of color regions on the face in auto mode
SAMPLE_MM = 0.5          # target spacing of points along curves
SIMPLIFY_MM = 0.05       # outline simplification tolerance


# --- SVG reading --------------------------------------------------------------

class Element:
    """One SVG shape: its class, paint and outline polygon (in SVG units)."""

    def __init__(self, index, el):
        self.index = index
        self.el = el
        self.cls = el.values.get("class", "") or ""
        self.fill = None if el.fill is None or el.fill.value is None else el.fill
        opacity = float(el.values.get("opacity", 1) or 1)
        fill_opacity = float(el.values.get("fill-opacity", 1) or 1)
        self.opacity = opacity * fill_opacity * (self.fill.opacity if self.fill else 1)
        self.is_circle = isinstance(el, (Circle, Ellipse))
        bb = el.bbox()
        self.bbox = bb  # (x0, y0, x1, y1) or None
        self.poly = None

    @property
    def fill_hex(self):
        return self.fill.hex[:7].lower() if self.fill else None

    @property
    def solid(self):
        return self.fill is not None and self.opacity >= 0.99

    def width(self):
        return 0 if self.bbox is None else self.bbox[2] - self.bbox[0]

    def height(self):
        return 0 if self.bbox is None else self.bbox[3] - self.bbox[1]


def read_svg(path):
    # Drop the viewBox so svgelements keeps the file's raw coordinates; its
    # viewBox shift composes wrongly with per-element rotate() transforms.
    with open(path, encoding="utf-8") as f:
        raw = re.sub(r'\sviewBox="[^"]*"', "", f.read(), count=1)
    svg = SVG.parse(io.StringIO(raw), reify=True)
    out = []
    for el in svg.elements():
        if not isinstance(el, Shape) or isinstance(el, (Line, SimpleLine)):
            continue
        e = Element(len(out), el)
        if e.bbox is None or e.width() <= 0 or e.height() <= 0:
            continue
        out.append(e)
    return out


def ring_points(sub, step):
    """Points along one subpath: corners for lines, spaced samples for curves."""
    pts = []
    for seg in sub:
        name = type(seg).__name__
        if name == "Move":
            pts.append((seg.end.x, seg.end.y))
        elif name in ("Line", "Close"):
            if seg.end is not None:
                pts.append((seg.end.x, seg.end.y))
        else:
            n = max(3, int(math.ceil(seg.length(error=1e-3) / step)))
            for t in np.linspace(0, 1, n + 1)[1:]:
                p = seg.point(t)
                pts.append((p.x, p.y))
    return pts


def element_polygon(e, step, simplify):
    """Even-odd fill polygon of an element in SVG units."""
    rings = []
    # abs() bakes the shape's own and inherited transforms into its points.
    for sub in abs(Path(e.el)).as_subpaths():
        pts = ring_points(Path(sub), step)
        if len(pts) < 3:
            continue
        p = Polygon(pts).buffer(0)
        if p.area > 0:
            rings.append(p)
    if not rings:
        return None
    poly = rings[0]
    for r in rings[1:]:
        poly = poly.symmetric_difference(r)
    poly = poly.simplify(simplify, preserve_topology=True).buffer(0)
    return None if poly.is_empty else poly


# --- spec matching ------------------------------------------------------------

def as_list(v):
    if v is None:
        return None
    return v if isinstance(v, list) else [v]


def rule_matches(rule, e, scale):
    classes = as_list(rule.get("class"))
    if classes is not None and not set(e.cls.split()) & set(classes):
        return False
    fills = as_list(rule.get("fill"))
    if fills is not None and e.fill_hex not in [f.lower() for f in fills]:
        return False
    if rule.get("shape") == "circle" and not e.is_circle:
        return False
    w_mm, h_mm = e.width() * scale, e.height() * scale
    if "min_width_mm" in rule and w_mm < rule["min_width_mm"]:
        return False
    if "max_width_mm" in rule and w_mm > rule["max_width_mm"]:
        return False
    area = w_mm * h_mm
    if "min_bbox_area_mm2" in rule and area < rule["min_bbox_area_mm2"]:
        return False
    if "max_bbox_area_mm2" in rule and area > rule["max_bbox_area_mm2"]:
        return False
    return True


# --- geometry -----------------------------------------------------------------

def polygons(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return list(geom.geoms)
    return [g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon)]


def extrude(geom, z0, h):
    meshes = []
    for p in polygons(geom):
        if p.area < 1e-4:
            continue
        m = trimesh.creation.extrude_polygon(orient(p), h)
        m.apply_translation([0, 0, z0])
        meshes.append(m)
    return meshes


def solid_mesh(sd, depth):
    """A block placed in mm: x from the device's center line, y up from its
    bottom, z out of the front with 0 the middle of the body (the front face is
    at depth/2, the back at -depth/2). It is size_mm across, rotated by
    rotate_deg about x, y then z around its own center. radius_mm rounds the
    corners of its two largest sides, so a flat port or button reads as one.
    shape = "cylinder" makes it round instead, along axis ("x", "y" or "z"),
    with sides faces around (6 for a hex nut)."""
    w, h, d = (float(v) for v in sd["size_mm"])
    dims = [w, h, d]
    if sd.get("shape") == "cylinder":
        axis = "xyz".index(sd.get("axis", "z"))
        m = trimesh.creation.cylinder(radius=0.5, height=1, sections=int(sd.get("sides", 32)))
        # Built along z; turn it onto its axis, then size it, so size_mm is x, y, z.
        if axis == 0:
            m.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [0, 1, 0]))
        elif axis == 1:
            m.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
        m.apply_scale(dims)
        return place_solid(m, sd)
    thin = int(np.argmin(dims))
    a, b = [dims[i] for i in range(3) if i != thin]
    r = min(float(sd.get("radius_mm", 0)), a / 2, b / 2)
    if r > 0:
        # Grow a core by r: a point for a disc, a line for a stadium, else a
        # smaller rectangle.
        ca, cb = a / 2 - r, b / 2 - r
        if ca < 1e-6 and cb < 1e-6:
            core = Point(0, 0)
        elif ca < 1e-6 or cb < 1e-6:
            core = LineString([(-max(ca, 0), -max(cb, 0)), (max(ca, 0), max(cb, 0))])
        else:
            core = box(-ca, -cb, ca, cb)
        g = core.buffer(r, quad_segs=8)
    else:
        g = box(-a / 2, -b / 2, a / 2, b / 2)
    m = extrude(g, -dims[thin] / 2, dims[thin])[0]
    # The rounded face was built in x/y with its thickness along z; turn it so
    # the thickness lies along the smallest dimension.
    if thin == 0:
        m.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [0, 1, 0]))
        m.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [1, 0, 0]))
    elif thin == 1:
        m.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [1, 0, 0]))
    return place_solid(m, sd)


def place_solid(m, sd):
    """Turns a solid by its rotate_deg and moves it to its center_mm."""
    rx, ry, rz = (math.radians(float(v)) for v in sd.get("rotate_deg", [0, 0, 0]))
    for angle, axis in ((rx, [1, 0, 0]), (ry, [0, 1, 0]), (rz, [0, 0, 1])):
        if angle:
            m.apply_transform(trimesh.transformations.rotation_matrix(angle, axis))
    m.apply_translation([float(v) for v in sd["center_mm"]])
    return m


def even_ring(ring, n):
    """n points evenly spaced along a closed ring, counter-clockwise."""
    line = LineString(ring.coords)
    pts = np.array([line.interpolate(d).coords[0] for d in np.linspace(0, line.length, n, endpoint=False)])
    if Polygon(pts).exterior.is_ccw is False:
        pts = pts[::-1]
    return pts


def rounded_extrude(geom, z0, h, r, rf=None, segs=6):
    """Extrude with the back edge rounded to radius r and the front edge to rf
    (mm). Falls back to a plain extrusion where insetting would change a
    shape's topology."""
    rf = r if rf is None else rf
    r, rf = max(min(r, h / 2 - 0.01), 0), max(min(rf, h / 2 - 0.01), 0)
    if r <= 0.05 and rf <= 0.05:
        return extrude(geom, z0, h)
    angles = np.linspace(0, math.pi / 2, segs + 1)
    levels = [(r - r * math.sin(a), z0 + r - r * math.cos(a)) for a in angles] if r > 0.05 else [(0, z0)]
    levels += [(rf - rf * math.cos(a), z0 + h - rf + rf * math.sin(a)) for a in angles] if rf > 0.05 else [(0, z0 + h)]
    meshes = []
    for p in polygons(geom):
        if p.area < 1e-4:
            continue
        p = Polygon(p.exterior)
        insets = [p.buffer(-d, quad_segs=8) if d > 1e-6 else p for d, _ in levels]
        if any(not isinstance(q, Polygon) or q.is_empty for q in insets):
            meshes += extrude(p, z0, h)
            continue
        n = int(min(max(p.exterior.length / 0.5, 48), 800))
        rings = [even_ring(q.exterior, n) for q in insets]
        for i in range(1, len(rings)):
            # Start each ring at the point closest to the previous ring's start.
            k = int(np.argmin(np.linalg.norm(rings[i] - rings[i - 1][0], axis=1)))
            rings[i] = np.roll(rings[i], -k, axis=0)
        verts = np.vstack([np.column_stack([rg, np.full(n, z)]) for rg, (_, z) in zip(rings, levels)])
        faces = []
        for i in range(len(rings) - 1):
            a, b = i * n, (i + 1) * n
            for j in range(n):
                j2 = (j + 1) % n
                faces += [[a + j, a + j2, b + j2], [a + j, b + j2, b + j]]
        side = trimesh.Trimesh(verts, np.array(faces), process=False)
        back = trimesh.creation.extrude_polygon(orient(insets[0]), 1e-4)
        back.apply_translation([0, 0, z0])
        front = trimesh.creation.extrude_polygon(orient(insets[-1]), 1e-4)
        front.apply_translation([0, 0, z0 + h - 1e-4])
        meshes += [side, back, front]
    return meshes


def fine_mesh(p, step):
    """Triangles filling polygon p with points about step apart, facing +z."""
    edge = np.vstack([np.asarray(shapely.segmentize(r, step).coords)[:-1] for r in [p.exterior, *p.interiors]])
    x0, y0, x1, y1 = p.bounds
    gx, gy = np.meshgrid(np.arange(x0, x1, step), np.arange(y0, y1, step))
    grid = np.column_stack([gx.ravel(), gy.ravel()])
    grid = grid[shapely.contains_xy(p, grid[:, 0], grid[:, 1])]
    grid = grid[shapely.distance(shapely.points(grid), p.boundary) > step / 2]
    pts = np.vstack([edge, grid])
    tri = Delaunay(pts).simplices
    c = pts[tri].mean(axis=1)
    tri = tri[shapely.contains_xy(p, c[:, 0], c[:, 1])]
    ab, ac = pts[tri[:, 1]] - pts[tri[:, 0]], pts[tri[:, 2]] - pts[tri[:, 0]]
    cw = ab[:, 0] * ac[:, 1] - ab[:, 1] * ac[:, 0] < 0
    tri[cw] = tri[cw][:, ::-1]
    return pts, tri


def puff_height(d, radius, dome):
    """Half-thickness at distance d in from the edge: a round edge of the given
    radius, so a part narrower than it comes out round, then a gentle dome."""
    t = np.clip(d / radius, 0, 1)
    return radius * np.sqrt(t * (2 - t)) + dome * np.sqrt(np.maximum(d - radius, 0))


def puffed(geom, zc, radius, dome):
    """A region inflated like a cushion, front and back, around the plane zc."""
    step = radius / 6  # Fine enough for the round edge, no finer.
    meshes = []
    for p in polygons(geom):
        if p.area < 1e-2:
            continue
        pts, tri = fine_mesh(p, step)
        h = puff_height(shapely.distance(shapely.points(pts), p.boundary), radius, dome)
        verts = np.vstack([np.column_stack([pts, zc + h]), np.column_stack([pts, zc - h])])
        meshes.append(trimesh.Trimesh(verts, np.vstack([tri, tri[:, ::-1] + len(pts)]), process=False))
    return meshes


def draped(geom, holder, zc, radius, dome, step=0.1, lift=0.1):
    """Face detail laid just over the front of the puffed region holder."""
    meshes = []
    for p in polygons(geom):
        if p.area < 1e-3:
            continue
        pts, tri = fine_mesh(p, step)
        h = puff_height(shapely.distance(shapely.points(pts), holder.boundary), radius, dome)
        meshes.append(trimesh.Trimesh(np.column_stack([pts, zc + h + lift]), tri, process=False))
    return meshes


def lathe_mesh(profile, sections=64):
    m = trimesh.creation.revolve(np.array(profile), sections=sections)
    # revolve uses Z as the axis; turn it so the axis is Y
    m.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
    return m


# --- materials ----------------------------------------------------------------

def hex_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def linear_rgb(h):
    """A hex color as the linear values USD and glTF expect for a material's
    base color. Written as-is, sRGB values show up much lighter: a near-black
    #232527 comes out mid-gray."""
    def channel(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(channel(c) for c in hex_rgb(h))


def auto_material(hexcolor):
    """Plastic by default; gold and pale yellow fills read as metal."""
    r, g, b = hex_rgb(hexcolor)
    hue, light, sat = colorsys.rgb_to_hls(r, g, b)
    metal = 0.08 <= hue <= 0.17 and sat > 0.35 and light > 0.4
    return {"color": hexcolor, "roughness": 0.3 if metal else 0.55, "metallic": 1.0 if metal else 0.0}


def prim_name(s):
    s = re.sub(r"[^A-Za-z0-9_]", "_", s)
    return s if re.match(r"[A-Za-z_]", s) else "_" + s


# --- build --------------------------------------------------------------------

def build(spec, svg_path):
    size = spec["size"]
    edge_r = float(size.get("edge_radius_mm", 0))
    edge_rf = float(size.get("front_edge_radius_mm", edge_r))
    # A bare board is built at PCB thickness; depth_mm is then the overall
    # height of the stack and only components ([[block]]) stand taller.
    depth = float(size.get("board_mm", size["depth_mm"]))
    rules = spec.get("part", [])
    auto = spec.get("auto", True)

    elements = read_svg(svg_path)
    if not elements:
        sys.exit(f"{svg_path}: no shapes found")

    # Outlines are sampled at a spacing based on a first guess of the scale.
    solid = [e for e in elements if e.solid]
    guess = float(size["width_mm"]) / (max(e.bbox[2] for e in solid) - min(e.bbox[0] for e in solid))
    for e in elements:
        e.poly = element_polygon(e, SAMPLE_MM / guess, SIMPLIFY_MM / guess)
    elements = [e for e in elements if e.poly is not None]

    # Drop stray marks that sit apart from the device (tiny islands).
    islands = polygons(unary_union([e.poly for e in elements if e.solid]))
    largest = max(p.area for p in islands)
    keep = unary_union([Polygon(p.exterior) for p in islands if p.area >= 0.01 * largest])
    stray = [e for e in elements if not e.poly.intersects(keep)]
    elements = [e for e in elements if e.poly.intersects(keep)]

    # Region the real dimensions refer to.
    fit = size.get("fit", "drawn")
    if fit == "drawn":
        fit_els = [e for e in elements if e.solid]
    elif fit.startswith("class:"):
        fit_els = [e for e in elements if fit[6:] in e.cls.split()]
    else:
        sys.exit(f"unknown fit '{fit}'")
    if "fit_bbox" in size:
        fx0, fy0, fx1, fy1 = size["fit_bbox"]
    else:
        fx0 = min(e.bbox[0] for e in fit_els)
        fy0 = min(e.bbox[1] for e in fit_els)
        fx1 = max(e.bbox[2] for e in fit_els)
        fy1 = max(e.bbox[3] for e in fit_els)
    fit_w, fit_h = fx1 - fx0, fy1 - fy0
    sx = float(size["width_mm"]) / fit_w
    sy = float(size["height_mm"]) / fit_h
    scale = sx if size.get("scale_by", "width") == "width" else sy
    mismatch = abs(sx - sy) / max(sx, sy)
    warnings = [f"dropped {len(stray)} stray shapes"] if stray else []
    if mismatch > 0.05:
        warnings.append(
            f"drawing aspect differs from real size by {mismatch:.0%} "
            f"(width gives {fit_w * sx:.1f}x{fit_h * sx:.1f} mm, spec {size['width_mm']}x{size['height_mm']})"
        )
    cx, base_y = (fx0 + fx1) / 2, fy1

    def to_mm(x, y):
        return (x - cx) * scale, (base_y - y) * scale

    def svg_to_mm_poly(p):
        def tx(coords):
            return [to_mm(x, y) for x, y in coords]
        return Polygon(tx(p.exterior.coords), [tx(i.coords) for i in p.interiors]).buffer(0)

    def mm_geom(geom):
        return unary_union([svg_to_mm_poly(p) for p in polygons(geom)])

    # When the drawing is taller than the published height, the published
    # figure leaves out an antenna or similar. Only the published height gets
    # full depth; the rest is built thin.
    band = None
    top_y = min(e.bbox[1] for e in elements if e.solid)
    drawn_h = (base_y - top_y) * scale
    body_h = float(size.get("body_height_mm", size["height_mm"]))
    appendage = size.get("appendage", "top")
    app_depth = float(size.get("appendage_depth_mm", min(depth * 0.35, 8.0)))
    if appendage == "outside":
        # Everything outside the fit box (cables, flat antennas) is thin.
        band = box(-fit_w * scale / 2, 0, fit_w * scale / 2, fit_h * scale)
    elif appendage != "none" and drawn_h > body_h * 1.05:
        if appendage == "top":
            band = box(-1e5, -1e5, 1e5, body_h)
        elif appendage == "bottom":
            band = box(-1e5, drawn_h - body_h, 1e5, 1e5)
        else:
            sys.exit(f"unknown appendage '{appendage}'")

    materials = {k: dict(v) for k, v in spec.get("materials", {}).items()}

    def material_for(name_or_auto, e=None):
        if name_or_auto in (None, "auto"):
            if e is None or e.fill_hex is None:
                return "default"
            key = "c_" + e.fill_hex.lstrip("#")
            materials.setdefault(key, auto_material(e.fill_hex))
            return key
        if name_or_auto not in materials:
            sys.exit(f"material '{name_or_auto}' is not defined in [materials]")
        return name_or_auto

    parts = {}  # name -> (meshes, material, smooth)

    def add(name, meshes, mat, smooth=False):
        if meshes:
            parts.setdefault(prim_name(name), ([], mat, smooth))[0].extend(meshes)

    front = depth / 2
    matched, leftover = {}, []
    for e in elements:
        rule = next((r for r in rules if rule_matches(r, e, scale)), None)
        if rule is None:
            leftover.append(e)
        else:
            matched.setdefault(id(rule), (rule, []))[1].append(e)

    has_body = False
    for rule, els in matched.values():
        role = rule.get("role", "layer")
        if role == "skip":
            continue
        name = rule.get("name", rule.get("class", "Part"))
        name = name if isinstance(name, str) else "_".join(name)
        mat = material_for(rule.get("material"), els[0])
        for e in els:
            g = mm_geom(e.poly)
            if rule.get("fill_holes"):
                g = unary_union([Polygon(p.exterior) for p in polygons(g)])
            if role == "body":
                has_body = True
                t = depth * float(rule.get("thickness", 1.0))
                add(name, extrude(g, -t / 2, t), mat)
            else:
                add(name, extrude(g, front + float(rule.get("z", 0)), float(rule.get("h", AUTO_LAYER_MM))), mat)

    def build_antenna(an, solid, visible):
        """Revolve an antenna around the line from its base to its tip, with
        the radius measured from the drawing's width across that line. Each
        run of one color becomes its own part. Returns the area it replaces."""
        (sx, sy), (ex, ey) = an["start"], an["end"]
        length = math.hypot(ex - sx, ey - sy)
        ux, uy = (ex - sx) / length, (ey - sy) / length
        nx, ny = -uy, ux
        shapes = unary_union([e.poly for e in solid + [e for e in stray if e.solid]])
        reach = float(an.get("max_width", length))
        n = int(an.get("samples", 80))
        samples = []
        for i in range(n + 1):
            t = min(max(i / n, 0.002), 0.998) * length
            px, py = sx + ux * t, sy + uy * t
            cut = LineString([(px - nx * reach, py - ny * reach), (px + nx * reach, py + ny * reach)])
            hit = cut.intersection(shapes)
            segs = [g for g in getattr(hit, "geoms", [hit]) if isinstance(g, LineString) and not g.is_empty]
            pt = Point(px, py)
            seg = min(segs, key=lambda g: g.distance(pt)) if segs else None
            half = seg.length / 2 if seg is not None and seg.distance(pt) < 1e-6 + reach * 0.02 else 0
            owner = next((e for e, v in reversed(visible) if v.buffer(0.5).contains(pt)), None)
            samples.append((t, half, owner))
        # Smooth the radius a little so sampling noise doesn't show as ridges.
        halves = [h for _, h, _ in samples]
        smooth = [sorted(halves[max(0, i - 1):i + 2])[len(halves[max(0, i - 1):i + 2]) // 2] for i in range(len(halves))]
        k = float(an.get("radius_scale", 1.0))
        floor = float(an.get("min_radius_mm", 0.3))
        prof = [(t * scale, max(h * scale * k, floor), o) for (t, _, o), h in zip(samples, smooth)]
        if "radius_mm" in an:
            # Fixed radius, for antennas the drawing shows end-on or too small.
            r0 = float(an["radius_mm"])
            r1 = float(an.get("tip_radius_mm", r0))
            prof = [(t, r0 + (r1 - r0) * t / prof[-1][0], o) for t, _, o in prof]

        # The tip ends in an even hemisphere as wide as the shaft just below it. The drawn tip
        # narrows, flares or carries highlight marks, which revolved into a bulb or a point. The
        # last stretch is held at that radius so the shaft runs straight into the dome, with no
        # step where a sample was a little thinner or wider.
        tip_r = None
        if an.get("dome", True):
            t_end = prof[-1][0]
            near = [r for t, r, _ in prof if 0.8 * t_end <= t <= 0.95 * t_end]
            tip_r = float(np.median(near)) if near else prof[-1][1]
            prof = [(t, tip_r if t >= 0.8 * t_end else r, o) for t, r, o in prof]
        runs = []
        for t, r, o in prof:
            key = o.fill_hex if o is not None else None
            if runs and runs[-1][0] == key:
                runs[-1][1].append((t, r))
            else:
                if runs:
                    runs[-1][1].append((t, r))  # share the boundary so runs meet
                runs.append((key, [(t, r)], o))
        dx, dy = ux * scale, -uy * scale
        d = np.array([dx, dy, 0.0]) / math.hypot(dx, dy)
        rot = trimesh.geometry.align_vectors([0, 0, 1], d)
        bx0, by0 = to_mm(sx, sy)
        zc = float(an.get("z_mm", 0))
        for idx, (key, pts, owner) in enumerate(runs):
            if len(pts) < 2:
                continue
            if idx == len(runs) - 1 and tip_r is not None:
                r_end = tip_r
                t_end = pts[-1][0]
                pts = [(t, r) for t, r in pts if t <= t_end - r_end] or pts[:1]
                pts += [(t_end - r_end + r_end * math.sin(a), r_end * math.cos(a)) for a in np.linspace(0, math.pi / 2, 10)]
            line = [(0.0, pts[0][0])] + [(r, t) for t, r in pts] + [(0.0, pts[-1][0])]
            m = trimesh.creation.revolve(np.array(line), sections=int(an.get("sections", 40)))
            m.apply_transform(rot)
            m.apply_translation([bx0, by0, zc])
            mat = material_for(an["material"]) if an.get("material") else material_for("auto", owner)
            add(f'{an.get("name", "Antenna")}_{idx}', [m], mat, smooth=True)
        widest = max(max(h for _, h, _ in samples), max(r for _, r, _ in prof) / scale) * 1.15 + 1
        corridor = LineString([(sx, sy), (ex + ux * widest, ey + uy * widest)]).buffer(widest, cap_style=2)
        return mm_geom(corridor)

    def build_tube(tb):
        """A round rod swept along points in SVG units, for a bent wire the
        drawing shows as a line. Returns the area of the drawing it replaces."""
        pts = [to_mm(x, y) for x, y in tb["points"]]
        r = float(tb["radius_mm"])
        zc = float(tb.get("z_mm", 0))
        # Open-ended sides: a capped cylinder's rim normals average with the
        # cap and shade as a dark ring at every joint.
        n = 24
        ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
        meshes = []
        for (ax, ay), (bx_, by) in zip(pts, pts[1:]):
            a, b = np.array([ax, ay, zc]), np.array([bx_, by, zc])
            d = (b - a) / np.linalg.norm(b - a)
            u = np.cross(d, [0, 0, 1])
            ring = r * (np.outer(np.cos(ang), u) + np.outer(np.sin(ang), [0, 0, 1]))
            faces = [f for j in range(n) for f in ([j, n + (j + 1) % n, (j + 1) % n], [j, n + j, n + (j + 1) % n])]
            meshes.append(trimesh.Trimesh(np.vstack([a + ring, b + ring]), faces, process=False))
        # A ball at every point rounds the joints and both ends.
        for x, y in pts:
            ball = trimesh.creation.uv_sphere(radius=r, count=[12, 24])
            ball.apply_translation([x, y, zc])
            meshes.append(ball)
        if tb.get("material"):
            mat = material_for(tb["material"])
        else:
            mat = "c_" + tb["color"].lstrip("#").lower()
            materials.setdefault(mat, auto_material(tb["color"]))
        add(tb.get("name", "Tube"), meshes, mat, smooth=True)
        half = float(tb.get("cut_width", 2 * r / scale)) / 2
        return mm_geom(LineString(tb["points"]).buffer(half, cap_style=2))

    def build_ball(bl):
        """A sphere at a point in SVG units, for a knob the drawing shows flat.
        Replaces the drawing inside cut_bbox, or inside its own outline."""
        x, y = to_mm(*bl["center"])
        ball = trimesh.creation.uv_sphere(radius=float(bl["radius_mm"]), count=[24, 48])
        ball.apply_translation([x, y, float(bl.get("z_mm", 0))])
        mat = "c_" + bl["color"].lstrip("#").lower()
        materials.setdefault(mat, auto_material(bl["color"]))
        add(bl.get("name", "Ball"), [ball], mat, smooth=True)
        if "cut_bbox" in bl:
            return svg_to_mm_poly(box(*bl["cut_bbox"]))
        return Point(x, y).buffer(float(bl["radius_mm"]))

    if auto:
        solid = [e for e in leftover if e.solid]
        # What each shape still shows once later shapes are painted over it.
        visible, above = [], None
        for e in reversed(solid):
            v = e.poly if above is None else e.poly.difference(above)
            above = e.poly if above is None else unary_union([above, e.poly])
            if not v.is_empty and v.area > 0:
                visible.append((e, v))
        visible.reverse()
        by_color = {}
        for e, v in visible:
            by_color.setdefault(e.fill_hex, []).append((e, v))
        if by_color:
            dominant = max(by_color, key=lambda c: sum(v.area for _, v in by_color[c]))

            def minus(g, other):
                return g if other is None else g.difference(other)

            # Round antennas replace their part of the drawing.
            cuts = [build_antenna(an, solid, visible) for an in spec.get("antenna", [])]
            cuts += [build_tube(tb) for tb in spec.get("tube", [])]
            cuts += [build_ball(bl) for bl in spec.get("ball", [])]
            cut_all = unary_union(cuts) if cuts else None
            # Regions built thinner than the body (lanyards, clips, side buttons).
            thins = []
            for th in spec.get("thin", []):
                region = Polygon(th["polygon"]) if "polygon" in th else box(*th["bbox"])
                tmat = None
                if th.get("color"):
                    # A region whose own color differs from the body, such as a glove.
                    tmat = "c_" + th["color"].lstrip("#").lower()
                    materials.setdefault(tmat, auto_material(th["color"]))
                thins.append((svg_to_mm_poly(region), float(th.get("z_mm", 0)), float(th.get("depth_mm", 0)),
                              float(th.get("edge_radius_mm", 0)), tmat, th))
            thin_all = unary_union([t[0] for t in thins]) if thins else None

            def block_geom(bk):
                x0, y0, x1, y1 = bk["bbox"]
                (ax, ay), (bx_, by) = to_mm(x0, y0), to_mm(x1, y1)
                g = box(min(ax, bx_), min(ay, by), max(ax, bx_), max(ay, by))
                r = float(bk.get("radius_mm", 0))
                return g.buffer(-r).buffer(r, quad_segs=8) if r > 0 else g

            # Boards that overhang on standoffs leave open space underneath.
            hollow = [block_geom(bk) for bk in spec.get("block", []) if bk.get("hollow_under")]
            hollow_all = unary_union(hollow) if hollow else None

            if not has_body:
                outline = unary_union([e.poly for e in solid])
                outline = minus(mm_geom(unary_union([Polygon(p.exterior) for p in polygons(outline)])), cut_all)
                if size.get("body_color"):
                    # The case color when the drawing's main color is a panel or label.
                    mat = "body"
                    materials.setdefault("body", auto_material(size["body_color"]))
                else:
                    mat = material_for("auto", by_color[dominant][0][0])
                body = minus(minus(outline, thin_all), hollow_all)
                if band is None:
                    add("Body", rounded_extrude(body, -front, depth, edge_r, edge_rf), mat)
                else:
                    add("Body", rounded_extrude(body.intersection(band), -front, depth, edge_r, edge_rf), mat)
                    add("Appendage", extrude(body.difference(band), -app_depth / 2, app_depth), mat)
                for g, zc, t, r, tmat, th in thins:
                    if "puff_mm" in th:
                        meshes = puffed(outline.intersection(g), zc, float(th["puff_mm"]), float(th.get("dome", 0)))
                        add(f"Puff_{tmat}" if tmat else "Puff", meshes, tmat or mat, smooth=True)
                        continue
                    add(f"Thin_{tmat}" if tmat else "Thin", rounded_extrude(outline.intersection(g), zc - t / 2, t, r), tmat or mat)
            # Components that stand above the face: a block of the given
            # height whose face details sit on its top.
            blocks = []
            for bk in spec.get("block", []):
                g = block_geom(bk)
                if not has_body:
                    g = g.intersection(outline)
                svg_region = box(*bk["bbox"])
                if bk.get("material"):
                    bmat = material_for(bk["material"])
                elif bk.get("side_color"):
                    bmat = "c_" + bk["side_color"].lstrip("#").lower()
                    materials.setdefault(bmat, auto_material(bk["side_color"]))
                else:
                    inside = [(e, v.intersection(svg_region).area) for e, v in visible]
                    e_top = max(inside, key=lambda t: t[1])[0]
                    bmat = material_for("auto", e_top)
                h = float(bk["h"])
                if bk.get("back"):
                    # Components under the board (a socket, a battery) stand off the back.
                    add(bk.get("name", "Block"), extrude(g, -front - h, h), bmat)
                    continue
                base = float(bk.get("base_mm", 0))
                blocks.append((g, h))
                add(bk.get("name", "Block"), extrude(g, front + base, h - base), bmat)
            all_blocks = unary_union([g for g, _ in blocks]) if blocks else None

            flat_front = outline.buffer(-edge_rf * 0.9) if edge_rf > 0 and not has_body else None

            def place(name, g, z, mat):
                if flat_front is not None and z == front:
                    g = g.intersection(flat_front)
                if all_blocks is None:
                    add(name, extrude(g, z, AUTO_LAYER_MM), mat)
                    return
                add(name, extrude(g.difference(all_blocks), z, AUTO_LAYER_MM), mat)
                for bg, h in blocks:
                    add(name, extrude(g.intersection(bg), z + h, AUTO_LAYER_MM), mat)

            for color, items in by_color.items():
                g = minus(mm_geom(unary_union([v for _, v in items])), cut_all)
                if not has_body:
                    for tg, zc, t, tr, _, th in thins if color != dominant else []:
                        if "puff_mm" in th:
                            if color == th.get("color", "").lower():
                                continue  # The region is already this color.
                            holder = outline.intersection(tg)
                            # bare_edge_mm leaves the drawn outline off, so the region shows its own color there.
                            detail = g.intersection(holder.buffer(-float(th.get("bare_edge_mm", 0))))
                            # Its own part: smoothing is set per part, and flat faces need sharp edges.
                            add("PuffFace_" + color.lstrip("#"), draped(detail, holder, zc,
                                                                  float(th["puff_mm"]), float(th.get("dome", 0))),
                                material_for("auto", items[0][0]), smooth=True)
                            continue
                        tface = tg.buffer(-tr * 0.9) if tr > 0 else tg
                        add("Face_" + color.lstrip("#"), extrude(g.intersection(tface), zc + t / 2, AUTO_LAYER_MM),
                            material_for("auto", items[0][0]))
                    g = minus(g, thin_all)
                if color == dominant and not has_body and not size.get("body_color"):
                    # The body shows this color; only block tops need it.
                    g = g.intersection(all_blocks) if all_blocks is not None else None
                    if g is None or g.is_empty:
                        continue
                mat = material_for("auto", items[0][0])
                name = "Face_" + color.lstrip("#")
                if band is None or has_body:
                    place(name, g, front, mat)
                else:
                    place(name, g.intersection(band), front, mat)
                    add(name, extrude(g.difference(band), app_depth / 2, AUTO_LAYER_MM), mat)

    for lt in spec.get("lathe", []):
        yb = (base_y - lt["y_bottom"]) * scale
        yt = (base_y - lt["y_top"]) * scale
        r = lt["radius"] * scale
        prof = [(0, yb), (r, yb)]
        if lt.get("dome"):
            cyd = yt - r
            prof.append((r, cyd))
            prof += [(r * math.cos(a), cyd + r * math.sin(a)) for a in np.linspace(0, math.pi / 2, 16)[1:]]
        else:
            prof += [(r, yt), (0, yt)]
        m = lathe_mesh(prof, lt.get("sections", 48))
        m.apply_translation([(lt["axis_x"] - cx) * scale, 0, float(lt.get("z", 0))])
        add(lt["name"], [m], material_for(lt["material"]), smooth=True)

    for bx in spec.get("box", []):
        x0, y0 = to_mm(bx["x"], bx["y"])
        x1, y1 = to_mm(bx["x"] + bx["width"], bx["y"] + bx["height"])
        r = bx.get("radius", 0) * scale
        g = box(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
        if r > 0:
            g = g.buffer(-r).buffer(r, quad_segs=8)
        if "thickness" in bx:
            # Centered on the body, as a fraction of depth plus h mm.
            t = depth * float(bx["thickness"]) + float(bx.get("h", 0))
            z0 = -t / 2
        else:
            t, z0 = float(bx["h"]), front + float(bx.get("z", 0))
        add(bx["name"], extrude(g, z0, t), material_for(bx["material"]))

    # Parts placed by measurement rather than read off the drawing: ports,
    # buttons and screws on any face, stands. In mm, in the model's frame.
    for sd in spec.get("solid", []):
        add(sd["name"], [solid_mesh(sd, depth)], material_for(sd["material"]))

    if not parts:
        sys.exit(f"{svg_path}: nothing was built")
    return parts, materials, warnings


def write_usdz(parts, materials, out, root_name, meta):
    with tempfile.TemporaryDirectory() as tmpdir:
        usdc = os.path.join(tmpdir, root_name + ".usdc")
        stage = Usd.Stage.CreateNew(usdc)
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1.0)
        layer = stage.GetRootLayer()
        layer.documentation = meta["copyright"]
        layer.customLayerData = meta
        root = UsdGeom.Xform.Define(stage, f"/{root_name}")
        stage.SetDefaultPrim(root.GetPrim())
        Usd.ModelAPI(root.GetPrim()).SetKind("component")
        Usd.ModelAPI(root.GetPrim()).SetAssetInfo({"name": root_name, "copyright": meta["copyright"]})

        mat_prims = {}
        for name in sorted({m for _, m, _ in parts.values()}):
            spec = materials.get(name, {"color": "#888888", "roughness": 0.5, "metallic": 0.0})
            m = UsdShade.Material.Define(stage, f"/{root_name}/Materials/{prim_name(name)}")
            s = UsdShade.Shader.Define(stage, f"/{root_name}/Materials/{prim_name(name)}/Surface")
            s.CreateIdAttr("UsdPreviewSurface")
            s.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*linear_rgb(spec["color"])))
            s.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(spec.get("roughness", 0.5)))
            s.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(float(spec.get("metallic", 0.0)))
            if "emissive" in spec:
                # A fraction of the base color, so a viewer's dim lighting can't wash it out.
                k = float(spec["emissive"])
                s.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).Set(
                    Gf.Vec3f(*(c * k for c in linear_rgb(spec["color"]))))
            if "opacity" in spec:
                s.CreateInput("opacity", Sdf.ValueTypeNames.Float).Set(float(spec["opacity"]))
            m.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(), "surface")
            mat_prims[name] = m

        mm = 0.001
        for name, (meshes, mat, smooth) in parts.items():
            mesh = trimesh.util.concatenate(meshes)
            if not smooth:
                # Split vertices only along sharp edges so extrusions keep crisp
                # corners without tripling the vertex count.
                mesh = mesh.smooth_shaded
            normals = mesh.vertex_normals
            g = UsdGeom.Mesh.Define(stage, f"/{root_name}/{name}")
            g.CreatePointsAttr((mesh.vertices * mm).astype(np.float32))
            g.CreateFaceVertexCountsAttr(np.full(len(mesh.faces), 3, dtype=np.int32))
            g.CreateFaceVertexIndicesAttr(mesh.faces.flatten().astype(np.int32))
            g.CreateNormalsAttr(np.asarray(normals, dtype=np.float32))
            g.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
            g.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
            g.CreateExtentAttr([Gf.Vec3f(*(mesh.bounds[0] * mm)), Gf.Vec3f(*(mesh.bounds[1] * mm))])
            UsdShade.MaterialBindingAPI.Apply(g.GetPrim()).Bind(mat_prims[mat])

        layer.Save()
        ok = UsdUtils.CreateNewARKitUsdzPackage(usdc, out)
    if not ok:
        sys.exit(f"failed to package {out}")
    allm = trimesh.util.concatenate([m for ms, _, _ in parts.values() for m in ms])
    return allm.extents


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("svg")
    ap.add_argument("out")
    ap.add_argument("--source-url", default="")
    a = ap.parse_args()
    if not a.out.endswith(".usdz"):
        sys.exit("output must end in .usdz")

    with open(a.spec, "rb") as f:
        spec = tomllib.load(f)
    parts, materials, warnings = build(spec, a.svg)
    size = spec["size"]
    meta = {
        # A spec's own notice, for a model that isn't of a manufacturer's device.
        "copyright": spec.get("copyright", COPYRIGHT),
        "generator": GENERATOR,
        "sourceImage": a.source_url,
        "dimensionsSource": size.get("source", ""),
        "dimensionsCover": size.get("covers", ""),
        "realSizeMM": Gf.Vec3f(float(size["width_mm"]), float(size["height_mm"]), float(size["depth_mm"])),
    }
    root_name = prim_name(spec.get("name") or re.sub(r"[^A-Za-z0-9]+", "_", a.out.rsplit("/", 1)[-1][:-5]))
    extents = write_usdz(parts, materials, a.out, root_name, meta)
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    print(f"{a.out}: {len(parts)} parts, size mm (w,h,d) {np.round(extents, 1).tolist()}")


if __name__ == "__main__":
    main()

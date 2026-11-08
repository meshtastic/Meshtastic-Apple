#
#  castle_tower.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/8/26.
#
#  A medieval castle tower for the visionOS cinema: the open roof of a square stone keep on a
#  summit at sunset, built on room_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P castle_tower.py -- --out out/castle_tower_gray.png --width 4096 --samples 160 --stone gray
#
#  The roof is a 6 m square of flagstones inside a low crenellated parapet whose merlons top out
#  about 6° below level from the seat, so the horizon and the valleys show over them, with a round
#  bartizan corbelled out from each open corner. There is no roof over it. The screen stands in
#  front on an oak frame. The app's boards are scrolls: two hang from one oak frame on the left, for
#  the team roster and the nodes' status messages, and one from a frame on the right, for the latest
#  trace route. Only the frames and the cords are painted; the app draws each scroll, rollers and
#  all, so a scroll rolled up shows the view behind it. Behind the seat are the trapdoor down into
#  the tower, a lit brazier, an oak bench and, on the back-left bartizan, a pole flying the
#  Meshtastic banner. `--stone` picks gray or pink stone. The light is the Kiara 8 sunset the fire lookout is lit by.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_base import (  # noqa: E402
    CACHE,
    EYE_HEIGHT,
    anchor,
    arguments,
    box,
    cylinder,
    image_material,
    link,
    material,
    mesh_object,
    plane,
    render_room,
    screen_anchor,
    smooth,
    sphere,
    torus,
)

# MARK: - The roof (meters)

# The parapet's inner face is HALF from the seat on every side, and WALL thick.
HALF = 3.0
WALL = 0.45
OUTER = HALF + WALL
# The parapet up to the crenels' sills, then the merlons, their tops about 6° below level from the
# seat like the fire lookout's sill, so the valleys below the summit show over them.
SILL = 0.55
MERLON_TOP = 0.82
# Merlons spaced as seven a side, outer corner to outer corner, the middle one in front behind the
# screen; the corner ones are left off, so the corners are open.
MERLONS = 7
MERLON_WIDTH = 0.55
# The round bartizan on each corner, centered on the corner of the parapet's outer faces.
BARTIZAN = 0.85

# The stone, by --stone: gray limestone, or Barbie pink. The flagstones are the same stone, a
# little darker and worn.
STONES = {
    "gray": (0.27, 0.26, 0.24),
    "pink": (0.78, 0.07, 0.3),
}

# The scrolls. Each one's parchment, in meters, then its rollers: the app draws a roller across the
# top and the bottom, ROLLER of the parchment's width thick, and their knobbed ends OVERHANG of it
# past each side (CinemaScroll in the app uses the same fractions). The anchor is the whole scroll.
ROLLER = 0.045
OVERHANG = 0.055
# Out at the side frames, 2.5 m from the seat, they cover the part of the view the lookout's boards
# do, at the same height above the eye.
SCROLL_X = 2.5
SCROLL_RISE = 0.405
ROSTER = (-1, 0.75, 1.1, 0.733)
STATUS = (-1, -0.75, 1.1, 0.733)
TRACE = (1, 0.75, 1.04, 0.851)
BEAM = 2.15


def scroll_size(width, height):
    """The whole scroll, rollers and knobs included: what the app fits its panel to."""
    return width * (1 + 2 * OVERHANG), height + 2 * ROLLER * width


# MARK: - Materials

def world_mapping(nodes, links, axes):
    """A vector of the shading point's world position along `axes`, two of "x", "y", "z" or "xy"
    (x and y added, so the courses run on round both kinds of wall alike)."""
    geometry = nodes.new("ShaderNodeNewGeometry")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], split.inputs[0])
    combine = nodes.new("ShaderNodeCombineXYZ")
    for slot, axis in zip(("X", "Y"), axes):
        if axis == "xy":
            add = nodes.new("ShaderNodeMath")
            add.operation = "ADD"
            links.new(split.outputs["X"], add.inputs[0])
            links.new(split.outputs["Y"], add.inputs[1])
            links.new(add.outputs[0], combine.inputs[slot])
        else:
            links.new(split.outputs[axis.upper()], combine.inputs[slot])
    return combine


def stonework(name, color, axes, block, course, mortar=0.012, wear=0.5, seed=0):
    """Dressed stone in courses, `block` long and `course` high, with recessed lime mortar, each
    block a little lighter or darker than the next, and weathering over the face."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.92
    vector = world_mapping(nodes, links, axes)
    shift = nodes.new("ShaderNodeVectorMath")
    shift.operation = "ADD"
    shift.inputs[1].default_value = (seed * 0.37, seed * 0.11, 0)
    links.new(vector.outputs[0], shift.inputs[0])
    brick = nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.5
    brick.inputs["Scale"].default_value = 1
    brick.inputs["Brick Width"].default_value = block
    brick.inputs["Row Height"].default_value = course
    brick.inputs["Mortar Size"].default_value = mortar
    brick.inputs["Mortar Smooth"].default_value = 0.3
    brick.inputs["Bias"].default_value = 0
    brick.inputs["Color1"].default_value = (*[c * 1.12 for c in color], 1)
    brick.inputs["Color2"].default_value = (*[c * 0.78 for c in color], 1)
    brick.inputs["Mortar"].default_value = (*[c * 0.6 + 0.12 for c in color], 1)
    links.new(shift.outputs[0], brick.inputs["Vector"])
    # Weathering: a broad stain and a fine pitting, multiplied over the blocks.
    stain = nodes.new("ShaderNodeTexNoise")
    stain.inputs["Scale"].default_value = 1.5
    stain.inputs["Detail"].default_value = 6
    links.new(shift.outputs[0], stain.inputs["Vector"])
    stain_ramp = nodes.new("ShaderNodeValToRGB")
    stain_ramp.color_ramp.elements[0].position = 0.3
    stain_ramp.color_ramp.elements[0].color = (1 - 0.55 * wear, 1 - 0.52 * wear, 1 - 0.5 * wear, 1)
    stain_ramp.color_ramp.elements[1].position = 0.75
    stain_ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(stain.outputs["Fac"], stain_ramp.inputs["Fac"])
    stained = nodes.new("ShaderNodeMix")
    stained.data_type = "RGBA"
    stained.blend_type = "MULTIPLY"
    stained.inputs["Factor"].default_value = 1
    links.new(brick.outputs["Color"], stained.inputs["A"])
    links.new(stain_ramp.outputs["Color"], stained.inputs["B"])
    links.new(stained.outputs["Result"], bsdf.inputs["Base Color"])
    # The mortar sits back from the faces, and the faces are rough-dressed.
    pits = nodes.new("ShaderNodeTexNoise")
    pits.inputs["Scale"].default_value = 60
    pits.inputs["Detail"].default_value = 8
    links.new(shift.outputs[0], pits.inputs["Vector"])
    height = nodes.new("ShaderNodeMath")
    height.operation = "MULTIPLY_ADD"
    height.inputs[1].default_value = 0.25
    links.new(pits.outputs["Fac"], height.inputs[0])
    links.new(brick.outputs["Fac"], height.inputs[2])
    invert = nodes.new("ShaderNodeMath")
    invert.operation = "SUBTRACT"
    invert.inputs[0].default_value = 1
    links.new(height.outputs[0], invert.inputs[1])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.02
    links.new(invert.outputs[0], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def oak(name, color=(0.1, 0.06, 0.032)):
    """Old oak: dark and weathered, with streaks of grain up its length and a rough bump."""
    mat = material(name, color, 0.8)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    stretch = nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (60, 60, 4)
    links.new(coords.outputs["Object"], stretch.inputs["Vector"])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 1
    grain.inputs["Detail"].default_value = 8
    links.new(stretch.outputs[0], grain.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*[c * 0.65 for c in color], 1)
    ramp.color_ramp.elements[1].color = (*[c * 1.3 for c in color], 1)
    links.new(grain.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    links.new(grain.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def iron(name):
    return material(name, (0.05, 0.045, 0.04), 0.65, metallic=0.7)


# MARK: - The tower top

def merlon_centers():
    """Where the merlons stand along a side, outer corner to outer corner."""
    length = 2 * OUTER
    crenel = (length - MERLONS * MERLON_WIDTH) / (MERLONS - 1)
    return [-OUTER + MERLON_WIDTH / 2 + i * (MERLON_WIDTH + crenel) for i in range(MERLONS)]


def on_side(side, u, out, z):
    """A point `u` along `side` ("front", "back", "left", "right"), increasing to the viewer's right
    as they face that side, `out` from the parapet's inner face, at height `z`."""
    if side == "front":
        return (u, HALF + out, z)
    if side == "back":
        return (-u, -HALF - out, z)
    if side == "left":
        return (-HALF - out, u, z)
    return (HALF + out, -u, z)


def along(side, length, thickness, height):
    return (length, thickness, height) if side in ("front", "back") else (thickness, length, height)


def cone(name, center, r_bottom, r_top, bottom, top, mat, segments=32):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=top - bottom)
    obj = mesh_object(name, build, mat, (center[0], center[1], (bottom + top) / 2))
    smooth(obj)
    return obj


def build_tower(stone):
    color = STONES[stone]
    wall = stonework("Ashlar", color, ("xy", "z"), 0.55, 0.3, seed=1)
    coping = stonework("Coping", [c * 0.95 for c in color], ("xy", "z"), 0.7, 0.12, mortar=0.008, wear=0.7, seed=2)
    flags = stonework("Flagstones", [c * 0.82 for c in color], ("x", "y"), 0.75, 0.55, mortar=0.01, wear=0.8, seed=3)

    # The roof: flagstones out under the parapet, and the keep's walls below it, which only show
    # down through the crenels at the bartizans.
    box("Roof", (2 * OUTER, 2 * OUTER, 0.3), (0, 0, -0.15), flags)
    box("Keep", (2 * OUTER, 2 * OUTER, 6), (0, 0, -3.3), wall)

    for side in ("front", "back", "left", "right"):
        # The parapet up to the crenels' sills, corner to corner on the front and back, between
        # them on the sides, with a coping course along its top.
        reach = OUTER if side in ("front", "back") else HALF
        box("Parapet" + side, along(side, 2 * reach, WALL, SILL - 0.06), on_side(side, 0, WALL / 2, (SILL - 0.06) / 2), wall, bevel=0.01)
        box("ParapetCoping" + side, along(side, 2 * reach, WALL + 0.06, 0.06), on_side(side, 0, WALL / 2, SILL - 0.03), coping, bevel=0.012)
        for u in merlon_centers()[1:-1]:
            box("Merlon" + side, along(side, MERLON_WIDTH, WALL, MERLON_TOP - SILL - 0.05), on_side(side, u, WALL / 2, (SILL + MERLON_TOP - 0.05) / 2), wall, bevel=0.015)
            box("MerlonCap" + side, along(side, MERLON_WIDTH + 0.04, WALL + 0.04, 0.05), on_side(side, u, WALL / 2, MERLON_TOP - 0.025), coping, bevel=0.012)

    # A round bartizan on each corner, corbelled out on a cone of stone, its top level with the
    # crenels' sills and nothing on it, so the corners stay open.
    for sx in (-1, 1):
        for sy in (-1, 1):
            center = (sx * OUTER, sy * OUTER)
            cylinder("Bartizan", BARTIZAN, (center[0], center[1], -1.4), (center[0], center[1], SILL - 0.06), wall, segments=48)
            cylinder("BartizanCoping", BARTIZAN + 0.03, (center[0], center[1], SILL - 0.06), (center[0], center[1], SILL), coping, segments=48)
            cone("BartizanCorbel", center, 0.25, BARTIZAN, -2.6, -1.4, wall)


# MARK: - Frames

def post(name, x, y, height, mat, size=0.09):
    return box(name, (size, size, height), (x, y, height / 2), mat, bevel=0.008)


def brace(name, start, end, mat, size=0.06):
    """A square timber from `start` to `end`."""
    start, end = Vector(start), Vector(end)
    direction = end - start
    obj = box(name, (size, size, direction.length), (start + end) / 2, mat, bevel=0.006)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def scroll_frame(sx, posts_along, wood, metal):
    """An oak gallows frame standing at x = sx * SCROLL_X, its posts at `posts_along` (y), on sledge
    feet, with a crossbeam over them and knee braces under it."""
    x = sx * SCROLL_X
    low, high = min(posts_along), max(posts_along)
    for y in posts_along:
        post("ScrollPost", x, y, BEAM + 0.04, wood)
        box("ScrollFoot", (0.6, 0.1, 0.08), (x, y, 0.04), wood, bevel=0.008)
        for dx in (-1, 1):
            brace("ScrollFootBrace", (x + dx * 0.24, y, 0.08), (x + dx * 0.04, y, 0.42), wood, size=0.05)
    box("ScrollBeam", (0.1, high - low + 0.3, 0.1), (x, (low + high) / 2, BEAM + 0.09), wood, bevel=0.008)
    for y in posts_along:
        for dy in (-1, 1):
            if low - 0.01 < y + dy * 0.3 < high + 0.01:
                brace("ScrollKnee", (x, y, BEAM - 0.22), (x, y + dy * 0.22, BEAM + 0.04), wood, size=0.05)
        # Iron strap where the post meets the beam.
        box("ScrollStrap", (0.12, 0.1, 0.03), (x, y, BEAM + 0.02), metal)


def hang_scroll(board_id, spec, wood, metal, cord):
    """Hangs one scroll's cords from its frame and records its anchor. The scroll itself is the
    app's to draw."""
    sx, y, width, height = spec
    x = sx * SCROLL_X
    total_w, total_h = scroll_size(width, height)
    z = EYE_HEIGHT + SCROLL_RISE
    top = z + total_h / 2 - ROLLER * width / 2
    for dy in (-1, 1):
        end = y + dy * (width / 2 + OVERHANG * width * 0.4)
        torus("ScrollHook", 0.018, 0.005, (x, end, BEAM + 0.015), metal, rotation=(0, math.pi / 2, 0))
        cylinder("ScrollCord", 0.005, (x, end, BEAM), (x, end, top), cord, segments=8)
    # The anchor sits a hair toward the seat from the cords, facing it.
    surface = plane("Scroll" + board_id, total_w, total_h, (x - sx * 0.02, y, z), (math.pi / 2, 0, -sx * math.pi / 2), None)
    surface.hide_render = True
    anchor(board_id, surface, total_w, total_h)


def build_scrolls():
    wood = oak("ScrollOak")
    metal = iron("ScrollIron")
    cord = material("ScrollCord", (0.42, 0.33, 0.2), 0.9)
    # Left: one frame for the roster and the status scrolls, a post between them.
    reach = scroll_size(ROSTER[2], ROSTER[3])[0] / 2 + 0.08
    scroll_frame(-1, [STATUS[1] - reach, 0, ROSTER[1] + reach], wood, metal)
    hang_scroll("teamStatus", ROSTER, wood, metal, cord)
    hang_scroll("nodeStatus", STATUS, wood, metal, cord)
    # Right: the trace route's.
    reach = scroll_size(TRACE[2], TRACE[3])[0] / 2 + 0.08
    scroll_frame(1, [TRACE[1] - reach, TRACE[1] + reach], wood, metal)
    hang_scroll("traceRoute", TRACE, wood, metal, cord)


def build_screen_frame():
    """The screen stands on an oak frame in front: two posts on sledge feet, a beam across the top
    and a rail under the screen, iron-strapped. The app draws the screen over the middle."""
    wood = oak("ScreenOak")
    metal = iron("ScreenIron")
    y = 2.68
    width = 2.4
    for sx in (-1, 1):
        x = sx * (width / 2 + 0.1)
        post("ScreenPost", x, y, 2.4, wood, size=0.11)
        box("ScreenFoot", (0.12, 0.8, 0.09), (x, y, 0.045), wood, bevel=0.008)
        for dy in (-1, 1):
            brace("ScreenFootBrace", (x, y + dy * 0.34, 0.09), (x, y + dy * 0.05, 0.55), wood, size=0.06)
        for z in (0.68, 2.3):
            box("ScreenStrap", (0.14, 0.13, 0.035), (x, y, z), metal)
    box("ScreenBeam", (width + 0.5, 0.12, 0.12), (0, y, 2.36), wood, bevel=0.008)
    box("ScreenRail", (width + 0.2, 0.1, 0.1), (0, y, 0.68), wood, bevel=0.008)
    # Backing boards behind the screen, so the bezel has something plain behind it.
    box("ScreenBacking", (width + 0.1, 0.04, 1.6), (0, y + 0.05, 1.49), oak("ScreenBoards", (0.12, 0.075, 0.04)))


# MARK: - Behind the seat

def trapdoor():
    """The hatch down into the tower: oak boards in a stone curb, with iron straps and a ring."""
    wood = oak("HatchOak", (0.15, 0.09, 0.05))
    metal = iron("HatchIron")
    x, y = 0.9, -1.9
    box("HatchCurb", (1.2, 1.0, 0.04), (x, y, 0.02), material("HatchCurb", (0.3, 0.29, 0.27), 0.9))
    for i in range(5):
        box("HatchBoard", (0.2, 0.86, 0.05), (x - 0.42 + i * 0.21, y, 0.05), wood, bevel=0.006)
    for dy in (-0.28, 0.28):
        box("HatchStrap", (1.0, 0.07, 0.012), (x, y + dy, 0.08), metal)
    torus("HatchRing", 0.07, 0.01, (x + 0.35, y, 0.085), metal)


def brazier():
    """An iron brazier on three legs with glowing coals, behind the viewer's right shoulder."""
    metal = iron("BrazierIron")
    x, y = 2.1, -2.1
    cone("BrazierBowl", (x, y), 0.12, 0.3, 0.72, 0.92, metal, segments=32)
    torus("BrazierRim", 0.3, 0.015, (x, y, 0.92), metal)
    for a in (0.3, 2.4, 4.5):
        foot = (x + 0.32 * math.cos(a), y + 0.32 * math.sin(a), 0)
        cylinder("BrazierLeg", 0.018, foot, (x + 0.18 * math.cos(a), y + 0.18 * math.sin(a), 0.8), metal, segments=8)
    coals = material("Coals", (0.03, 0.01, 0), 0.9, emission=(0.9, 0.18, 0.02), strength=1.5)
    rng = random.Random(5)
    for _ in range(22):
        r, a = rng.uniform(0, 0.22), rng.uniform(0, 2 * math.pi)
        sphere("Coal", rng.uniform(0.035, 0.06), (x + r * math.cos(a), y + r * math.sin(a), 0.9 + rng.uniform(0, 0.04)), coals, segments=8)
    light = bpy.data.lights.new("Brazier", "POINT")
    light.energy = 120
    light.color = (1, 0.55, 0.25)
    light.shadow_soft_size = 0.2
    obj = bpy.data.objects.new("Brazier", light)
    obj.location = (x, y, 1.15)
    link(obj)


def bench():
    """An oak bench along the back parapet, behind the viewer's left shoulder."""
    wood = oak("BenchOak")
    x, y = -1.4, -HALF + 0.3
    box("BenchSeat", (1.6, 0.36, 0.07), (x, y, 0.45), wood, bevel=0.008)
    for dx in (-0.65, 0.65):
        box("BenchLeg", (0.08, 0.3, 0.42), (x + dx, y, 0.21), wood, bevel=0.006)
    box("BenchStretcher", (1.3, 0.05, 0.06), (x, y, 0.15), wood, bevel=0.005)


def banner_pole():
    """A pole on the back-left bartizan flying the Meshtastic banner from a crossbar."""
    metal = iron("PoleIron")
    wood = oak("PoleOak", (0.12, 0.075, 0.04))
    x, y = -OUTER, -OUTER
    top = 4.6
    cylinder("BannerPole", 0.045, (x, y, SILL), (x, y, top), wood, segments=16)
    sphere("BannerFinial", 0.07, (x, y, top + 0.05), material("Finial", (0.7, 0.55, 0.2), 0.35, metallic=0.9), segments=16)
    # The crossbar runs across the line from the seat, so the banner faces it.
    across = Vector((1, -1, 0)).normalized()
    bar = Vector((x, y, top - 0.25))
    cylinder("BannerBar", 0.022, bar - across * 0.55, bar + across * 0.55, wood, segments=12)
    flag = image_material("Banner", os.path.join(CACHE, "castle_banner.png"), 0.85)
    # Turned to face away from the seat and drawn from both sides, so its picture reads the right
    # way round from the seat.
    surface = plane("Banner", 1.0, 1.5, bar + Vector((0, 0, -0.77)) + Vector((0.03, 0.03, 0)), (math.pi / 2, 0, math.atan2(across.y, across.x) + math.pi), flag)
    surface.data.materials[0].use_backface_culling = False
    for end in (-0.5, 0.5):
        torus("BannerRing", 0.025, 0.006, bar + across * end, metal, rotation=(0, math.pi / 2, math.atan2(across.y, across.x)))


def build(stone):
    build_tower(stone)
    build_screen_frame()
    build_scrolls()
    trapdoor()
    brazier()
    bench()
    banner_pole()
    # On the frame in front, 2.6 m out: 2.4 m wide, so it covers the part of the view the lookout's
    # 2 m screen does at 2.15 m.
    screen_anchor((0, 2.6, EYE_HEIGHT + 0.34), (math.pi / 2, 0, 0), width=2.4)


STONE = arguments().get("stone", "gray")
if STONE not in STONES:
    raise SystemExit(f"unknown stone {STONE}: use one of {', '.join(STONES)}")

# Kiara 8 at sunset, turned as for the fire lookout, so the lookout's skies and the app's terrain
# shading fit this image too. The sky isn't painted: the image is a cutout over everything but the
# tower top.
render_room(lambda: build(STONE), "kiara_8_sunset_8k.hdr", hdri_rotation=3, hdri_strength=1.0, cutout=True)

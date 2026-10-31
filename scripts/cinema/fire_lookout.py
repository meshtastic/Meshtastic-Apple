#
#  fire_lookout.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/29/26.
#
#  A fire lookout for the visionOS cinema: a glass-walled cab on a rocky summit at sunset, built on
#  room_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P fire_lookout.py -- --out out/fire_lookout.png --width 4096 --samples 160
#
#  The cab is a square room with a low wall all round, windows above it on every side, a wide sill
#  shelf under them, and a catwalk with a railing outside. The storm shutters are propped open
#  over the windows except where the app needs a plain surface: the two middle bays in front are
#  shuttered for the screen, two on the left behind the whiteboards the app draws the team roster
#  and the nodes' status messages on, and one on the right behind the print it draws the latest
#  trace route on. The
#  fire finder stands to the right, the cot is along the back wall with the stove in the back-left
#  corner and the door back-right, and a lantern hangs from the ceiling. The mountains and the
#  sunset are the Kiara 8 HDRI from Poly Haven.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_base import (  # noqa: E402
    CACHE,
    EYE_HEIGHT,
    anchor,
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

# MARK: - The cab (meters)

# 4.6 m square, the viewer in the middle, 2.3 m from every wall.
HALF = 2.3
# The wall is this thick; its inner face is WALL in from HALF.
WALL = 0.12
# The low wall, then glass up to the window head, then the ceiling.
KNEE = 0.9
HEAD = 2.1
CEILING = 2.35
# Four window bays a side, between posts.
BAY = 2 * HALF / 4
POST = 0.1
SILL_DEPTH = 0.32
# The catwalk outside, and its railing: low enough that the sill hides it from the seat. At a
# real 1 m its top rail ran across every window, in front of the nodes the app marks outside.
CATWALK = 0.95
RAIL = 0.7

DEVICE_MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels")

# Each wall's outward normal. Positions along a wall are given as `u`, increasing to the viewer's
# right as they face that wall from the seat, so the bays are numbered the same way on every side.
SIDES = {"front": (0, 1), "back": (0, -1), "left": (-1, 0), "right": (1, 0)}


def at(side, u, out, z):
    """World position for a point `u` along `side`, `out` meters outside its outer face
    (negative is inside the room), at height `z`."""
    nx, ny = SIDES[side]
    if ny > 0:
        return (u, HALF + out, z)
    if ny < 0:
        return (-u, -HALF - out, z)
    if nx < 0:
        return (-HALF - out, u, z)
    return (HALF + out, -u, z)


def along(side, length, thickness, height):
    """A box size with `length` along `side` and `thickness` through it."""
    return (length, thickness, height) if SIDES[side][1] else (thickness, length, height)


def facing_in(side):
    """The rotation that lays a plane() on `side`, its face toward the room and its image upright,
    with its +X toward +u."""
    return {"front": (math.pi / 2, 0, 0), "back": (math.pi / 2, 0, math.pi),
            "left": (math.pi / 2, 0, math.pi / 2), "right": (math.pi / 2, 0, -math.pi / 2)}[side]


def bay_center(index):
    return -HALF + (index + 0.5) * BAY


# Bays with their shutters closed, by side: the screen's two in front, and one on each side
# behind a board.
CLOSED = {"front": (1, 2), "left": (1, 2), "right": (1,), "back": ()}
DOOR = ("back", 0)
ROSTER = ("left", 2)
STATUS = ("left", 1)
TRACE = ("right", 1)


# MARK: - Materials

def planks(name, color, along_axis, width, gap=0.004, roughness=0.6):
    """Painted boards `width` wide with a dark seam between them, running along `along_axis`."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    geometry = nodes.new("ShaderNodeNewGeometry")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], split.inputs[0])
    uv = nodes.new("ShaderNodeCombineXYZ")
    across = {"X": "Y", "Y": "X", "Z": "X"}[along_axis]
    links.new(split.outputs[across], uv.inputs["X"])
    links.new(split.outputs[along_axis], uv.inputs["Y"])
    brick = nodes.new("ShaderNodeTexBrick")
    brick.offset = 0
    brick.squash = 1
    brick.inputs["Scale"].default_value = 1
    brick.inputs["Brick Width"].default_value = width
    brick.inputs["Row Height"].default_value = 6
    brick.inputs["Mortar Size"].default_value = gap
    brick.inputs["Bias"].default_value = 0
    brick.inputs["Color1"].default_value = (*color, 1)
    brick.inputs["Color2"].default_value = (*[c * 0.93 for c in color], 1)
    brick.inputs["Mortar"].default_value = (*[c * 0.35 for c in color], 1)
    links.new(uv.outputs[0], brick.inputs["Vector"])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 40
    grain.inputs["Detail"].default_value = 4
    stretch = nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (1, 12, 1)
    links.new(uv.outputs[0], stretch.inputs["Vector"])
    links.new(stretch.outputs[0], grain.inputs["Vector"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.18
    links.new(brick.outputs["Color"], mix.inputs["A"])
    links.new(grain.outputs["Color"], mix.inputs["B"])
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def glass_material():
    mat = bpy.data.materials.new("Glass")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.03
    return mat


def glowing(name, path, strength):
    mat = image_material(name, path, 0.3)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    links.new(nodes["Image Texture"].outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


# MARK: - The cab

def build_cab():
    cream = (0.86, 0.84, 0.76)
    paint = planks("KneeWall", cream, "X", 0.14)
    paint_y = planks("KneeWallY", cream, "Y", 0.14)
    floor = planks("Floor", (0.52, 0.47, 0.4), "X", 0.14, roughness=0.7)
    deck = planks("Deck", (0.36, 0.3, 0.24), "Y", 0.14, roughness=0.8)
    ceiling = planks("Ceiling", (0.86, 0.84, 0.78), "Y", 0.12, roughness=0.7)
    frame = material("Frame", cream, 0.5)
    sill = material("Sill", (0.5, 0.36, 0.2), 0.5)
    glass = glass_material()
    shutter_out = material("ShutterOut", (0.22, 0.26, 0.2), 0.7)
    shutter_in = material("ShutterIn", (0.44, 0.34, 0.2), 0.8)
    rail = material("Rail", (0.24, 0.26, 0.2), 0.7)

    size = 2 * (HALF + CATWALK)
    box("Deck", (size, size, 0.06), (0, 0, -0.03), deck)
    box("Floor", (2 * HALF, 2 * HALF, 0.02), (0, 0, 0.0), floor)
    box("Ceiling", (2 * HALF + 0.3, 2 * HALF + 0.3, 0.05), (0, 0, CEILING + 0.025), ceiling)
    # Ceiling joists, and the eaves outside over the catwalk.
    joist = material("Joist", (0.5, 0.38, 0.22), 0.55)
    for x in (-1.5 * BAY, -0.5 * BAY, 0.5 * BAY, 1.5 * BAY):
        box("Joist", (0.08, 2 * HALF + 0.3, 0.12), (x, 0, CEILING - 0.06), joist)
    box("Eave", (size + 0.2, size + 0.2, 0.08), (0, 0, CEILING + 0.09), joist)

    for side in SIDES:
        wall_mat = paint if SIDES[side][1] else paint_y
        # The low wall, with its inner face WALL inside the outer face.
        box("KneeWall" + side, along(side, 2 * HALF + 0.2, WALL, KNEE), at(side, 0, -WALL / 2, KNEE / 2), wall_mat)
        # The sill shelf inside, and a drip sill outside.
        box("Sill" + side, along(side, 2 * HALF + 0.1, SILL_DEPTH, 0.035), at(side, 0, -WALL - SILL_DEPTH / 2 + 0.03, KNEE + 0.017), sill)
        box("OuterSill" + side, along(side, 2 * HALF + 0.2, 0.06, 0.03), at(side, 0, 0.03, KNEE + 0.01), frame)
        # The header over the windows.
        box("Header" + side, along(side, 2 * HALF + 0.2, WALL, CEILING - HEAD), at(side, 0, -WALL / 2, (HEAD + CEILING) / 2), wall_mat)
        # Posts between the bays, and at the corners.
        for i in range(5):
            u = -HALF + i * BAY
            box("Post" + side, along(side, POST, WALL, HEAD - KNEE), at(side, u, -WALL / 2, (KNEE + HEAD) / 2), frame)
        for bay in range(4):
            u = bay_center(bay)
            if (side, bay) == DOOR:
                build_door(side, u, frame, glass)
                continue
            pane_w, pane_h = BAY - POST, HEAD - KNEE
            plane("Glass" + side, pane_w, pane_h, at(side, u, -WALL / 2, (KNEE + HEAD) / 2), facing_in(side), glass)
            # A muntin across each pane, a little above the middle.
            box("Muntin" + side, along(side, pane_w, 0.03, 0.03), at(side, u, -WALL / 2, KNEE + pane_h * 0.62), frame)
            closed = bay in CLOSED[side]
            build_shutter(side, u, closed, shutter_out, shutter_in, frame)

    build_railing(rail)


def u_direction(side):
    """The world direction of +u along `side`."""
    return Vector(at(side, 1, 0, 0)) - Vector(at(side, 0, 0, 0))


# Turns a shutter built with its width along X, its thickness along Y and its height along Z so
# that X runs along the wall toward +u and Y points outward.
YAW = {"front": 0, "right": -math.pi / 2, "back": math.pi, "left": math.pi / 2}


def build_shutter(side, u, closed, outside, inside, prop_mat):
    """A storm shutter the width of a bay, hinged at the top: propped open as an awning over the
    window, or closed down over it."""
    width, height, thick = BAY - 0.02, HEAD - KNEE + 0.08, 0.035
    hinge = Vector(at(side, u, 0.03, HEAD + 0.04))
    nx, ny = SIDES[side]
    outward = Vector((nx, ny, 0))
    if closed:
        center = hinge + Vector((0, 0, -height / 2))
        box("ShutterClosed" + side, along(side, width, thick, height), center, outside)
        # Its inner face, as seen through the glass: bare plywood.
        plane("ShutterBack" + side, width, height, center - outward * (thick / 2 + 0.001), facing_in(side), inside)
        return
    # Open: swung up to 80 degrees from the wall, propped on two struts to the outer sill. The box
    # is tipped about its own X so its height runs from the hinge out along `direction`.
    angle = math.radians(80)
    direction = outward * math.sin(angle) - Vector((0, 0, math.cos(angle)))
    center = hinge + direction * height / 2
    box("ShutterOpen" + side, (width, thick, height), center, outside, rotation=(angle + math.pi, 0, YAW[side]))
    far = hinge + direction * (height - 0.05)
    udir = u_direction(side)
    for du in (-width / 2 + 0.1, width / 2 - 0.1):
        foot = Vector(at(side, u + du, 0.05, KNEE + 0.03))
        cylinder("ShutterProp", 0.012, foot, far + udir * du, prop_mat, segments=8)


def build_door(side, u, frame, glass):
    """A half-glass door in its bay, with Chirpy's poster on the inside of its lower panel."""
    width = BAY - POST
    paint = material("Door", (0.86, 0.84, 0.76), 0.5)
    box("DoorLower", along(side, width, 0.04, KNEE + 0.02), at(side, u, -WALL / 2, (KNEE + 0.02) / 2 + 0.01), paint)
    plane("DoorGlass", width - 0.12, HEAD - KNEE - 0.1, at(side, u, -WALL / 2, (KNEE + HEAD) / 2), facing_in(side), glass)
    for du in (-width / 2 + 0.03, width / 2 - 0.03):
        box("DoorStile", along(side, 0.06, 0.04, HEAD - KNEE), at(side, u + du, -WALL / 2, (KNEE + HEAD) / 2), paint)
    box("DoorRail", along(side, width, 0.04, 0.06), at(side, u, -WALL / 2, KNEE + 0.03), paint)
    box("DoorTop", along(side, width, 0.04, 0.05), at(side, u, -WALL / 2, HEAD - 0.025), paint)
    brass = material("Brass", (0.78, 0.6, 0.3), 0.3, metallic=1.0)
    knob = Vector(at(side, u + width / 2 - 0.09, -WALL / 2 - 0.02, 0.95))
    nx, ny = SIDES[side]
    sphere("DoorKnob", 0.025, knob - Vector((nx, ny, 0)) * 0.05, brass, segments=16)
    cylinder("DoorKnobNeck", 0.008, knob, knob - Vector((nx, ny, 0)) * 0.05, brass, segments=10)
    poster = image_material("ChirpyPoster", os.path.join(CACHE, "chirpy_poster.png"), 0.7)
    plane("Poster", 0.38, 0.53, at(side, u, -WALL / 2 - 0.021, 0.48), facing_in(side), poster)


def build_railing(rail):
    """The railing round the catwalk: posts at each bay line, two rails, and a cap."""
    edge = CATWALK - 0.06
    for side in SIDES:
        for i in range(5):
            u = -HALF - CATWALK + 0.06 + i * (HALF + CATWALK - 0.06) / 2
            box("RailPost" + side, (0.07, 0.07, RAIL), at(side, u, edge, RAIL / 2), rail)
        length = 2 * (HALF + CATWALK) - 0.05
        box("RailCap" + side, along(side, length, 0.1, 0.035), at(side, 0, edge, RAIL + 0.017), rail)
        box("RailMid" + side, along(side, length, 0.04, 0.08), at(side, 0, edge, RAIL * 0.5), rail)


# MARK: - Furniture

def fire_finder():
    """The fire finder: a round map table on a wooden cabinet, with a brass sighting ring and its
    two sights, pointed out over the mountains. The map is the topo print."""
    x, y = 1.05, -0.7
    wood = material("FinderCabinet", (0.5, 0.36, 0.2), 0.5)
    brass = material("FinderBrass", (0.72, 0.56, 0.28), 0.3, metallic=1.0)
    box("FinderCabinet", (0.5, 0.5, 0.92), (x, y, 0.46), wood, bevel=0.005)
    box("FinderDrawer", (0.44, 0.02, 0.12), (x, y - 0.25, 0.7), material("Drawer", (0.42, 0.3, 0.16), 0.5))
    sphere("DrawerPull", 0.012, (x, y - 0.27, 0.7), brass, segments=12)
    top = 0.94
    cylinder("FinderTable", 0.4, (x, y, 0.92), (x, y, top), wood, segments=64)

    def disc(bm):
        bm.loops.layers.uv.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=64, radius=0.37, calc_uvs=True)
    mesh_object("FinderMap", disc, image_material("FinderTopo", os.path.join(CACHE, "topo.png"), 0.8), (x, y, top + 0.001))
    torus("FinderRing", 0.38, 0.012, (x, y, top + 0.02), brass)
    # The sighting bar across the ring, with a sight at each end: a slit at the back and a hair at
    # the front, turned toward the right-hand mountains.
    bearing = math.radians(-35)
    across = Vector((math.cos(bearing), math.sin(bearing), 0))
    box("SightBar", (0.8, 0.03, 0.008), (x, y, top + 0.03), brass, rotation=(0, 0, bearing))
    for end, tall in ((-1, 0.14), (1, 0.12)):
        pos = Vector((x, y, top + 0.03)) + across * end * 0.37
        box("Sight", (0.006, 0.05, tall), pos + Vector((0, 0, tall / 2)), brass, rotation=(0, 0, bearing))
    cylinder("FinderPivot", 0.02, (x, y, top), (x, y, top + 0.045), brass, segments=20)


def bumpy(mat, scale, strength, colors=None):
    """Gives `mat` a noise bump, for cloth, bark and cast iron, and with `colors`, blends its base
    color between the two with the same noise."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 5
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    if colors:
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[1].position = 0.65
        ramp.color_ramp.elements[0].color = (*colors[0], 1)
        ramp.color_ramp.elements[1].color = (*colors[1], 1)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def fire_material():
    """Flames behind the stove door's window: dark red through orange to yellow, by noise."""
    mat = material("Fire", (0.05, 0.01, 0), 0.8)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 25
    noise.inputs["Detail"].default_value = 4
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.5, 0.04, 0, 1)
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = (1, 0.85, 0.3, 1)
    ramp.color_ramp.elements.new(0.52).color = (1, 0.35, 0.03, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 10
    return mat


def split_log(name, start, end, radius, bark, wood, turn):
    """A split log from `start` to `end`: a half round with bark on the curve and pale wood on the
    flat face and the ends, its flat face turned `turn` radians about its length."""
    start, end = Vector(start), Vector(end)
    direction = end - start
    n = 10

    def build(bm):
        half = direction.length / 2
        rings = [[bm.verts.new((radius * math.cos(a), radius * math.sin(a), z)) for a in (math.pi * i / n for i in range(n + 1))] for z in (-half, half)]
        for ring in rings:
            bm.faces.new(ring).material_index = 1
        for i in range(n):
            bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i])).material_index = 0
        bm.faces.new((rings[0][n], rings[0][0], rings[1][0], rings[1][n])).material_index = 1
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, build, bark, (start + end) / 2)
    obj.data.materials.append(wood)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y") @ Quaternion((0, 0, 1), turn)
    for polygon in obj.data.polygons:
        polygon.use_smooth = polygon.material_index == 0
    return obj


def cot():
    """A folding cot along the back wall, with a mummy sleeping bag laid out on it, zipped, and a
    pillow on its hood."""
    cx, cy, z = -0.3, -1.7, 0.42
    length, width = 1.9, 0.7
    tube = material("CotTube", (0.3, 0.3, 0.32), 0.4, metallic=0.8)
    canvas = material("CotCanvas", (0.3, 0.33, 0.24), 0.9)
    box("CotCanvas", (length, width, 0.03), (cx, cy, z), canvas)
    for dx in (-length / 2 + 0.1, length / 2 - 0.1):
        for dy in (-width / 2 + 0.02, width / 2 - 0.02):
            cylinder("CotLeg", 0.012, (cx + dx + 0.12 * (1 if dy > 0 else -1), cy - dy, 0), (cx + dx, cy + dy, z - 0.01), tube)
    for dy in (-width / 2 + 0.02, width / 2 - 0.02):
        cylinder("CotRail", 0.014, (cx - length / 2, cy + dy, z + 0.01), (cx + length / 2, cy + dy, z + 0.01), tube)
    # A mummy bag laid out on the canvas, zipped, with its quilting stitched across it, and a
    # pillow on its hood.
    head = cx - 0.85
    mummy_bag((head, cy + 0.01, z + 0.015))
    # Across the cot, its long side with the bag's width.
    pillow((head + 0.24, cy + 0.01, z + 0.015 + 0.11), math.radians(90))


# The bag's outline from its hood to its feet: distance along it, and its half width there.
BAG_OUTLINE = [(0, 0.2), (0.12, 0.27), (0.4, 0.32), (0.9, 0.3), (1.3, 0.24), (1.6, 0.2), (1.75, 0.17)]
BAG_LOFT = 0.11


def bag_half_width(x):
    for (x0, w0), (x1, w1) in zip(BAG_OUTLINE, BAG_OUTLINE[1:]):
        if x0 <= x <= x1:
            return w0 + (w1 - w0) * (x - x0) / (x1 - x0)
    return BAG_OUTLINE[-1][1]


def mummy_bag(origin):
    """A lofted sleeping bag with its hood at `origin`, running along +X: one tapered body with
    rounded edges, quilted every 20 cm by a gentle swell in the shading and a stitched seam, and a
    zipper along its near edge."""
    nylon = bumpy(material("SleepingBag", (0.05, 0.09, 0.26), 0.5), 25, 0.12)
    nodes, links = nylon.node_tree.nodes, nylon.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Sheen Weight"].default_value = 0.4
    # The quilting: bands along the bag, one per 20 cm, bumped on top of the cloth's noise.
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 5
    wave.inputs["Distortion"].default_value = 0.3
    coords = nodes.new("ShaderNodeTexCoord")
    links.new(coords.outputs["Object"], wave.inputs["Vector"])
    swell = nodes.new("ShaderNodeBump")
    swell.inputs["Strength"].default_value = 0.18
    swell.inputs["Distance"].default_value = 0.02
    links.new(wave.outputs["Fac"], swell.inputs["Height"])
    cloth = bsdf.inputs["Normal"].links[0].from_node
    links.new(cloth.outputs["Normal"], swell.inputs["Normal"])
    links.new(swell.outputs["Normal"], bsdf.inputs["Normal"])

    def build(bm):
        outline = [(x, w) for x, w in BAG_OUTLINE] + [(x, -w) for x, w in reversed(BAG_OUTLINE)]
        rings = [[bm.verts.new((x, w, z)) for x, w in outline] for z in (0, BAG_LOFT)]
        bm.faces.new(rings[0])
        bm.faces.new(rings[1])
        count = len(outline)
        for i in range(count):
            j = (i + 1) % count
            bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bag = mesh_object("SleepingBag", build, nylon, origin)
    modifier = bag.modifiers.new("Bevel", "BEVEL")
    modifier.width = 0.045
    modifier.segments = 5
    smooth(bag)
    thread = material("BagThread", (0.02, 0.04, 0.12), 0.6)
    ox, oy, oz = origin
    for k in range(8):
        x = 0.15 + 0.2 * k
        half = bag_half_width(x) - 0.05
        box("BagSeam", (0.008, 2 * half, 0.003), (ox + x, oy, oz + BAG_LOFT + 0.001), thread)
    zipper = material("Zipper", (0.03, 0.03, 0.03), 0.4, metallic=0.5)
    for (x0, w0), (x1, w1) in zip(BAG_OUTLINE[1:], BAG_OUTLINE[2:]):
        a = Vector((ox + x0, oy + w0 - 0.03, oz + BAG_LOFT - 0.002))
        b = Vector((ox + x1, oy + w1 - 0.03, oz + BAG_LOFT - 0.002))
        cylinder("BagZipper", 0.004, a, b, zipper, segments=8)
    box("ZipperPull", (0.025, 0.014, 0.008), (ox + 0.14, oy + bag_half_width(0.14) - 0.03, oz + BAG_LOFT + 0.002), zipper, bevel=0.002)
    return bag


def pillow(center, yaw):
    """A pillow lying flat, its bottom at `center`: a cushion shape, rounded-rectangular in plan
    and soft in section, turned `yaw` about the vertical."""
    cotton = bumpy(material("Pillow", (0.88, 0.85, 0.76), 0.9), 30, 0.15)
    a, b, c = 0.24, 0.17, 0.055
    rows, cols = 14, 28

    def shaped(w, e):
        return math.copysign(abs(math.cos(w)) ** e, math.cos(w)), math.copysign(abs(math.sin(w)) ** e, math.sin(w))

    def build(bm):
        rings = []
        for i in range(1, rows):
            u = -math.pi / 2 + math.pi * i / rows
            cu, su = shaped(u, 0.9)
            ring = []
            for j in range(cols):
                v = -math.pi + 2 * math.pi * j / cols
                cv, sv = shaped(v, 0.35)
                ring.append(bm.verts.new((a * cu * cv, b * cu * sv, c * su)))
            rings.append(ring)
        bottom = bm.verts.new((0, 0, -c))
        top = bm.verts.new((0, 0, c))
        for ring, nxt in zip(rings, rings[1:]):
            for j in range(cols):
                bm.faces.new((ring[j], ring[(j + 1) % cols], nxt[(j + 1) % cols], nxt[j]))
        for j in range(cols):
            bm.faces.new((bottom, rings[0][(j + 1) % cols], rings[0][j]))
            bm.faces.new((top, rings[-1][j], rings[-1][(j + 1) % cols]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object("Pillow", build, cotton, (center[0], center[1], center[2] + c), (0, 0, yaw))
    smooth(obj)
    return obj


def stove():
    """A small cast iron box stove in the back-left corner on a steel hearth pad, heat shields on
    the walls behind it, its pipe up through the ceiling, and the fire showing in its door. Split
    firewood is stacked against the left wall beside it."""
    x, y = -1.8, -1.8
    iron = bumpy(material("Iron", (0.035, 0.035, 0.04), 0.55, metallic=0.2), 80, 0.25)
    box("HearthPad", (0.9, 0.9, 0.006), (x + 0.05, y + 0.08, 0.023), material("HearthPad", (0.2, 0.2, 0.21), 0.5, metallic=0.6), bevel=0.002)
    shield = material("HeatShield", (0.55, 0.56, 0.58), 0.35, metallic=0.8)
    inner = -HALF + WALL
    plane("HeatShieldBack", 0.7, 0.75, (x, inner + 0.02, 0.47), facing_in("back"), shield)
    plane("HeatShieldLeft", 0.7, 0.75, (inner + 0.02, y, 0.47), facing_in("left"), shield)
    box("StoveBody", (0.42, 0.4, 0.46), (x, y, 0.45), iron, bevel=0.012)
    for dx in (-0.16, 0.16):
        for dy in (-0.15, 0.15):
            cylinder("StoveLeg", 0.018, (x + dx * 1.15, y + dy * 1.15, 0.03), (x + dx, y + dy, 0.24), iron)
            sphere("StoveFoot", 0.025, (x + dx * 1.15, y + dy * 1.15, 0.035), iron, segments=10)
    box("StoveTop", (0.48, 0.46, 0.025), (x, y, 0.69), iron, bevel=0.006)
    for lid_x, lid_y, radius in ((x + 0.05, y + 0.08, 0.085), (x - 0.12, y + 0.1, 0.06)):
        cylinder("StoveLid", radius, (lid_x, lid_y, 0.702), (lid_x, lid_y, 0.71), iron, segments=32)
        torus("StoveLidRing", radius, 0.005, (lid_x, lid_y, 0.71), iron)
    # The flue from the back of the top, in sections, with its damper handle.
    flue_y = y - 0.1
    cylinder("StovePipe", 0.06, (x, flue_y, 0.7), (x, flue_y, CEILING), iron, segments=24)
    for seam_z in (1.2, 1.7):
        torus("PipeSeam", 0.062, 0.004, (x, flue_y, seam_z), iron)
    cylinder("PipeDamper", 0.005, (x - 0.1, flue_y, 1.35), (x + 0.1, flue_y, 1.35), iron, segments=8)
    cylinder("PipeDamperHandle", 0.01, (x + 0.1, flue_y, 1.35), (x + 0.17, flue_y, 1.35), iron, segments=10)
    cylinder("StoveCollar", 0.09, (x, flue_y, CEILING - 0.03), (x, flue_y, CEILING), iron, segments=24)
    # The door on the front: hinged on the left, a spring handle on the right, a window with the
    # fire behind three bars, the spin damper below it and the ash lip under it.
    door_x, door_z = x, 0.44
    box("StoveDoorFrame", (0.34, 0.012, 0.34), (door_x, y + 0.206, door_z), iron, bevel=0.004)
    box("StoveDoor", (0.3, 0.014, 0.3), (door_x, y + 0.219, door_z), iron, bevel=0.005)
    plane("StoveWindow", 0.18, 0.09, (door_x, y + 0.2265, door_z + 0.05), facing_in("back"), fire_material())
    for dx in (-0.045, 0, 0.045):
        cylinder("StoveBar", 0.003, (door_x + dx, y + 0.229, door_z + 0.005), (door_x + dx, y + 0.229, door_z + 0.095), iron, segments=8)
    for dz in (-0.1, 0.1):
        cylinder("StoveHinge", 0.009, (x - 0.16, y + 0.222, door_z + dz - 0.03), (x - 0.16, y + 0.222, door_z + dz + 0.03), iron, segments=10)
    cylinder("StoveHandle", 0.007, (x + 0.12, y + 0.226, door_z), (x + 0.12, y + 0.3, door_z), iron, segments=10)
    cylinder("StoveHandleGrip", 0.012, (x + 0.12, y + 0.3, door_z), (x + 0.12, y + 0.34, door_z), material("HandleWood", (0.35, 0.22, 0.1), 0.5), segments=10)
    torus("StoveDamper", 0.03, 0.005, (door_x, y + 0.23, door_z - 0.08), iron, rotation=(math.pi / 2, 0, 0))
    for a in (0, math.pi / 2):
        cylinder("DamperSpoke", 0.004, (door_x - 0.03 * math.cos(a), y + 0.23, door_z - 0.08 - 0.03 * math.sin(a)), (door_x + 0.03 * math.cos(a), y + 0.23, door_z - 0.08 + 0.03 * math.sin(a)), iron, segments=6)
    box("StoveAshLip", (0.3, 0.05, 0.012), (door_x, y + 0.235, 0.27), iron, bevel=0.003)
    glow = bpy.data.lights.new("StoveGlow", "POINT")
    glow.energy = 15
    glow.color = (1, 0.5, 0.2)
    glow.shadow_soft_size = 0.1
    obj = bpy.data.objects.new("StoveGlow", glow)
    obj.location = (door_x, y + 0.32, door_z)
    link(obj)
    # A kettle on the big lid.
    steel = material("Kettle", (0.6, 0.6, 0.62), 0.3, metallic=1.0)
    kx, ky = x + 0.05, y + 0.08
    cylinder("Kettle", 0.1, (kx, ky, 0.71), (kx, ky, 0.87), steel, segments=32)
    torus("KettleHandle", 0.06, 0.008, (kx, ky, 0.92), steel, rotation=(math.pi / 2, 0, 0))
    cylinder("KettleSpout", 0.015, (kx, ky + 0.08, 0.8), (kx, ky + 0.18, 0.9), steel, segments=10)
    # Split firewood in a stack against the left wall in front of the stove, bark out, the rows
    # settling into each other.
    bark = bumpy(material("Bark", (0.25, 0.17, 0.1), 0.9), 60, 0.6, ((0.16, 0.1, 0.06), (0.34, 0.24, 0.14)))
    wood = bumpy(material("SplitWood", (0.62, 0.48, 0.3), 0.8), 90, 0.3, ((0.5, 0.37, 0.22), (0.7, 0.56, 0.36)))
    rng = random.Random(7)
    z = 0.02
    for row, count in enumerate((4, 3, 3, 2)):
        for i in range(count):
            radius = rng.uniform(0.04, 0.055)
            log_x = inner + 0.06 + row * 0.03 + i * 0.105 + rng.uniform(-0.005, 0.005)
            log_y = -1.1 + rng.uniform(-0.03, 0.03)
            length = rng.uniform(0.36, 0.42)
            split_log(f"Log{row}{i}", (log_x, log_y - length / 2, z + radius), (log_x, log_y + length / 2, z + radius), radius, bark, wood, rng.uniform(0, 2 * math.pi))
        z += 0.09


def stool():
    wood = material("Stool", (0.5, 0.36, 0.2), 0.5)
    x, y = -1.1, 1.25
    cylinder("StoolSeat", 0.17, (x, y, 0.43), (x, y, 0.46), wood, segments=32)
    for a in (0.5, 2.6, 4.7):
        foot = (x + 0.14 * math.cos(a), y + 0.14 * math.sin(a), 0)
        cylinder("StoolLeg", 0.015, foot, (x + 0.1 * math.cos(a), y + 0.1 * math.sin(a), 0.43), wood)


def lantern():
    """A kerosene lantern hung from the middle joist behind the seat, lit."""
    x, y = 0, -0.95
    hang = CEILING - 0.12
    black = material("LanternMetal", (0.08, 0.07, 0.06), 0.5, metallic=0.5)
    glass = material("LanternGlass", (1, 0.9, 0.7), 0.1, emission=(1, 0.75, 0.4), strength=1.5)
    top = hang - 0.08
    torus("LanternHook", 0.02, 0.003, (x, y, hang - 0.02), black, rotation=(math.pi / 2, 0, 0))
    torus("LanternBail", 0.06, 0.004, (x, y, top - 0.02), black, rotation=(math.pi / 2, 0, 0))
    cylinder("LanternCap", 0.06, (x, y, top - 0.12), (x, y, top - 0.08), black, segments=24)
    cylinder("LanternGlobe", 0.045, (x, y, top - 0.3), (x, y, top - 0.12), glass, segments=24)
    cylinder("LanternTank", 0.065, (x, y, top - 0.4), (x, y, top - 0.3), black, segments=24)
    for a in (0.8, 2.3, 3.9, 5.4):
        cylinder("LanternWire", 0.003, (x + 0.055 * math.cos(a), y + 0.055 * math.sin(a), top - 0.3), (x + 0.055 * math.cos(a), y + 0.055 * math.sin(a), top - 0.1), black, segments=6)
    mantle = sphere("LanternMantle", 0.018, (x, y, top - 0.2), material("Mantle", (1, 0.95, 0.8), emission=(1, 0.85, 0.55), strength=40), segments=12)
    mantle.visible_shadow = False
    light = bpy.data.lights.new("Lantern", "POINT")
    light.energy = 90
    light.color = (1, 0.8, 0.5)
    light.shadow_soft_size = 0.05
    obj = bpy.data.objects.new("Lantern", light)
    obj.location = (x, y, top - 0.2)
    link(obj)


def sill_things():
    """What a lookout keeps on the sill shelf: the VHF radio and a Meshtastic radio on the right,
    binoculars by the screen, a mug and a logbook on the left, and a water jug on the floor."""
    body = material("RadioBody", (0.06, 0.06, 0.065), 0.4, metallic=0.3)
    knob = material("Knob", (0.02, 0.02, 0.02), 0.35)
    shelf = KNEE + 0.035
    # The VHF base radio on the right sill, its display lit, with its mic hung on a hook beside it.
    rx, ry = HALF - WALL - 0.17, -0.5
    box("VHFRadio", (0.22, 0.26, 0.09), (rx, ry, shelf + 0.045), body, bevel=0.004)
    plane("VHFDisplay", 0.1, 0.03, (rx - 0.111, ry + 0.04, shelf + 0.06), facing_in("right"), glowing("VHFDisplay", os.path.join(CACHE, "lookout_radio.png"), 2.5))
    cylinder("VHFKnob", 0.018, (rx - 0.11, ry - 0.08, shelf + 0.05), (rx - 0.13, ry - 0.08, shelf + 0.05), knob, segments=20)
    cylinder("VHFAntennaLead", 0.004, (rx, ry + 0.13, shelf + 0.06), (rx + 0.05, ry + 0.3, shelf + 0.06), knob, segments=6)
    place_model("t-echo.usdz", (rx - 0.02, ry + 0.3), -0.3, flat=False)
    # Binoculars on the front sill beside the screen.
    bx, by = 1.6, HALF - WALL - 0.16
    for dx in (-0.035, 0.035):
        cylinder("Binocular", 0.025, (bx + dx, by - 0.08, shelf + 0.028), (bx + dx, by + 0.08, shelf + 0.028), body, segments=20)
    box("BinocularBridge", (0.05, 0.08, 0.02), (bx, by, shelf + 0.03), body)
    # A mug and the logbook on the left sill.
    mug = material("Mug", (0.2, 0.3, 0.35), 0.4)
    cylinder("Mug", 0.04, (-HALF + WALL + 0.15, 1.6, shelf), (-HALF + WALL + 0.15, 1.6, shelf + 0.1), mug, segments=24)
    torus("MugHandle", 0.025, 0.006, (-HALF + WALL + 0.19, 1.6, shelf + 0.05), mug, rotation=(0, 0, 0))
    box("Logbook", (0.2, 0.26, 0.025), (-HALF + WALL + 0.17, 1.95, shelf + 0.013), material("Logbook", (0.12, 0.2, 0.14), 0.6), bevel=0.003)
    cylinder("Pencil", 0.004, (-HALF + WALL + 0.1, 1.85, shelf + 0.03), (-HALF + WALL + 0.25, 1.92, shelf + 0.03), material("Pencil", (0.9, 0.7, 0.1), 0.5), segments=6)
    # A water jug by the stove.
    jug = material("Jug", (0.2, 0.35, 0.6), 0.3)
    cylinder("WaterJug", 0.14, (-1.3, -1.95, 0.02), (-1.3, -1.95, 0.42), jug, segments=32)
    cylinder("JugCap", 0.04, (-1.3, -1.95, 0.42), (-1.3, -1.95, 0.46), material("JugCap", (0.9, 0.9, 0.9), 0.4), segments=20)


def place_model(file_name, at_xy, yaw, flat):
    """Puts one of the app's device models on the sill shelf at real size."""
    path = os.path.abspath(os.path.join(DEVICE_MODELS, file_name))
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [obj for obj in bpy.data.objects if obj not in before]
    root = next(obj for obj in new if obj.parent is None)
    tip = Matrix.Rotation(-math.pi / 2, 4, "X") if flat else Matrix.Rotation(math.pi / 2, 4, "Z")
    root.matrix_world = Matrix.Rotation(yaw, 4, "Z") @ tip @ root.matrix_world
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(corner) for obj in new if obj.type == "MESH" for corner in obj.bound_box]
    low = min(c.z for c in corners)
    cx = (min(c.x for c in corners) + max(c.x for c in corners)) / 2
    cy = (min(c.y for c in corners) + max(c.y for c in corners)) / 2
    root.matrix_world = Matrix.Translation((at_xy[0] - cx, at_xy[1] - cy, KNEE + 0.035 - low)) @ root.matrix_world


# MARK: - Outside

SOLAR_NODE = os.path.join(DEVICE_MODELS, "seeed_solar.usdz")
SOLAR_NODE_MOUNT = Vector((0.0027, 0.117, -0.0376))


def outside():
    """On the catwalk: a Solar Node on a mast clamped to a railing post outside the right window
    and the Meshtastic flag on a staff at the front-right corner."""
    steel = material("MastSteel", (0.15, 0.15, 0.16), 0.4, metallic=0.9)
    clamp = material("Clamp", (0.02, 0.02, 0.02), 0.45)
    # The node, up above the railing where the window frames it, panel turned to the seat.
    px, py = HALF + CATWALK - 0.06, 0.6
    mast_top = (px, py, 1.95)
    cylinder("NodeMast", 0.016, (px, py, RAIL - 0.3), mast_top, steel)
    for z in (RAIL - 0.2, RAIL - 0.02):
        box("MastClamp", (0.1, 0.05, 0.04), (px, py, z), clamp)
    tilt = math.radians(20)
    yaw = math.atan2(-py, -px)
    facing = Vector((math.cos(yaw), math.sin(yaw), 0))
    mount = Vector((px, py, 1.75)) + facing * 0.045
    cylinder("NodeArm", 0.01, (px, py, mount.z), mount - facing * 0.008, clamp)
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=os.path.abspath(SOLAR_NODE))
    root = next(obj for obj in bpy.data.objects if obj not in before and obj.parent is None)
    mount_local = root.matrix_world @ SOLAR_NODE_MOUNT
    turn = Matrix.Rotation(yaw + math.pi / 2, 4, "Z") @ Matrix.Rotation(-tilt, 4, "X")
    root.matrix_world = Matrix.Translation(mount) @ turn @ Matrix.Translation(-mount_local) @ root.matrix_world

    # The flag on a staff lashed to the front-right corner post, hanging in the still evening.
    fx, fy = HALF + CATWALK - 0.06, HALF + CATWALK - 0.06
    cylinder("FlagStaff", 0.014, (fx, fy, RAIL - 0.3), (fx, fy, 2.6), steel)
    sphere("StaffFinial", 0.025, (fx, fy, 2.62), material("Finial", (0.78, 0.6, 0.3), 0.3, metallic=1.0), segments=12)
    banner = image_material("Flag", os.path.join(CACHE, "banner.png"), 0.9)
    flag = plane("Flag", 0.6, 0.3, (fx - 0.3, fy + 0.02, 2.4), (math.pi / 2, 0, 0), banner)
    flag.rotation_euler = (math.pi / 2, 0, math.radians(-8))


# MARK: - Boards

def board_light(name, location, target, width, energy):
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = width, 0.3
    light.energy = energy
    light.color = (1, 0.75, 0.5)
    light.spread = math.radians(70)
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector(target) - obj.location).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)


def build_boards():
    """The two whiteboards and the print hang inside the glass of their shuttered bays in the same
    thin dark frames, clipped to the posts either side. Smaller than the tent's, since the walls are
    closer: they cover the same part of the view."""
    z = (KNEE + HEAD) / 2
    side, bay = ROSTER
    u = bay_center(bay)
    # Inside the bay's opening, like the print, with a little clear of the posts.
    width, height = 0.95, 0.633
    frame = material("BoardFrame", (0.03, 0.03, 0.032), 0.5)
    board = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)
    box("WhiteboardFrame", along(side, width + 0.05, 0.02, height + 0.05), at(side, u, -WALL - 0.01, z), frame, bevel=0.003)
    surface = plane("Whiteboard", width, height, at(side, u, -WALL - 0.021, z), facing_in(side), board)
    anchor("teamStatus", surface, width, height)
    nx, ny = SIDES[side]
    center = Vector(at(side, u, -WALL, z))
    board_light("BoardLight", center - Vector((nx, ny, 0)) * 0.9 + Vector((0, 0, 0.75)), center + Vector((0, 0, 0.05)), width - 0.2, 2.6)

    # A second whiteboard in the next bay back: the app draws the nodes' status messages over it
    # (the "nodeStatus" anchor).
    side, bay = STATUS
    u = bay_center(bay)
    box("StatusBoardFrame", along(side, width + 0.05, 0.02, height + 0.05), at(side, u, -WALL - 0.01, z), frame, bevel=0.003)
    surface = plane("StatusBoard", width, height, at(side, u, -WALL - 0.021, z), facing_in(side), board)
    anchor("nodeStatus", surface, width, height)
    nx, ny = SIDES[side]
    center = Vector(at(side, u, -WALL, z))
    board_light("StatusLight", center - Vector((nx, ny, 0)) * 0.9 + Vector((0, 0, 0.75)), center + Vector((0, 0, 0.05)), width - 0.2, 2.6)

    side, bay = TRACE
    u = bay_center(bay)
    width, height = 0.9, 0.74
    box("PrintFrame", along(side, width + 0.05, 0.02, height + 0.05), at(side, u, -WALL - 0.01, z), frame, bevel=0.003)
    surface = plane("Print", width, height, at(side, u, -WALL - 0.021, z), facing_in(side), material("PrintMat", (0.86, 0.85, 0.82), 0.85))
    anchor("traceRoute", surface, width, height)
    nx, ny = SIDES[side]
    center = Vector(at(side, u, -WALL, z))
    board_light("PrintLight", center - Vector((nx, ny, 0)) * 0.9 + Vector((0, 0, 0.75)), center + Vector((0, 0, 0.05)), width - 0.2, 2.6)


def build():
    build_cab()
    fire_finder()
    cot()
    stove()
    stool()
    lantern()
    sill_things()
    outside()
    build_boards()
    # On the shuttered front bays, high enough that its bottom clears the sill shelf from the seat.
    # Narrower than the tent's since the wall is closer; it covers about the same part of the view.
    screen_anchor((0, HALF - WALL - 0.03, EYE_HEIGHT + 0.42), (math.pi / 2, 0, 0), width=2.0)


# Kiara 8 at sunset, turned so the sun is behind the viewer's right shoulder, lighting the cab
# through the back and right windows and leaving the screen wall in shade.
# The sunset lights the cab but is not painted: the app puts the sky, and the terrain when it has
# some, behind the glass (sky.py renders the skies).
render_room(build, "kiara_8_sunset_8k.hdr", hdri_rotation=3, hdri_strength=1.0, cutout=True)

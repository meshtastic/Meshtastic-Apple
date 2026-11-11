#
#  sky_deck.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/10/26.
#
#  A sky deck for the visionOS cinema: a glass box cantilevered off the face of one of the tallest
#  towers downtown, built on room_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P sky_deck.py -- --out out/sky_deck.png --width 4096 --samples 160
#
#  The box is 6 m across and runs 5.4 m out from the tower's face, with the seat 2.2 m out. Its
#  floor is glass from just behind the seat to the front wall, on a grid of slim steel beams, with
#  two deep girders under its sides; its front and side walls are glass floor to ceiling between
#  slim mullions, with a low handrail inside them. Behind the seat is the tower's service core, a
#  solid wall with the lift doors, the Meshtastic banner and Chirpy's poster; the tower's face falls
#  away below it. The screen hangs from the ceiling in front on a plain panel, the whiteboard the
#  app draws the team roster on to its left and the status board to its right, with the print for
#  the latest trace route on the left wall. Over the front of the box the ceiling gives way to a
#  glass strip, through which a mast with the app's Solar Node shows on the roof. The image is a
#  cutout: the app puts its own sky, and the real city when it has one, past the glass, under the
#  floor too. The light is the rooftop's, the clear sunset the fire lookout's skies are painted from.

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

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
    plane,
    render_room,
    screen_anchor,
)

# MARK: - The box (meters)

# The side walls are SIDE either side of the seat, the front wall FRONT ahead of it, and the
# tower's core BACK behind it.
SIDE = 3.0
FRONT = 3.2
BACK = 2.2
CEILING = 3.0
# The glass floor starts here, just behind the seat; behind it the floor is solid to the core.
GLASS_FROM = -1.1
# The grid of beams under the glass, clear of the line straight down from the seat.
BEAMS_X = (-3.0, -1.5, 1.5, 3.0)
BEAMS_Y = (GLASS_FROM, 0.55, 1.9, FRONT)
MULLION = 1.2
RAIL = 0.95
# The glass roof over the front of the box, from here to the front wall.
SKYLIGHT_FROM = 2.3

DEVICE_MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels")
# Where the Solar Node's back mount is in the model, as in sar_tent.py.
SOLAR_NODE_MOUNT = Vector((0.0027, 0.117, -0.0376))

# The boards hung from the ceiling, each turned to the seat: id, center, width and height.
BOARDS = (
    ("teamStatus", (-2.05, 1.85, 1.62), 1.0, 0.667),
    ("nodeStatus", (2.05, 1.85, 1.62), 1.0, 0.667),
    ("traceRoute", (-2.75, -0.2, 1.6), 0.9, 0.74),
)


# MARK: - Materials

def glass():
    mat = bpy.data.materials.new("Glass")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.03
    return mat


def steel(name, color=(0.55, 0.56, 0.57), roughness=0.3):
    return material(name, color, roughness, metallic=1.0)


def glowing(name, color, strength):
    return material(name, color, 0.4, emission=color, strength=strength)


def curtain_wall():
    """The tower's face: dark glass in a grid of pale mullions, a floor every 3.6 m."""
    mat = bpy.data.materials.new("CurtainWall")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.15
    bsdf.inputs["Metallic"].default_value = 0.6
    coords = nodes.new("ShaderNodeTexCoord")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coords.outputs["Object"], split.inputs[0])
    uv = nodes.new("ShaderNodeCombineXYZ")
    links.new(split.outputs["X"], uv.inputs["X"])
    links.new(split.outputs["Z"], uv.inputs["Y"])
    brick = nodes.new("ShaderNodeTexBrick")
    brick.offset = 0
    brick.inputs["Scale"].default_value = 1
    brick.inputs["Brick Width"].default_value = 1.5
    brick.inputs["Row Height"].default_value = 3.6
    brick.inputs["Mortar Size"].default_value = 0.08
    brick.inputs["Color1"].default_value = (0.09, 0.12, 0.15, 1)
    brick.inputs["Color2"].default_value = (0.11, 0.14, 0.17, 1)
    brick.inputs["Mortar"].default_value = (0.55, 0.56, 0.57, 1)
    links.new(uv.outputs[0], brick.inputs["Vector"])
    links.new(brick.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# MARK: - Helpers

def strut(name, start, end, mat, size=0.05):
    """A square member from `start` to `end`."""
    start, end = Vector(start), Vector(end)
    middle = (start + end) / 2
    direction = end - start
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    return box(name, (size, size, direction.length), middle, mat, rotation=rotation)


def facing_seat(x, y):
    """The rotation that stands a plane up at (x, y) facing the seat."""
    return (math.pi / 2, 0, math.atan2(-x, y))


def point_light(name, location, energy, color, radius=0.05):
    light = bpy.data.lights.new(name, "POINT")
    light.energy = energy
    light.color = color
    light.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    link(obj)
    return obj


def area_light(name, location, target, size, energy, color=(1, 0.93, 0.85)):
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = size
    light.energy = energy
    light.color = color
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    link(obj)
    return obj


# MARK: - The floor

def build_floor():
    """Glass from just behind the seat to the front wall on a grid of slim beams, with two deep
    girders under the sides carrying the box out from the tower; solid behind the glass."""
    frame = steel("FloorSteel", (0.24, 0.25, 0.27), 0.4)
    girder = steel("Girder", (0.3, 0.31, 0.33), 0.45)
    solid = material("Terrazzo", (0.62, 0.61, 0.58), 0.35)
    glazing = glass()
    # The solid strip at the back, where the box meets the core.
    box("FloorSolid", (2 * SIDE, GLASS_FROM + BACK, 0.12), (0, (GLASS_FROM - BACK) / 2, -0.06), solid)
    # The glass in one pane per bay, a hair below the beams' tops.
    xs, ys = (-SIDE,) + BEAMS_X[1:-1] + (SIDE,), BEAMS_Y
    for x0, x1 in zip(xs, xs[1:]):
        for y0, y1 in zip(ys, ys[1:]):
            box("FloorGlass", (x1 - x0 - 0.04, y1 - y0 - 0.04, 0.03), ((x0 + x1) / 2, (y0 + y1) / 2, -0.02), glazing)
    for x in BEAMS_X:
        box("FloorBeamY", (0.06, FRONT - GLASS_FROM, 0.14), (x, (FRONT + GLASS_FROM) / 2, -0.07), frame)
    for y in BEAMS_Y:
        box("FloorBeamX", (2 * SIDE, 0.06, 0.14), (0, y, -0.07), frame)
    # The girders under the side walls, deep at the tower and tapering out to the front.
    for x in (-SIDE, SIDE):
        box("GirderWeb", (0.05, FRONT + BACK, 0.7), (x, (FRONT - BACK) / 2, -0.49), girder)
        box("GirderFlange", (0.24, FRONT + BACK, 0.04), (x, (FRONT - BACK) / 2, -0.86), girder)
        strut("GirderBrace", (x, -BACK, -0.84), (x, FRONT, -0.16), girder, size=0.06)


# MARK: - The walls and roof

def build_walls():
    """Glass floor to ceiling on the front and sides between slim mullions, a low steel handrail
    inside them, and the ceiling over it all with a glass strip over the front."""
    glazing = glass()
    mullion = steel("Mullion", (0.2, 0.21, 0.23), 0.4)
    rail = steel("Handrail", (0.72, 0.73, 0.74), 0.25)
    walls = [
        ("front", Vector((-SIDE, FRONT, 0)), Vector((SIDE, FRONT, 0))),
        ("left", Vector((-SIDE, -BACK, 0)), Vector((-SIDE, FRONT, 0))),
        ("right", Vector((SIDE, -BACK, 0)), Vector((SIDE, FRONT, 0))),
    ]
    for name, a, b in walls:
        length = (b - a).length
        along_x = abs(b.x - a.x) > 0.1
        bays = max(1, round(length / MULLION))
        for i in range(bays + 1):
            p = a.lerp(b, i / bays)
            box("Mullion" + name, (0.05, 0.05, CEILING), (p.x, p.y, CEILING / 2), mullion)
        for i in range(bays):
            p = a.lerp(b, (i + 0.5) / bays)
            width = length / bays - 0.06
            size = (width, 0.02, CEILING - 0.04) if along_x else (0.02, width, CEILING - 0.04)
            box("Glass" + name, size, (p.x, p.y, CEILING / 2), glazing)
        # The handrail 15 cm in from the glass, on a bracket at each mullion.
        inward = Vector((0, -0.15, 0)) if name == "front" else Vector((0.15 if name == "left" else -0.15, 0, 0))
        ra, rb = a + inward, b + inward
        cylinder("Handrail" + name, 0.022, (ra.x, ra.y, RAIL), (rb.x, rb.y, RAIL), rail, segments=20)
        for i in range(bays + 1):
            p = a.lerp(b, i / bays)
            q = p + inward
            cylinder("RailBracket" + name, 0.012, (p.x, p.y, RAIL), (q.x, q.y, RAIL), rail, segments=8)
    # The ceiling, solid back to the core, then the glass strip over the front.
    ceiling = material("Ceiling", (0.82, 0.82, 0.8), 0.6)
    fascia = steel("Fascia", (0.22, 0.23, 0.25), 0.4)
    depth = SKYLIGHT_FROM + BACK
    box("Ceiling", (2 * SIDE + 0.1, depth, 0.25), (0, (SKYLIGHT_FROM - BACK) / 2, CEILING + 0.125), ceiling)
    box("SkylightGlass", (2 * SIDE, FRONT - SKYLIGHT_FROM, 0.03), (0, (FRONT + SKYLIGHT_FROM) / 2, CEILING + 0.2), glazing)
    for x in (-SIDE, -SIDE / 3, SIDE / 3, SIDE):
        box("SkylightRib", (0.05, FRONT - SKYLIGHT_FROM, 0.12), (x, (FRONT + SKYLIGHT_FROM) / 2, CEILING + 0.16), mullion)
    box("FasciaFront", (2 * SIDE + 0.2, 0.12, 0.35), (0, FRONT + 0.03, CEILING + 0.12), fascia)
    for x in (-SIDE - 0.03, SIDE + 0.03):
        box("FasciaSide", (0.12, FRONT + BACK, 0.35), (x, (FRONT - BACK) / 2, CEILING + 0.12), fascia)
    # Recessed downlights in a grid, a few of them really lighting the room.
    lens = glowing("Downlight", (1, 0.9, 0.78), 25)
    for x in (-2.0, 0.0, 2.0):
        for y in (-1.4, 0.0, 1.4):
            cylinder("Downlight", 0.07, (x, y, CEILING + 0.001), (x, y, CEILING - 0.004), lens, segments=20)
            if x == 0.0 or y == 0.0:
                point_light("DownlightLight", (x, y, CEILING - 0.1), 18, (1, 0.9, 0.78), radius=0.06)


# MARK: - The core

def build_core():
    """The tower's service core behind the seat: a solid wall with the lift doors, the banner and
    Chirpy's poster, and the tower's face falling away below it and out either side."""
    wall = material("CoreWall", (0.74, 0.72, 0.68), 0.55)
    door = steel("LiftDoor", (0.6, 0.61, 0.62), 0.25)
    trim = steel("LiftTrim", (0.3, 0.31, 0.33), 0.35)
    y = -BACK
    box("Core", (2 * SIDE + 0.4, 0.3, CEILING + 0.6), (0, y - 0.15, (CEILING + 0.6) / 2), wall)
    for x in (-0.48, 0.48):
        box("LiftDoor", (0.94, 0.04, 2.15), (x * 0.5 + 0.0, y + 0.02, 1.075), door)
    box("LiftFrame", (1.1, 0.05, 0.08), (0, y + 0.03, 2.19), trim)
    for x in (-0.53, 0.53):
        box("LiftJamb", (0.05, 0.05, 2.2), (x, y + 0.03, 1.1), trim)
    box("LiftCall", (0.08, 0.02, 0.16), (0.7, y + 0.02, 1.1), trim)
    cylinder("LiftCallButton", 0.018, (0.7, y + 0.03, 1.12), (0.7, y + 0.04, 1.12), glowing("CallGlow", (1, 0.85, 0.5), 8), segments=12)
    banner = image_material("Banner", os.path.join(CACHE, "banner.png"), 0.7)
    plane("Banner", 1.1, 1.65, (-1.85, y + 0.012, 1.55), (math.pi / 2, 0, math.pi), banner)
    poster = image_material("Chirpy", os.path.join(CACHE, "chirpy_poster.png"), 0.6)
    plane("Chirpy", 0.42, 0.59, (1.75, y + 0.012, 1.45), (math.pi / 2, 0, math.pi), poster)
    # The tower's face: down from the floor to the street, and out past the box either side.
    face = curtain_wall()
    box("TowerFace", (60, 0.4, 400), (0, y - 0.5, -200.1), face)
    for x in (-1, 1):
        box("TowerFaceSide", (27, 0.4, CEILING + 1.2), (x * (SIDE + 0.2 + 13.5), y - 0.5, (CEILING + 1.2) / 2 - 0.1), face)
    # The parapet along the tower's roof, over the box.
    box("Parapet", (60, 0.6, 0.9), (0, y - 0.6, CEILING + 1.15), material("Parapet", (0.5, 0.5, 0.5), 0.5))


# MARK: - The screen and the boards

def build_screen():
    """The plain panel the screen hangs on, on two rods from the ceiling, so the view round it stays
    open."""
    panel = material("ScreenPanel", (0.13, 0.13, 0.14), 0.6)
    rod = steel("HangerRod", (0.4, 0.41, 0.42), 0.35)
    y = 2.65
    z = EYE_HEIGHT + 0.34
    box("ScreenPanel", (2.62, 0.04, 1.72), (0, y + 0.02, z), panel, bevel=0.01)
    for x in (-0.9, 0.9):
        cylinder("ScreenRod", 0.012, (x, y + 0.02, z + 0.86), (x, y + 0.02, CEILING), rod, segments=10)
    # 2.4 m wide, as on the rooftop's bulkhead.
    screen_anchor((0, y - 0.005, z), (math.pi / 2, 0, 0), width=2.4)


def build_boards():
    """The whiteboard, the status board and the print, each hung from the ceiling on two rods in a
    thin dark frame, turned to the seat."""
    frame = material("BoardFrame", (0.03, 0.03, 0.032), 0.5)
    rod = steel("BoardRod", (0.4, 0.41, 0.42), 0.35)
    mats = {
        "teamStatus": image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25),
        "nodeStatus": material("Slate", (0.06, 0.07, 0.065), 0.85),
        "traceRoute": material("PrintMat", (0.86, 0.85, 0.82), 0.85),
    }
    for board_id, (x, y, z), width, height in BOARDS:
        rotation = facing_seat(x, y)
        turn = Matrix.Rotation(rotation[2], 3, "Z")
        toward = turn @ Vector((0, -1, 0))
        across = turn @ Vector((1, 0, 0))
        center = Vector((x, y, z))
        box(board_id + "Frame", (width + 0.05, 0.02, height + 0.05), center - toward * 0.012, frame, rotation=(0, 0, rotation[2]), bevel=0.003)
        surface = plane(board_id, width, height, center + toward * 0.001, rotation, mats[board_id])
        anchor(board_id, surface, width, height)
        for side in (-1, 1):
            top = center + across * side * (width / 2 - 0.08) + Vector((0, 0, height / 2 + 0.02))
            cylinder(board_id + "Rod", 0.008, top, (top.x, top.y, CEILING), rod, segments=8)
        area_light(board_id + "Light", center + toward * 0.9 + Vector((0, 0, 0.7)), center, (width - 0.2, 0.2), 3.0)


# MARK: - The mast

def place_solar_node(mount, yaw, tilt):
    """The app's own model of the SenseCAP Solar Node, its back mount at `mount`, its panel turned to
    `yaw` and tipped back `tilt`, as in sar_tent.py."""
    path = os.path.abspath(os.path.join(DEVICE_MODELS, "seeed_solar.usdz"))
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    root = next(obj for obj in bpy.data.objects if obj not in before and obj.parent is None)
    mount_local = root.matrix_world @ SOLAR_NODE_MOUNT
    turn = Matrix.Rotation(yaw + math.pi / 2, 4, "Z") @ Matrix.Rotation(-tilt, 4, "X")
    root.matrix_world = Matrix.Translation(mount) @ turn @ Matrix.Translation(-mount_local) @ root.matrix_world


def build_mast():
    """A mast on the tower's roof over the front of the box, seen through the glass strip, with the
    Solar Node on an arm near its top."""
    pole = steel("Mast", (0.62, 0.63, 0.64), 0.35)
    base = (1.9, 2.75, CEILING + 0.25)
    cylinder("Mast", 0.03, base, (base[0], base[1], 8.5), pole, segments=16)
    box("MastFoot", (0.4, 0.4, 0.06), (base[0], base[1], base[2] + 0.03), pole)
    for dx, dy in ((0.9, 0.0), (-0.6, 0.6), (-0.4, -0.7)):
        cylinder("MastGuy", 0.004, (base[0], base[1], 6.0), (base[0] + dx, base[1] + dy, base[2]), steel("Guy", (0.3, 0.3, 0.3), 0.5), segments=6)
    cylinder("MastArm", 0.015, (base[0], base[1], 7.6), (base[0] - 0.35, base[1], 7.6), pole, segments=10)
    place_solar_node(Vector((base[0] - 0.36, base[1], 7.6)), math.pi, math.radians(15))
    # A small antenna whip at the top.
    cylinder("MastWhip", 0.008, (base[0], base[1], 8.5), (base[0], base[1], 9.4), steel("Whip", (0.08, 0.08, 0.08), 0.5), segments=8)


def build():
    build_floor()
    build_walls()
    build_core()
    build_screen()
    build_boards()
    build_mast()


# The rooftop's light, the clear sunset the fire lookout's skies are painted from, at the same turn,
# so the app's skies and its terrain and city shading fit this image too. The image is a cutout past
# the glass, the floor's included.
render_room(build, "kloppenheim_06_puresky_4k.hdr", hdri_rotation=5.5, hdri_strength=0.8, cutout=True)

#
#  city_rooftop.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  A city rooftop for the visionOS cinema: the roof deck of a tall downtown building at dusk, built
#  on room_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P city_rooftop.py -- --out out/city_rooftop.png --width 4096 --samples 160
#
#  The deck is a 7.2 m square of wood decking tiles on a low curb, with a glass railing round its
#  edges and nothing else at them, so from the seat the city shows past the railing on three sides,
#  down to the streets a few blocks out. In front is the stair bulkhead, a stucco box with the
#  screen on its plain front wall, the whiteboard the app draws the team roster on to the screen's
#  left and the print it draws the latest trace route on to its right. A sandwich board stands on
#  the deck to the right, for the nodes' status messages. Behind the seat are a wooden water tower
#  on steel legs, an HVAC unit, and a mast on a ballasted roof mount with a Yagi at the top and the
#  app's Solar Node on an arm. String lights run from the bulkhead to poles at the back corners. The
#  image is a cutout: the app puts its own sky, and the real city when it has one, past the railing.
#  The light is the clear sunset the fire lookout's skies are painted from, at the same turn, so
#  the sun is behind the viewer's right shoulder here too.

import math
import os
import random
import sys

import bmesh
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
    mesh_object,
    plane,
    render_room,
    screen_anchor,
    smooth,
    sphere,
    torus,
)

# MARK: - The deck (meters)

# The deck's edges are HALF from the seat on the sides and behind, so from the seat it hides the
# city below about 17° under level, and the railing's glass hides nothing.
HALF = 3.6
CURB = 0.15
RAIL = 1.05
# The stair bulkhead in front: its front wall FRONT from the seat, WIDE across and TALL.
FRONT = 2.7
WIDE = 5.2
TALL = 2.95
DEEP = 2.4
# The deck runs on past the bulkhead's sides to here, in front.
DECK_FRONT = FRONT + DEEP + 0.4

DEVICE_MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels")
# Where the Solar Node's back mount is in the model, as in sar_tent.py.
SOLAR_NODE_MOUNT = Vector((0.0027, 0.117, -0.0376))

# The boards on the bulkhead's front wall, either side of the screen, and the sandwich board's face.
ROSTER = (-1.92, 1.0, 0.667)
TRACE = (1.92, 0.9, 0.74)
STATUS_SIZE = (0.58, 0.87)


# MARK: - Materials

def decking(name, color):
    """Wood decking tiles: boards running one way in each 0.6 m tile and across in the next."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.75
    coords = nodes.new("ShaderNodeTexCoord")
    tiles = nodes.new("ShaderNodeTexChecker")
    tiles.inputs["Scale"].default_value = 1
    tiles.inputs["Color1"].default_value = (1, 1, 1, 1)
    tiles.inputs["Color2"].default_value = (0, 0, 0, 1)
    tile_scale = nodes.new("ShaderNodeMapping")
    tile_scale.inputs["Scale"].default_value = (1 / 1.2, 1 / 1.2, 1)
    links.new(coords.outputs["Object"], tile_scale.inputs["Vector"])
    links.new(tile_scale.outputs[0], tiles.inputs["Vector"])
    boards = []
    for axis in ("X", "Y"):
        split = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], split.inputs[0])
        uv = nodes.new("ShaderNodeCombineXYZ")
        links.new(split.outputs[axis], uv.inputs["X"])
        links.new(split.outputs["Y" if axis == "X" else "X"], uv.inputs["Y"])
        brick = nodes.new("ShaderNodeTexBrick")
        brick.offset = 0
        brick.inputs["Scale"].default_value = 1
        brick.inputs["Brick Width"].default_value = 0.6
        brick.inputs["Row Height"].default_value = 0.1
        brick.inputs["Mortar Size"].default_value = 0.004
        brick.inputs["Bias"].default_value = 0
        brick.inputs["Color1"].default_value = (*color, 1)
        brick.inputs["Color2"].default_value = (*[c * 0.85 for c in color], 1)
        brick.inputs["Mortar"].default_value = (*[c * 0.5 for c in color], 1)
        links.new(uv.outputs[0], brick.inputs["Vector"])
        boards.append(brick)
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(tiles.outputs["Fac"], mix.inputs["Factor"])
    links.new(boards[0].outputs["Color"], mix.inputs["A"])
    links.new(boards[1].outputs["Color"], mix.inputs["B"])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 30
    grain.inputs["Detail"].default_value = 6
    links.new(coords.outputs["Object"], grain.inputs["Vector"])
    weather = nodes.new("ShaderNodeMix")
    weather.data_type = "RGBA"
    weather.blend_type = "MULTIPLY"
    weather.inputs["Factor"].default_value = 0.25
    links.new(mix.outputs["Result"], weather.inputs["A"])
    links.new(grain.outputs["Color"], weather.inputs["B"])
    links.new(weather.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def stucco(name, color):
    """Painted stucco: a fine trowelled bump and a faint stain."""
    mat = material(name, color, 0.9)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    fine = nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 90
    fine.inputs["Detail"].default_value = 6
    links.new(coords.outputs["Object"], fine.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    links.new(fine.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    stain = nodes.new("ShaderNodeTexNoise")
    stain.inputs["Scale"].default_value = 1.2
    links.new(coords.outputs["Object"], stain.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*[c * 0.88 for c in color], 1)
    ramp.color_ramp.elements[1].color = (*color, 1)
    links.new(stain.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


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


def wood(name, color, scale=(80, 80, 6)):
    """Weathered timber, the grain running up its length."""
    mat = material(name, color, 0.8)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    stretch = nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = scale
    links.new(coords.outputs["Object"], stretch.inputs["Vector"])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Detail"].default_value = 8
    links.new(stretch.outputs[0], grain.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*[c * 0.7 for c in color], 1)
    ramp.color_ramp.elements[1].color = (*[c * 1.25 for c in color], 1)
    links.new(grain.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def glowing(name, color, strength):
    return material(name, color, 0.4, emission=color, strength=strength)


# MARK: - Helpers

def strut(name, start, end, mat, size=0.06):
    """A square member from `start` to `end`."""
    start, end = Vector(start), Vector(end)
    direction = end - start
    obj = box(name, (size, size, direction.length), (start + end) / 2, mat, bevel=size * 0.08)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def cone(name, center, r_bottom, r_top, bottom, top, mat, segments=40):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=top - bottom)
    obj = mesh_object(name, build, mat, (center[0], center[1], (bottom + top) / 2))
    smooth(obj)
    return obj


def area_light(name, location, target, size, energy, color=(1, 0.8, 0.55)):
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = size
    light.energy = energy
    light.color = color
    light.spread = math.radians(80)
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector(target) - obj.location).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)
    return obj


def point_light(name, location, energy, color, radius=0.05):
    light = bpy.data.lights.new(name, "POINT")
    light.energy = energy
    light.color = color
    light.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    link(obj)
    return obj


# MARK: - The deck and railing

def build_deck():
    deck = decking("Decking", (0.36, 0.25, 0.16))
    curb = stucco("Curb", (0.42, 0.4, 0.37))
    # The deck from the back edge to past the bulkhead, and the roof's own membrane under the
    # bulkhead, which no one sees.
    length = DECK_FRONT + HALF
    box("Deck", (2 * HALF, length, 0.06), (0, (DECK_FRONT - HALF) / 2, -0.03), deck)
    box("Roof", (2 * HALF + 0.6, length + 0.6, 0.4), (0, (DECK_FRONT - HALF) / 2, -0.26), curb)
    # The building's walls falling away below the curb, so the deck has an edge seen past the glass.
    box("Facade", (2 * HALF + 0.6, length + 0.6, 30), (0, (DECK_FRONT - HALF) / 2, -15.46), stucco("Facade", (0.3, 0.3, 0.31)))

    glazing = glass()
    rail = steel("Handrail", (0.7, 0.71, 0.72), 0.25)
    shoe = steel("RailShoe", (0.18, 0.18, 0.19), 0.5)
    edges = [
        ("left", (-HALF, -HALF), (-HALF, DECK_FRONT)),
        ("right", (HALF, -HALF), (HALF, DECK_FRONT)),
        ("back", (-HALF, -HALF), (HALF, -HALF)),
        ("front", (-HALF, DECK_FRONT), (HALF, DECK_FRONT)),
    ]
    for name, a, b in edges:
        a, b = Vector((*a, 0)), Vector((*b, 0))
        middle = (a + b) / 2
        length = (b - a).length
        along_x = abs(b.x - a.x) > 0.1
        size = (length, 0.3, CURB) if along_x else (0.3, length, CURB)
        box("Curb" + name, size, (middle.x, middle.y, CURB / 2), curb, bevel=0.01)
        # The glass sits in a low steel shoe on the curb, in panels with a hair of gap between.
        size = (length, 0.08, 0.1) if along_x else (0.08, length, 0.1)
        box("Shoe" + name, size, (middle.x, middle.y, CURB + 0.05), shoe)
        panels = max(1, round(length / 1.5))
        for i in range(panels):
            t = (i + 0.5) / panels
            center = a.lerp(b, t)
            width = length / panels - 0.012
            size = (width, 0.014, RAIL - CURB - 0.12) if along_x else (0.014, width, RAIL - CURB - 0.12)
            box("Glass" + name, size, (center.x, center.y, CURB + 0.1 + (RAIL - CURB - 0.12) / 2), glazing)
        cylinder("Handrail" + name, 0.024, (a.x, a.y, RAIL), (b.x, b.y, RAIL), rail, segments=20)


# MARK: - The bulkhead

def build_bulkhead():
    wall = stucco("Bulkhead", (0.5, 0.45, 0.38))
    coping = steel("Coping", (0.32, 0.33, 0.34), 0.45)
    y = FRONT + DEEP / 2
    box("Bulkhead", (WIDE, DEEP, TALL), (0, y, TALL / 2), wall)
    box("BulkheadCoping", (WIDE + 0.08, DEEP + 0.08, 0.08), (0, y, TALL + 0.03), coping, bevel=0.01)
    # A base course of darker paint where the deck meets the wall.
    box("BulkheadBase", (WIDE + 0.02, DEEP + 0.02, 0.18), (0, y, 0.09), stucco("BulkheadBase", (0.28, 0.27, 0.26)))

    # The steel door on the left side, with a wall pack over it, lit.
    door = material("Door", (0.16, 0.22, 0.24), 0.45, metallic=0.4)
    x = -WIDE / 2 - 0.01
    box("DoorFrame", (0.04, 1.06, 2.16), (x, FRONT + 1.0, 1.08), coping)
    box("Door", (0.05, 0.94, 2.08), (x - 0.01, FRONT + 1.0, 1.04), door)
    box("DoorPush", (0.03, 0.5, 0.05), (x - 0.04, FRONT + 1.0, 1.0), steel("PushBar"))
    box("DoorSign", (0.01, 0.34, 0.12), (x - 0.04, FRONT + 1.0, 1.65), material("DoorSign", (0.85, 0.82, 0.7), 0.6))
    box("WallPack", (0.14, 0.26, 0.18), (x - 0.07, FRONT + 1.0, 2.45), coping, bevel=0.01)
    plane("WallPackLens", 0.22, 0.05, (x - 0.07, FRONT + 1.0, 2.355), (math.pi, 0, 0), glowing("WallPackGlow", (1, 0.82, 0.6), 30))
    spot = bpy.data.lights.new("WallPack", "SPOT")
    spot.energy = 60
    spot.color = (1, 0.82, 0.6)
    spot.spot_size = math.radians(110)
    spot.spot_blend = 0.6
    obj = bpy.data.objects.new("WallPack", spot)
    obj.location = (x - 0.12, FRONT + 1.0, 2.33)
    link(obj)

    # A vent stack and a conduit run on the roof of the bulkhead, so its top edge isn't bare.
    vent = steel("Vent", (0.45, 0.46, 0.47), 0.4)
    cylinder("VentStack", 0.1, (1.6, y + 0.4, TALL), (1.6, y + 0.4, TALL + 0.7), vent)
    cone("VentCap", (1.6, y + 0.4), 0.2, 0.02, TALL + 0.72, TALL + 0.86, vent)
    box("Conduit", (0.04, DEEP - 0.2, 0.04), (WIDE / 2 - 0.12, y, TALL - 0.35), coping)


def build_boards():
    """The whiteboard and the print hang on the bulkhead's front wall either side of the screen, in
    thin dark frames, lit from above by little gooseneck lamps, as a shop sign is."""
    frame = material("BoardFrame", (0.03, 0.03, 0.032), 0.5)
    lamp = material("BoardLamp", (0.05, 0.05, 0.055), 0.4, metallic=0.6)
    z = EYE_HEIGHT + 0.34
    face = FRONT - 0.02
    for board_id, (x, width, height), mat in (
        ("teamStatus", ROSTER, image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)),
        ("traceRoute", TRACE, material("PrintMat", (0.86, 0.85, 0.82), 0.85)),
    ):
        box(board_id + "Frame", (width + 0.05, 0.02, height + 0.05), (x, FRONT - 0.01, z), frame, bevel=0.003)
        surface = plane(board_id, width, height, (x, face - 0.001, z), (math.pi / 2, 0, 0), mat)
        anchor(board_id, surface, width, height)
        top = z + height / 2 + 0.25
        cylinder(board_id + "Gooseneck", 0.008, (x, FRONT, top), (x, FRONT - 0.3, top + 0.05), lamp, segments=8)
        cone(board_id + "Shade", (x, FRONT - 0.32), 0.05, 0.03, top - 0.02, top + 0.06, lamp)
        area_light(board_id + "Light", (x, FRONT - 0.7, top + 0.1), (x, face, z), (width - 0.2, 0.2), 4.0)


def sandwich_board():
    """An A-frame sandwich board on the deck to the right, a little way out, turned to the seat. Its
    blank chalkboard face is the status board."""
    timber = wood("SandwichWood", (0.22, 0.14, 0.08))
    hinge = steel("SandwichHinge", (0.2, 0.2, 0.2), 0.5)
    slate = material("Slate", (0.05, 0.06, 0.055), 0.85)
    x, y = 2.3, 1.15
    # Its own frame: +Y toward the seat, the two panels hinged together at the top and leaning
    # apart to their feet.
    yaw = math.atan2(x, -y)
    lean = math.radians(12)
    width, height = STATUS_SIZE
    frame_w, frame_h = width + 0.1, height + 0.2
    base = Vector((x, y, 0))
    turn = Matrix.Rotation(yaw, 3, "Z")
    for side in (1, -1):
        tilt = Matrix.Rotation(side * lean, 3, "X")
        center = base + turn @ Vector((0, side * frame_h / 2 * math.sin(lean), frame_h / 2 * math.cos(lean)))
        box("SandwichPanel", (frame_w, 0.025, frame_h), center, timber, rotation=(turn @ tilt).to_euler(), bevel=0.006)
    tilt = Matrix.Rotation(lean, 3, "X")
    normal = turn @ tilt @ Vector((0, 1, 0))
    panel_center = base + turn @ Vector((0, frame_h / 2 * math.sin(lean), frame_h / 2 * math.cos(lean)))
    face_center = panel_center + turn @ tilt @ Vector((0, 0, 0.03)) + normal * 0.014
    rotation = (turn @ tilt @ Matrix.Rotation(math.pi, 3, "Z") @ Matrix.Rotation(math.pi / 2, 3, "X")).to_euler()
    plane("SandwichSlate", width, height, face_center, rotation, slate)
    surface = plane("SandwichFace", width, height, face_center + normal * 0.002, rotation, None)
    surface.hide_render = True
    anchor("nodeStatus", surface, width, height)
    top = base + Vector((0, 0, frame_h * math.cos(lean) + 0.01))
    across = turn @ Vector((frame_w / 2, 0, 0))
    cylinder("SandwichHinge", 0.012, top - across, top + across, hinge, segments=10)
    area_light("SandwichLight", face_center + normal * 0.9 + Vector((0, 0, 0.6)), face_center, (width, 0.2), 3.0)


# MARK: - Behind the seat

def water_tower():
    """A wooden water tank on steel legs behind the viewer's left shoulder, with a conical roof,
    steel hoops round its staves and a ladder up one leg."""
    staves = wood("TankStaves", (0.24, 0.16, 0.1), scale=(40, 40, 3))
    legs = steel("TankSteel", (0.16, 0.13, 0.11), 0.6)
    roof = material("TankRoof", (0.12, 0.1, 0.09), 0.7)
    cx, cy = -2.35, -2.45
    radius, bottom, top = 1.05, 2.5, 4.9
    cylinder("Tank", radius, (cx, cy, bottom), (cx, cy, top), staves, segments=48)
    cone("TankRoof", (cx, cy), radius + 0.08, 0.05, top, top + 0.9, roof, segments=48)
    sphere("TankFinial", 0.07, (cx, cy, top + 0.95), legs, segments=12)
    for z in (bottom + 0.25, bottom + 0.8, bottom + 1.35, bottom + 1.9, top - 0.15):
        torus("TankHoop", radius + 0.012, 0.012, (cx, cy, z), legs)
    cylinder("TankPlatform", radius + 0.12, (cx, cy, bottom - 0.1), (cx, cy, bottom), legs, segments=48)
    feet = []
    for a in (0.785, 2.356, 3.927, 5.498):
        fx, fy = cx + 1.0 * math.cos(a), cy + 1.0 * math.sin(a)
        feet.append((fx, fy))
        strut("TankLeg", (fx, fy, 0), (cx + 0.75 * math.cos(a), cy + 0.75 * math.sin(a), bottom - 0.1), legs, size=0.12)
        box("TankFoot", (0.36, 0.36, 0.08), (fx, fy, 0.04), legs)
    # Cross bracing between the legs.
    for i in range(4):
        (ax, ay), (bx, by) = feet[i], feet[(i + 1) % 4]
        strut("TankBrace", (ax, ay, 0.2), (bx, by, 1.4), legs, size=0.04)
        strut("TankBrace", (bx, by, 0.2), (ax, ay, 1.4), legs, size=0.04)
    lx, ly = feet[0]
    for z in [0.35 * i for i in range(1, 8)]:
        strut("TankLadder", (lx + 0.15, ly - 0.15, z), (lx - 0.1, ly + 0.1, z), legs, size=0.025)


def hvac_unit():
    """A packaged rooftop unit behind the viewer's right shoulder: a louvered box with two fan
    guards on top, on a steel curb."""
    body = material("HVAC", (0.62, 0.63, 0.6), 0.5, metallic=0.2)
    dark = material("HVACDark", (0.05, 0.05, 0.05), 0.6)
    x, y = 2.4, -2.35
    w, d, h = 1.7, 1.25, 1.1
    box("HVACCurb", (w + 0.1, d + 0.1, 0.2), (x, y, 0.1), steel("HVACCurb", (0.2, 0.2, 0.21), 0.6))
    box("HVAC", (w, d, h), (x, y, 0.2 + h / 2), body, bevel=0.01)
    for i in range(9):
        box("Louver", (0.01, d - 0.2, 0.03), (x - w / 2 - 0.005, y, 0.4 + i * 0.08), dark)
    for fx in (-0.42, 0.42):
        cylinder("FanWell", 0.33, (x + fx, y, 0.2 + h - 0.02), (x + fx, y, 0.2 + h + 0.01), dark, segments=32)
        torus("FanGuard", 0.33, 0.012, (x + fx, y, 0.2 + h + 0.02), steel("FanGuard", (0.3, 0.3, 0.3), 0.5))
        for a in range(0, 180, 30):
            r = math.radians(a)
            strut("FanWire", (x + fx - 0.32 * math.cos(r), y - 0.32 * math.sin(r), 0.2 + h + 0.02), (x + fx + 0.32 * math.cos(r), y + 0.32 * math.sin(r), 0.2 + h + 0.02), steel("FanGuard"), size=0.006)
    # Refrigerant lines down into the roof.
    copper = material("Copper", (0.6, 0.32, 0.18), 0.35, metallic=1.0)
    cylinder("LineSet", 0.015, (x - w / 2, y + 0.4, 0.6), (x - w / 2 - 0.25, y + 0.4, 0.6), copper)
    cylinder("LineSet", 0.015, (x - w / 2 - 0.25, y + 0.4, 0.6), (x - w / 2 - 0.25, y + 0.4, 0.02), copper)


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


def antenna_mast():
    """A mast on a non-penetrating roof mount behind the seat: a steel frame weighed down with
    concrete blocks, a galvanized pipe up from it, a Yagi at the top pointing out over the city, and
    the Solar Node clamped on an arm halfway up, its panel to the sunset."""
    galvanized = steel("Galvanized", (0.6, 0.61, 0.6), 0.45)
    frame = steel("MountFrame", (0.25, 0.26, 0.27), 0.55)
    block = stucco("Block", (0.45, 0.44, 0.42))
    pad = material("RoofPad", (0.06, 0.06, 0.06), 0.9)
    x, y = 0.55, -2.75
    box("MountPad", (1.3, 1.3, 0.02), (x, y, 0.01), pad)
    for dx, dy in ((-0.55, 0), (0.55, 0), (0, -0.55), (0, 0.55)):
        strut("MountArm", (x, y, 0.06), (x + dx, y + dy, 0.06), frame, size=0.05)
        box("MountBlock", (0.4, 0.2, 0.2) if dy == 0 else (0.2, 0.4, 0.2), (x + dx, y + dy, 0.13), block, bevel=0.01)
    for dx, dy in ((-0.4, 0), (0.4, 0), (0, -0.4), (0, 0.4)):
        strut("MountStay", (x + dx, y + dy, 0.08), (x, y, 1.0), frame, size=0.03)
    top = 4.2
    cylinder("Mast", 0.03, (x, y, 0.04), (x, y, top + 0.15), galvanized, segments=20)
    # The Yagi: a boom out over the back railing, with its elements across it, horizontally polarized
    # for a long link over the city.
    boom_out = Vector((0, -1, 0))
    boom_a = Vector((x, y + 0.6, top))
    boom_b = Vector((x, y - 1.3, top))
    cylinder("YagiBoom", 0.014, boom_a, boom_b, galvanized, segments=12)
    box("YagiClamp", (0.08, 0.08, 0.1), (x, y, top), frame)
    for i, length in enumerate((0.36, 0.33, 0.31, 0.3, 0.29, 0.28, 0.27)):
        point = boom_a.lerp(boom_b, (i + 0.5) / 7)
        half = Vector((length / 2, 0, 0))
        cylinder("YagiElement", 0.005, point - half, point + half, galvanized, segments=8)
    box("YagiFeed", (0.06, 0.04, 0.05), boom_a.lerp(boom_b, 0.5 / 7) + Vector((0, 0, -0.03)), material("Feed", (0.05, 0.05, 0.05), 0.5))
    cylinder("Coax", 0.006, boom_a.lerp(boom_b, 0.5 / 7) + Vector((0, 0, -0.05)), (x + 0.03, y, top - 0.1), material("Coax", (0.02, 0.02, 0.02), 0.6), segments=8)
    cylinder("CoaxDown", 0.006, (x + 0.035, y, top - 0.1), (x + 0.035, y, 0.05), material("Coax"), segments=8)
    # The Solar Node on an arm, its panel turned toward the seat and tipped back to the sky.
    yaw = math.atan2(-y, -x)
    facing = Vector((math.cos(yaw), math.sin(yaw), 0))
    height = 2.15
    mount = Vector((x, y, height)) + facing * 0.12
    cylinder("NodeClamp", 0.045, (x, y, height - 0.05), (x, y, height + 0.05), frame)
    cylinder("NodeArm", 0.012, (x, y, height), mount - facing * 0.008, frame)
    place_solar_node(mount, yaw, math.radians(25))
    del boom_out


def folding_chair():
    """A folding chair beside the seat on the left, turned a little toward the bulkhead."""
    metal = steel("ChairSteel", (0.08, 0.08, 0.085), 0.45)
    slats = wood("ChairSlats", (0.3, 0.19, 0.1), scale=(6, 60, 6))
    x, y, yaw = -1.35, 0.35, math.radians(-25)
    turn = Matrix.Rotation(yaw, 4, "Z").to_3x3()
    def at(px, py, pz):
        return Vector((x, y, 0)) + turn @ Vector((px, py, pz))
    w = 0.44
    for side in (-1, 1):
        sx = side * w / 2
        strut("ChairFront", at(sx, 0.22, 0), at(sx, -0.2, 0.92), metal, size=0.022)
        strut("ChairBack", at(sx, -0.22, 0), at(sx, 0.12, 0.45), metal, size=0.022)
    for i in range(4):
        box("ChairSeatSlat", (w, 0.08, 0.018), at(0, -0.1 + i * 0.09, 0.46), slats, rotation=(0, 0, yaw), bevel=0.003)
    for i in range(3):
        box("ChairBackSlat", (w, 0.018, 0.07), at(0, -0.19 + 0.02 * i, 0.7 + i * 0.09), slats, rotation=(math.radians(-14), 0, yaw), bevel=0.003)
    strut("ChairBar", at(-w / 2, 0.15, 0.08), at(w / 2, 0.15, 0.08), metal, size=0.016)


# MARK: - String lights

def catenary(a, b, sag, count):
    a, b = Vector(a), Vector(b)
    points = []
    for i in range(count + 1):
        t = i / count
        p = a.lerp(b, t)
        p.z -= sag * 4 * t * (1 - t)
        points.append(p)
    return points


def string_lights():
    """Festoon lights strung from the bulkhead's top corners to two poles at the back corners and
    across over the seat, with a warm bulb every 40 cm."""
    wire = material("Festoon", (0.02, 0.02, 0.02), 0.6)
    pole = steel("LightPole", (0.1, 0.1, 0.1), 0.5)
    bulb = glowing("Bulb", (1, 0.72, 0.4), 18)
    rng = random.Random(3)
    back = [(-HALF + 0.2, -HALF + 0.2), (HALF - 0.2, -HALF + 0.2)]
    for bx, by in back:
        cylinder("LightPole", 0.03, (bx, by, CURB), (bx, by, 2.75), pole, segments=12)
        box("PoleBase", (0.3, 0.3, 0.12), (bx, by, CURB + 0.06), pole)
    front = [(-WIDE / 2 + 0.05, FRONT + 0.05, TALL - 0.05), (WIDE / 2 - 0.05, FRONT + 0.05, TALL - 0.05)]
    runs = [
        (front[0], (back[0][0], back[0][1], 2.7), 0.35),
        (front[1], (back[1][0], back[1][1], 2.7), 0.35),
        ((back[0][0], back[0][1], 2.7), (back[1][0], back[1][1], 2.7), 0.3),
        (front[0], (back[1][0], back[1][1], 2.7), 0.45),
        (front[1], (back[0][0], back[0][1], 2.7), 0.45),
    ]
    lit = 0
    for a, b, sag in runs:
        length = (Vector(b) - Vector(a)).length
        points = catenary(a, b, sag, max(8, int(length / 0.4)))
        for p, q in zip(points, points[1:]):
            cylinder("FestoonWire", 0.004, p, q, wire, segments=6)
        for p in points[1:-1]:
            cylinder("BulbSocket", 0.012, p, p - Vector((0, 0, 0.05)), wire, segments=8)
            glow = sphere("Bulb", 0.03, p - Vector((0, 0, 0.08)), bulb, segments=10)
            glow.visible_shadow = False
            # A few of the bulbs light the deck; all of them would cost the render for no more light.
            lit += 1
            if lit % 4 == 0:
                point_light("BulbLight", p - Vector((0, 0, 0.1)), 6 + rng.uniform(-1, 1), (1, 0.7, 0.4), radius=0.03)


def build():
    build_deck()
    build_bulkhead()
    build_boards()
    sandwich_board()
    water_tower()
    hvac_unit()
    antenna_mast()
    folding_chair()
    string_lights()
    # On the bulkhead's plain front wall, 2.7 m out: 2.4 m wide, as on the castle tower's frame.
    screen_anchor((0, FRONT - 0.03, EYE_HEIGHT + 0.34), (math.pi / 2, 0, 0), width=2.4)


# The clear sunset the fire lookout's skies are painted from, at the same turn, so the app's skies
# (fire_lookout_puresky behind the real city, city_view.py's painted one otherwise) and its terrain
# shading fit this image. The sky isn't painted: the image is a cutout past the deck and the glass.
render_room(build, "kloppenheim_06_puresky_4k.hdr", hdri_rotation=5.5, hdri_strength=0.8, cutout=True)

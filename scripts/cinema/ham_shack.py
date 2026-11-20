#
#  ham_shack.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/29/26.
#
#  An amateur radio shack for the visionOS cinema: a small wood-paneled room built on
#  room_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P ham_shack.py -- --out out/ham_shack.png --width 4096 --samples 160
#
#  The front wall is plain plaster for the app's screen. The operating desk runs along the left
#  wall: an HF radio, its power supply, an SWR meter, a desk mic, a Morse key, the log and a few
#  Meshtastic radios, and a computer running FT8, with the whiteboard the app draws the team roster
#  on above its front end, a shelf with two stacks of radios and the UTC and local clocks above the
#  back, and a band plan chart past the end of the desk. A window on the right wall looks out on
#  the dusk forest and the antenna tower, with the door in front of it and the print the app draws
#  the latest trace route on between the door and the corner. Chirpy's poster hangs to the left of
#  the screen and the portrait whiteboard net control logs the check-ins on to its right, which the
#  app draws the nodes' status messages over; the Meshtastic banner and a board of QSL cards are on
#  the back wall, over a soldering bench. A rack with a repeater and an amplifier stands under the
#  band plan, a cabinet with an old tube receiver sits under the window, and radios crowd the desk.

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ham_books import COVERS, SPINES  # noqa: E402
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

# MARK: - Room (meters)

# 5.4 m square, with the viewer in the middle, so every wall is 2.7 m away.
HALF = 2.7
CEILING = 2.45
WALL = 0.1
# The window in the right wall: from y, to y, sill, top.
WINDOW = (-1.75, 0.25, 0.85, 2.15)
# The door in the right wall, between the window and the print: center y, width, height.
DOOR = (0.95, 0.84, 2.03)
DESK_TOP = 0.74
DESK_DEPTH = 0.75
# The desk runs along the left wall between these.
DESK_Y = (-0.55, 2.6)

DEVICE_MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels")


def facing_in(side):
    """The rotation that turns a plane() to lie on a side wall, its face toward the room and its
    image upright. `side` is -1 for the left wall, +1 for the right."""
    return (math.pi / 2, 0, -side * math.pi / 2)


# MARK: - Materials

def paneling(name, along):
    """Knotty pine paneling: vertical boards about 15 cm wide with a dark groove between them, each
    a slightly different tone, with grain running up them. `along` is the world axis the wall runs
    along, "X" or "Y"."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.55
    geometry = nodes.new("ShaderNodeNewGeometry")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], split.inputs[0])
    uv = nodes.new("ShaderNodeCombineXYZ")
    links.new(split.outputs[along], uv.inputs["X"])
    links.new(split.outputs["Z"], uv.inputs["Y"])
    brick = nodes.new("ShaderNodeTexBrick")
    brick.offset = 0
    brick.squash = 1
    brick.inputs["Scale"].default_value = 1
    brick.inputs["Brick Width"].default_value = 0.15
    brick.inputs["Row Height"].default_value = 3
    brick.inputs["Mortar Size"].default_value = 0.004
    brick.inputs["Bias"].default_value = 0
    brick.inputs["Color1"].default_value = (0.42, 0.24, 0.11, 1)
    brick.inputs["Color2"].default_value = (0.55, 0.33, 0.16, 1)
    brick.inputs["Mortar"].default_value = (0.08, 0.045, 0.02, 1)
    links.new(uv.outputs[0], brick.inputs["Vector"])
    # Grain: noise stretched up the boards, darkening them in streaks, and a few knots.
    stretch = nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (60, 3, 1)
    links.new(uv.outputs[0], stretch.inputs["Vector"])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 1.5
    grain.inputs["Detail"].default_value = 6
    links.new(stretch.outputs[0], grain.inputs["Vector"])
    knots = nodes.new("ShaderNodeTexVoronoi")
    knots.inputs["Scale"].default_value = 3.5
    links.new(uv.outputs[0], knots.inputs["Vector"])
    knot_mask = nodes.new("ShaderNodeMapRange")
    knot_mask.inputs["From Min"].default_value = 0.03
    knot_mask.inputs["From Max"].default_value = 0.0
    links.new(knots.outputs["Distance"], knot_mask.inputs["Value"])
    streak = nodes.new("ShaderNodeMix")
    streak.data_type = "RGBA"
    streak.blend_type = "MULTIPLY"
    streak.inputs["Factor"].default_value = 0.35
    links.new(brick.outputs["Color"], streak.inputs["A"])
    links.new(grain.outputs["Color"], streak.inputs["B"])
    knot = nodes.new("ShaderNodeMix")
    knot.data_type = "RGBA"
    links.new(knot_mask.outputs[0], knot.inputs["Factor"])
    links.new(streak.outputs["Result"], knot.inputs["A"])
    knot.inputs["B"].default_value = (0.12, 0.06, 0.025, 1)
    links.new(knot.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def carpet():
    """Plain, dark, short-pile carpet: nearly flat, since the floor near the viewer has no depth in
    the image."""
    mat = material("Carpet", (0.045, 0.075, 0.065), 0.95)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 400
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], nodes["Principled BSDF"].inputs["Normal"])
    return mat


def glowing(name, path, strength):
    """An image that gives its own light, like a lit display or a backlit meter."""
    mat = image_material(name, path, 0.3)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    links.new(nodes["Image Texture"].outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


# MARK: - The room

def build_room():
    plaster = material("Plaster", (0.78, 0.74, 0.66), 0.85)
    side_panels = paneling("PanelingSide", "Y")
    back_panels = paneling("PanelingBack", "X")
    ceiling = material("Ceiling", (0.85, 0.84, 0.8), 0.9)
    trim = material("Trim", (0.3, 0.17, 0.08), 0.5)
    outer = HALF + WALL

    box("Floor", (2 * outer, 2 * outer, 0.1), (0, 0, -0.05), carpet())
    box("Ceiling", (2 * outer, 2 * outer, 0.1), (0, 0, CEILING + 0.05), ceiling)
    box("FrontWall", (2 * outer, WALL, CEILING), (0, HALF + WALL / 2, CEILING / 2), plaster)
    box("BackWall", (2 * outer, WALL, CEILING), (0, -HALF - WALL / 2, CEILING / 2), back_panels)
    box("LeftWall", (WALL, 2 * HALF, CEILING), (-HALF - WALL / 2, 0, CEILING / 2), side_panels)
    # The right wall, around the window opening.
    y0, y1, sill, top = WINDOW
    x = HALF + WALL / 2
    box("RightWallFront", (WALL, HALF - y1, CEILING), (x, (y1 + HALF) / 2, CEILING / 2), side_panels)
    box("RightWallBack", (WALL, y0 + HALF, CEILING), (x, (y0 - HALF) / 2, CEILING / 2), side_panels)
    box("RightWallSill", (WALL, y1 - y0, sill), (x, (y0 + y1) / 2, sill / 2), side_panels)
    box("RightWallHead", (WALL, y1 - y0, CEILING - top), (x, (y0 + y1) / 2, (top + CEILING) / 2), side_panels)

    # Baseboards and crown molding on all four walls, so the corners read.
    for name, size, location in (
        ("Front", (2 * HALF, 0.02, 0.1), (0, HALF - 0.01, 0.05)),
        ("Back", (2 * HALF, 0.02, 0.1), (0, -HALF + 0.01, 0.05)),
        ("Left", (0.02, 2 * HALF, 0.1), (-HALF + 0.01, 0, 0.05)),
        ("Right", (0.02, 2 * HALF, 0.1), (HALF - 0.01, 0, 0.05)),
    ):
        box("Baseboard" + name, size, location, trim)
        box("Crown" + name, (size[0], size[1], 0.06), (location[0], location[1], CEILING - 0.03), trim)

    build_window(trim)
    build_door(trim)


def build_window(trim):
    """A double-hung window with a wide sill, open on the dusk outside."""
    y0, y1, sill, top = WINDOW
    face = HALF - 0.01
    width = y1 - y0
    cy = (y0 + y1) / 2
    for name, size, location in (
        ("Sill", (0.16, width + 0.12, 0.035), (face - 0.05, cy, sill - 0.01)),
        ("Head", (0.03, width + 0.12, 0.08), (face, cy, top + 0.04)),
        ("JambFront", (0.03, 0.06, top - sill), (face, y1 + 0.03, (sill + top) / 2)),
        ("JambBack", (0.03, 0.06, top - sill), (face, y0 - 0.03, (sill + top) / 2)),
        ("Apron", (0.02, width + 0.06, 0.08), (face, cy, sill - 0.07)),
    ):
        box("Window" + name, size, location, trim)
    sash = material("Sash", (0.92, 0.9, 0.85), 0.5)
    mid = (sill + top) / 2
    box("SashRail", (0.04, width, 0.045), (HALF + 0.03, cy, mid), sash)
    for z in (sill + 0.02, top - 0.02):
        box("SashEdge", (0.04, width, 0.04), (HALF + 0.03, cy, z), sash)
    for y in (y0 + 0.02, y1 - 0.02):
        box("SashStile", (0.04, 0.04, top - sill), (HALF + 0.03, y, mid), sash)
    # Glass, barely there: it catches a little of the room.
    glass = bpy.data.materials.new("Glass")
    glass.use_nodes = True
    bsdf = glass.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1
    bsdf.inputs["Roughness"].default_value = 0.02
    bsdf.inputs["IOR"].default_value = 1.05
    plane("WindowGlass", width, top - sill, (HALF + 0.05, cy, mid), facing_in(1), glass)
    # Evening light coming in, unseen itself.
    area = bpy.data.lights.new("WindowLight", "AREA")
    area.shape = "RECTANGLE"
    area.size, area.size_y = width, top - sill
    area.energy = 12
    area.color = (0.95, 0.82, 0.65)
    area.spread = math.radians(80)
    obj = bpy.data.objects.new("WindowLight", area)
    obj.location = (HALF - 0.2, cy, mid)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((-1, 0, -0.35)).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)


def build_door(trim):
    """A closed six-panel door in the right wall, painted, with a brass knob and its casing."""
    y, width, height = DOOR
    paint = material("DoorPaint", (0.88, 0.86, 0.8), 0.45)
    face = HALF - 0.025
    box("Door", (0.04, width, height), (face, y, height / 2), paint, bevel=0.003)
    # Six raised panels: two small at the top, two tall in the middle, two at the bottom.
    rails = [(1.62, 1.92), (0.86, 1.5), (0.14, 0.74)]
    for z0, z1 in rails:
        for side in (-1, 1):
            panel_y = y + side * width / 4
            box("DoorPanel", (0.012, width / 2 - 0.12, z1 - z0), (face - 0.022, panel_y, (z0 + z1) / 2), paint, bevel=0.004)
    brass = material("Brass", (0.78, 0.6, 0.3), 0.25, metallic=1.0)
    knob_y = y - width / 2 + 0.07
    cylinder("DoorRose", 0.03, (face - 0.02, knob_y, 0.95), (face - 0.03, knob_y, 0.95), brass, segments=24)
    cylinder("DoorNeck", 0.01, (face - 0.03, knob_y, 0.95), (face - 0.07, knob_y, 0.95), brass, segments=12)
    sphere("DoorKnob", 0.028, (face - 0.085, knob_y, 0.95), brass, segments=20)
    # Casing around it, standing just off the paneling.
    casing = 0.07
    for side in (-1, 1):
        box("DoorCasing", (0.02, casing, height + casing), (HALF - 0.01, y + side * (width / 2 + casing / 2), (height + casing) / 2), trim)
    box("DoorHead", (0.02, width + 2 * casing, casing), (HALF - 0.01, y, height + casing / 2), trim)


def build_tower():
    """A lattice antenna tower out past the window, with a triband beam and a vertical on top,
    standing against the sunset sky."""
    steel = material("TowerSteel", (0.25, 0.26, 0.28), 0.5, metallic=0.8)
    base = Vector((14.0, -4.5, -0.4))
    height = 4.6
    spread = 0.3
    legs = [base + Vector((spread * math.cos(a), spread * math.sin(a), 0)) for a in (0, 2.094, 4.189)]
    for leg in legs:
        cylinder("TowerLeg", 0.04, leg, leg + Vector((0, 0, height)), steel, segments=8)
    for step in range(int(height / 0.5)):
        z0, z1 = step * 0.5, step * 0.5 + 0.5
        for a, b in zip(legs, legs[1:] + legs[:1]):
            cylinder("TowerBrace", 0.016, a + Vector((0, 0, z0)), b + Vector((0, 0, z1)), steel, segments=6)
            cylinder("TowerRung", 0.016, a + Vector((0, 0, z1)), b + Vector((0, 0, z1)), steel, segments=6)
    top = base + Vector((0, 0, height))
    mast_top = top + Vector((0, 0, 1.6))
    cylinder("TowerMast", 0.03, top, mast_top, steel, segments=10)
    # The beam: a boom with three elements across it, turned a little off the view.
    boom_dir = Vector((math.cos(0.5), math.sin(0.5), 0))
    across = Vector((-boom_dir.y, boom_dir.x, 0))
    beam_z = top + Vector((0, 0, 1.0))
    cylinder("Boom", 0.05, beam_z - boom_dir * 2.2, beam_z + boom_dir * 2.2, steel, segments=8)
    for offset, half_length in ((-2.1, 4.0), (0.0, 3.7), (2.1, 3.4)):
        center = beam_z + boom_dir * offset
        cylinder("Element", 0.03, center - across * half_length, center + across * half_length, steel, segments=6)
    # A vertical for VHF and the mesh, and a red beacon at the very top.
    cylinder("Vertical", 0.025, mast_top, mast_top + Vector((0, 0, 2.2)), steel, segments=6)
    sphere("Beacon", 0.1, mast_top + Vector((0, 0, 2.25)), material("Beacon", (1, 0.05, 0.02), emission=(1, 0.08, 0.03), strength=40), segments=12)
    # The coax run down the tower toward the shack.
    cable = material("Coax", (0.02, 0.02, 0.02), 0.6)
    cylinder("TowerCoax", 0.012, legs[1] + Vector((0, 0, height)), legs[1] + Vector((0, 0, 0.3)), cable, segments=6)


# MARK: - The operating desk

def build_desk():
    wood = material("DeskTop", (0.3, 0.19, 0.1), 0.45)
    frame = material("DeskFrame", (0.08, 0.08, 0.09), 0.5, metallic=0.5)
    y0, y1 = DESK_Y
    x = -HALF + DESK_DEPTH / 2
    length = y1 - y0
    box("Desk", (DESK_DEPTH, length, 0.04), (x, (y0 + y1) / 2, DESK_TOP - 0.02), wood, bevel=0.006)
    # A modesty panel and two pedestal ends, closed, so nothing shows under the desk.
    box("DeskBack", (0.02, length - 0.04, DESK_TOP - 0.1), (-HALF + 0.03, (y0 + y1) / 2, (DESK_TOP - 0.1) / 2 + 0.06), frame)
    for y in (y0 + 0.03, y1 - 0.03):
        box("DeskEnd", (DESK_DEPTH - 0.04, 0.04, DESK_TOP - 0.04), (x, y, (DESK_TOP - 0.04) / 2), wood)


def radio(name, center, size, display, knob_mat, body_mat):
    """A radio standing on the desk with its front panel toward the room (+X): a box, a display
    and a big tuning knob. Returns its front face's x."""
    cx, cy, cz = center
    depth, width, height = size
    box(name, size, (cx, cy, cz + height / 2), body_mat, bevel=0.004)
    front = cx + depth / 2
    if display:
        plane(name + "Display", width * 0.42, height * 0.36, (front + 0.001, cy - width * 0.1, cz + height * 0.62), facing_in(-1), display)
    cylinder(name + "Knob", height * 0.28, (front, cy + width * 0.28, cz + height * 0.45), (front + 0.03, cy + width * 0.28, cz + height * 0.45), knob_mat, segments=32)
    for i in range(4):
        y = cy - width * 0.36 + i * width * 0.08
        cylinder(name + "SmallKnob", 0.008, (front, y, cz + height * 0.2), (front + 0.015, y, cz + height * 0.2), knob_mat, segments=12)
    return front


def stacked(front, y, bottom, radios, knob_mat):
    """Stacks radios one on another with their fronts at `front`, from `bottom` up, and returns the
    height of the top of the stack. Each is (name, (depth, width, height), display, body)."""
    for name, size, display, body in radios:
        radio(name, (front - size[0] / 2, y, bottom), size, display, knob_mat, body)
        bottom += size[2]
    return bottom


def meter(name, center, size, face, body_mat):
    cx, cy, cz = center
    depth, width, height = size
    box(name, size, (cx, cy, cz + height / 2), body_mat, bevel=0.003)
    plane(name + "Face", width * 0.8, height * 0.6, (cx + depth / 2 + 0.001, cy, cz + height * 0.6), facing_in(-1), face)


def furnish_desk():
    body = material("RadioBody", (0.06, 0.06, 0.065), 0.4, metallic=0.3)
    gray = material("SupplyBody", (0.55, 0.56, 0.58), 0.45, metallic=0.4)
    knob = material("Knob", (0.02, 0.02, 0.02), 0.35, metallic=0.2)
    chrome = material("Chrome", (0.8, 0.8, 0.82), 0.15, metallic=1.0)
    display = glowing("RadioDisplay", os.path.join(CACHE, "radio_display.png"), 3.0)
    back = -HALF + 0.22

    # The HF radio in the middle of the desk, its power supply behind and to the left, and the SWR
    # meter on the right.
    radio("HFRadio", (back, 0.5, DESK_TOP), (0.33, 0.38, 0.13), display, knob, body)
    meter("PowerSupply", (back, -0.1, DESK_TOP), (0.3, 0.28, 0.14), glowing("VoltsFace", os.path.join(CACHE, "meter_volts.png"), 0.6), gray)
    swr_bottom = desk_radios(back, body, knob)
    meter("SWRMeter", (back + 0.02, 0.93, swr_bottom), (0.18, 0.2, 0.11), glowing("SWRFace", os.path.join(CACHE, "meter_swr.png"), 0.6), body)
    computer(back + 0.04, 1.5, knob)

    # A desk mic on its stand in front of the radio.
    mx, my = back + 0.36, 0.55
    cylinder("MicBase", 0.07, (mx, my, DESK_TOP), (mx, my, DESK_TOP + 0.025), body, segments=32)
    cylinder("MicStem", 0.008, (mx, my, DESK_TOP + 0.025), (mx, my, DESK_TOP + 0.22), chrome)
    capsule = cylinder("MicHead", 0.03, (mx - 0.01, my, DESK_TOP + 0.22), (mx + 0.07, my, DESK_TOP + 0.26), chrome, segments=24)
    capsule.name = "MicHead"
    box("MicPTT", (0.03, 0.02, 0.012), (mx + 0.02, my, DESK_TOP + 0.03), material("PTT", (0.6, 0.05, 0.05), 0.4))

    # A straight key on the right of the radio.
    kx, ky = back + 0.4, 0.95
    box("KeyBase", (0.11, 0.06, 0.018), (kx, ky, DESK_TOP + 0.009), body, bevel=0.003)
    cylinder("KeyLever", 0.005, (kx - 0.04, ky, DESK_TOP + 0.03), (kx + 0.05, ky, DESK_TOP + 0.03), chrome, segments=10)
    cylinder("KeyKnob", 0.016, (kx + 0.05, ky, DESK_TOP + 0.03), (kx + 0.05, ky, DESK_TOP + 0.045), knob, segments=20)

    # The log, open, with a pen.
    paper = material("LogPaper", (0.93, 0.92, 0.88), 0.8)
    lx, ly = back + 0.3, 2.1
    for side in (-1, 1):
        plane("LogPage", 0.21, 0.15, (lx, ly + side * 0.106, DESK_TOP + 0.004 + 0.002 * (side + 1)), (0, 0, math.pi / 2 + side * 0.03), paper)
    box("LogCover", (0.22, 0.44, 0.004), (lx, ly, DESK_TOP + 0.002), material("LogCover", (0.12, 0.22, 0.12), 0.6))
    cylinder("Pen", 0.004, (lx - 0.06, ly + 0.15, DESK_TOP + 0.01), (lx + 0.06, ly + 0.2, DESK_TOP + 0.01), material("Pen", (0.05, 0.1, 0.4), 0.4), segments=8)

    headphones((-HALF + 0.24, -0.33, 1.2), (back + 0.17, 0.5 - 0.12, DESK_TOP + 0.06), body, chrome)

    # Meshtastic radios, the app's own models at real size: a T-Deck lying in front of the log,
    # a T1000-E beside the key and a WisMesh Pocket by the mic.
    place_model("t-deck.usdz", (back + 0.5, 1.88), 1.4, flat=True)
    place_model("tracker-t1000-e.usdz", (back + 0.48, 1.15), 0.4, flat=True)
    place_model("rak_wismesh_pocket.usdz", (back + 0.4, 0.15), -0.3, flat=False)

    # Coax and power leads from the back of the radios down behind the desk and up to the
    # feedthrough panel high on the wall.
    cable = material("Cable", (0.02, 0.02, 0.02), 0.6)
    panel_y = -0.25
    box("Feedthrough", (0.02, 0.22, 0.14), (-HALF + 0.01, panel_y, 2.12), gray)
    for i, y in enumerate((0.0, 0.5, 0.93)):
        start = (-HALF + 0.06, y, DESK_TOP + 0.05)
        turn = (-HALF + 0.04, panel_y + 0.06 * (i - 1), DESK_TOP + 0.05)
        cylinder("CoaxRun", 0.006, start, turn, cable, segments=6)
        cylinder("CoaxUp", 0.006, turn, (-HALF + 0.03, panel_y + 0.06 * (i - 1), 2.07), cable, segments=6)

    desk_lamp(back + 0.05, 2.42)


def desk_radios(back, body, knob):
    """The rest of the radios crowding the desk around the mic and the headphones: a 6 meter rig and
    a 220 mobile stacked on the HF radio, two mobiles on the power supply, a 20 meter rig under the
    SWR meter, a QRP rig against the wall under the headphones, a portable at the front corner and
    a handheld by the mic. Returns the height the SWR meter stands at."""
    def display(name):
        return glowing("Display" + name, os.path.join(CACHE, f"radio_display_{name}.png"), 2.0)

    stacked(back + 0.165, 0.5, DESK_TOP + 0.13, [("SixMeter", (0.28, 0.34, 0.075), display("6m"), body), ("Mobile220", (0.2, 0.17, 0.05), display("220"), body)], knob)
    stacked(back + 0.15, -0.1, DESK_TOP + 0.14, [("Mobile440", (0.2, 0.17, 0.055), display("440rpt"), body), ("Mobile2mDesk", (0.2, 0.17, 0.05), display("2m"), body)], knob)
    swr_bottom = stacked(back + 0.12, 0.93, DESK_TOP, [("TwentyMeter", (0.28, 0.24, 0.09), display("20m"), body)], knob)
    # Pushed against the wall so the headphones' cable drops past its front.
    radio("QRPRig", (-HALF + 0.1, -0.42, DESK_TOP), (0.18, 0.2, 0.07), display("30m"), knob, body)
    radio("Portable", (back + 0.33, -0.4, DESK_TOP), (0.14, 0.2, 0.06), display("15m"), knob, material("PortableBody", (0.16, 0.17, 0.18), 0.45, metallic=0.3))
    handheld(back + 0.38, 0.77, material("DeskHandheld", (0.07, 0.07, 0.075), 0.45), knob)
    return swr_bottom


def handheld(x, y, body, knob):
    """A handheld radio standing on its own, facing the room, its rubber duck antenna up."""
    box("Handheld", (0.035, 0.058, 0.115), (x, y, DESK_TOP + 0.0575), body, bevel=0.006)
    plane("HandheldDisplay", 0.04, 0.022, (x + 0.0181, y, DESK_TOP + 0.085), facing_in(-1),
          glowing("HandheldDisplay", os.path.join(CACHE, "radio_display_2m.png"), 2.0))
    cylinder("HandheldKnob", 0.008, (x - 0.005, y + 0.015, DESK_TOP + 0.115), (x - 0.005, y + 0.015, DESK_TOP + 0.13), knob, segments=12)
    cylinder("HandheldDuck", 0.006, (x - 0.005, y - 0.015, DESK_TOP + 0.115), (x - 0.005, y - 0.015, DESK_TOP + 0.27), material("Duck", (0.03, 0.03, 0.03), 0.6), segments=10)


def tube(name, points, radius, mat):
    """A smooth round tube along `points`, for cables and bent metal."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    spline.order_u = min(4, len(points))
    spline.use_endpoint_u = True
    spline.resolution_u = 12
    curve.materials.append(mat)
    return link(bpy.data.objects.new(name, curve))


def headphones(hook, jack, plastic, metal):
    """Closed-back headphones hung by their headband from a hook under the shelf, the cups hanging
    either side and turned toward each other, their cable dropping to the radio's front jack.
    `hook` is where the hook meets the shelf's underside."""
    hx, hy, hz = hook
    leather = material("Leatherette", (0.03, 0.03, 0.03), 0.55)
    # The hook: down from the shelf and curled out toward the room.
    tube("HeadphoneHook", [(hx, hy, hz), (hx, hy, hz - 0.03), (hx + 0.01, hy, hz - 0.045), (hx + 0.03, hy, hz - 0.04)], 0.003, metal)
    # The headband hangs on the hook: an arc across, padded under its crown.
    radius = 0.088
    cz = hz - 0.045 - radius - 0.004
    band = [(hx + 0.004, hy + radius * math.cos(a), cz + radius * math.sin(a)) for a in (math.radians(d) for d in range(10, 171, 16))]
    tube("Headband", band, 0.007, metal)
    pad = [(hx + 0.004, hy + (radius - 0.012) * math.cos(a), cz + (radius - 0.012) * math.sin(a)) for a in (math.radians(d) for d in range(40, 141, 20))]
    tube("HeadbandPad", pad, 0.012, leather)
    for side in (-1, 1):
        end = Vector((hx + 0.004, hy + side * radius * math.cos(math.radians(10)), cz + radius * math.sin(math.radians(10))))
        # A slider down from each end of the band to the yoke.
        slider_bottom = end - Vector((0, 0, 0.045))
        tube("Slider", [end, slider_bottom], 0.004, metal)
        # The yoke: a fork either side of the cup.
        cup_center = slider_bottom - Vector((0, side * 0.006, 0.05))
        tube("Yoke", [(cup_center.x - 0.05, cup_center.y, cup_center.z), (slider_bottom.x - 0.05, slider_bottom.y, slider_bottom.z + 0.004),
                      (slider_bottom.x + 0.05, slider_bottom.y, slider_bottom.z + 0.004), (cup_center.x + 0.05, cup_center.y, cup_center.z)], 0.0035, metal)
        # The cup, and its cushion on the side facing the other cup.
        outer = cup_center + Vector((0, side * 0.012, 0))
        inner = cup_center - Vector((0, side * 0.018, 0))
        cup = cylinder("EarCup", 0.046, outer, inner, plastic, segments=40)
        bevel = cup.modifiers.new("Bevel", "BEVEL")
        bevel.width = 0.008
        bevel.segments = 4
        torus("EarCushion", 0.036, 0.013, (inner.x, inner.y - side * 0.004, inner.z), leather, rotation=(math.pi / 2, 0, 0))
        cylinder("CupBadge", 0.018, outer, outer + Vector((0, side * 0.002, 0)), metal, segments=24)
    # The cable from the bottom of the left cup down behind the radio and around to its jack.
    start = Vector((hx + 0.004, hy - radius * math.cos(math.radians(10)), cz - 0.1))
    tube("HeadphoneCable", [start, start - Vector((0, 0, 0.05)), (start.x + 0.04, start.y + 0.05, DESK_TOP + 0.03), (jack[0] - 0.08, jack[1] - 0.12, DESK_TOP + 0.006), (jack[0] + 0.03, jack[1] - 0.04, DESK_TOP + 0.01), jack], 0.0025, plastic)


def computer(x, y, knob_mat):
    """A computer screen on a stand at the back of the desk, running FT8, and its keyboard."""
    case = material("MonitorCase", (0.03, 0.03, 0.035), 0.4)
    width, height = 0.56, 0.34
    z = DESK_TOP + 0.11 + height / 2
    cylinder("MonitorFoot", 0.1, (x, y, DESK_TOP), (x, y, DESK_TOP + 0.012), case, segments=32)
    box("MonitorNeck", (0.03, 0.06, 0.12), (x, y, DESK_TOP + 0.07), case)
    box("Monitor", (0.03, width + 0.02, height + 0.02), (x + 0.02, y, z), case, bevel=0.004)
    plane("MonitorScreen", width, height, (x + 0.036, y, z), facing_in(-1), glowing("Waterfall", os.path.join(CACHE, "waterfall.png"), 1.6))
    box("Keyboard", (0.15, 0.44, 0.02), (x + 0.33, y, DESK_TOP + 0.01), case, bevel=0.003)
    box("Keys", (0.12, 0.41, 0.006), (x + 0.33, y, DESK_TOP + 0.022), material("Keys", (0.12, 0.12, 0.13), 0.6))
    box("Mouse", (0.1, 0.06, 0.03), (x + 0.33, y - 0.32, DESK_TOP + 0.015), case, bevel=0.012)


def place_model(file_name, at, yaw, flat, top=DESK_TOP):
    """Puts one of the app's device models on a surface at real size, the desk unless `top` says
    another height. `flat` lays it on its back, screen up, the way a handheld rests on a desk;
    otherwise it stands facing +X. `yaw` turns it about the vertical, in radians."""
    path = os.path.abspath(os.path.join(DEVICE_MODELS, file_name))
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [obj for obj in bpy.data.objects if obj not in before]
    root = next(obj for obj in new if obj.parent is None)
    # The importer leaves the model's front facing -Y. Lay it screen up, or stand it facing the
    # room (+X), then turn it.
    tip = Matrix.Rotation(-math.pi / 2, 4, "X") if flat else Matrix.Rotation(math.pi / 2, 4, "Z")
    root.matrix_world = Matrix.Rotation(yaw, 4, "Z") @ tip @ root.matrix_world
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(corner) for obj in new if obj.type == "MESH" for corner in obj.bound_box]
    low = min(c.z for c in corners)
    cx = (min(c.x for c in corners) + max(c.x for c in corners)) / 2
    cy = (min(c.y for c in corners) + max(c.y for c in corners)) / 2
    root.matrix_world = Matrix.Translation((at[0] - cx, at[1] - cy, top - low)) @ root.matrix_world


def desk_lamp(x, y):
    """An arm lamp clamped to the back of the desk at its front end, reaching out over the log."""
    arm = material("LampArm", (0.1, 0.1, 0.11), 0.4, metallic=0.7)
    base = Vector((x, y, DESK_TOP))
    elbow = base + Vector((0.12, -0.05, 0.42))
    head = elbow + Vector((0.22, -0.2, -0.05))
    cylinder("LampBase", 0.05, base, base + Vector((0, 0, 0.03)), arm, segments=24)
    cylinder("LampLower", 0.008, base, elbow, arm, segments=8)
    cylinder("LampUpper", 0.008, elbow, head, arm, segments=8)

    def shade(bm):
        bmesh.ops.create_cone(bm, cap_ends=False, segments=32, radius1=0.075, radius2=0.025, depth=0.12)
    lamp = mesh_object("LampShade", shade, arm, head - Vector((0, 0, 0.05)))
    smooth(lamp)
    bulb = sphere("LampBulb", 0.025, head - Vector((0, 0, 0.09)), material("DeskBulb", (1, 0.85, 0.6), emission=(1, 0.8, 0.55), strength=25), segments=16)
    bulb.visible_diffuse = False
    bulb.visible_shadow = False
    spot = bpy.data.lights.new("DeskLamp", "SPOT")
    spot.energy = 25
    spot.color = (1, 0.82, 0.6)
    spot.spot_size = math.radians(70)
    spot.spot_blend = 0.6
    spot.shadow_soft_size = 0.03
    obj = bpy.data.objects.new("DeskLamp", spot)
    obj.location = head - Vector((0, 0, 0.1))
    link(obj)


def build_shelf():
    """A shelf over the back half of the desk with a VHF/UHF radio, and the two clocks above it."""
    wood = material("Shelf", (0.3, 0.19, 0.1), 0.45)
    body = material("ShelfRadioBody", (0.06, 0.06, 0.065), 0.4, metallic=0.3)
    knob = material("ShelfKnob", (0.02, 0.02, 0.02), 0.35)
    z = 1.22
    y0, y1 = -0.5, 0.95
    box("Shelf", (0.3, y1 - y0, 0.025), (-HALF + 0.15, (y0 + y1) / 2, z), wood)
    for y in (y0 + 0.1, y1 - 0.1):
        box("ShelfBracket", (0.2, 0.02, 0.15), (-HALF + 0.1, y, z - 0.09), wood)
    top = z + 0.0125
    gray = material("ShelfGray", (0.5, 0.51, 0.53), 0.45, metallic=0.4)

    def display(name):
        return glowing("Display" + name, os.path.join(CACHE, f"radio_display_{name}.png"), 2.0)

    # On the left, a 2 m mobile on a dual-band rig; on the right, a second HF rig with an antenna
    # tuner and a power meter on it. Each stack's front stands at the shelf's front edge.
    front = -HALF + 0.29
    stack = [("DualBand", (0.24, 0.3, 0.1), display("70cm"), body), ("Mobile2m", (0.18, 0.16, 0.05), display("2m"), body)]
    stacked(front, -0.18, top, stack, knob)
    stack = [("HFRadio2", (0.27, 0.34, 0.11), display("40m"), body), ("Tuner", (0.22, 0.3, 0.08), None, gray)]
    height = stacked(front, 0.5, top, stack, knob)
    meter("PowerMeter", (front - 0.06, 0.5, height), (0.12, 0.16, 0.08), glowing("PowerFace", os.path.join(CACHE, "meter_power.png"), 0.6), body)
    # Ten to eight in the evening, local, seven hours behind UTC.
    wall_clock("utc", (-0.05, 1.78), 2, 50, 24)
    wall_clock("local", (0.5, 1.78), 19, 50, 24)
    # The band plan chart on the wall behind the end of the desk.
    box("BandPlanFrame", (0.02, 1.26, 0.86), (-HALF + 0.01, -1.65, 1.5), material("BandPlanFrame", (0.03, 0.03, 0.032), 0.5))
    plane("BandPlan", 1.2, 0.8, (-HALF + 0.021, -1.65, 1.5), facing_in(-1), image_material("BandPlan", os.path.join(CACHE, "band_plan.png"), 0.7))


def wall_clock(label, at, hours, minutes, seconds):
    """A round wall clock on the left wall: a black case with a rounded bezel, the dial from
    make_textures.py, and its hands standing off the dial at `hours`:`minutes`:`seconds`."""
    y, z = at
    radius = 0.15
    case = material("ClockCase", (0.04, 0.04, 0.045), 0.35)
    cylinder("ClockCase", radius + 0.014, (-HALF, y, z), (-HALF + 0.04, y, z), case, segments=64)
    torus("ClockBezel", radius + 0.006, 0.011, (-HALF + 0.04, y, z), case, rotation=(0, math.pi / 2, 0))

    def dial(bm):
        bm.loops.layers.uv.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=64, radius=radius, calc_uvs=True)
    face = mesh_object("ClockDial", dial, image_material("Clock" + label, os.path.join(CACHE, f"clock_{label}.png"), 0.4),
                       (-HALF + 0.041, y, z), facing_in(-1))
    face.name = "ClockDial"

    # The hands, in the dial's plane: 12 is up and 3 is toward +Y, the viewer's right.
    def hand(name, angle, length, width, tail, depth, mat):
        direction = Vector((0, math.sin(angle), math.cos(angle)))
        center = Vector((-HALF + depth, y, z)) + direction * (length - tail) / 2
        obj = box(name, (0.003, width, length + tail), center, mat)
        obj.rotation_euler = (-angle, 0, 0)
        return obj
    black = material("ClockHand", (0.02, 0.02, 0.025), 0.4)
    red = material("ClockSecond", (0.75, 0.08, 0.06), 0.4)
    hand_angle = math.radians(((hours % 12) + minutes / 60) * 30)
    hand("HourHand", hand_angle, radius * 0.5, 0.012, 0.02, 0.046, black)
    hand("MinuteHand", math.radians((minutes + seconds / 60) * 6), radius * 0.78, 0.008, 0.025, 0.05, black)
    hand("SecondHand", math.radians(seconds * 6), radius * 0.86, 0.003, 0.04, 0.054, red)
    cylinder("ClockCap", 0.008, (-HALF + 0.045, y, z), (-HALF + 0.058, y, z), red, segments=20)


# MARK: - The soldering bench

# A workbench along the back wall, under the banner and left of the bookcase: from x, to x.
BENCH_X = (-2.3, 0.85)
BENCH_TOP = 0.9
BENCH_DEPTH = 0.62


def on_bench(x, d):
    """A point on the bench top `d` meters out from the back wall."""
    return (x, -HALF + d)


def facing_room_from_back(x, d, z):
    """Where a front panel on the bench sits, and the rotation that turns a plane() to face the
    room from it: +Y, away from the back wall."""
    return (x, -HALF + d, z), (math.pi / 2, 0, math.pi)


def build_bench():
    """The bench itself: a butcher-block top on a steel frame, an anti-static mat, and a low shelf
    of parts bins under it."""
    top = material("BenchTop", (0.52, 0.36, 0.2), 0.5)
    steel = material("BenchFrame", (0.12, 0.13, 0.14), 0.45, metallic=0.7)
    x0, x1 = BENCH_X
    cx, width = (x0 + x1) / 2, x1 - x0
    cy = -HALF + BENCH_DEPTH / 2
    box("BenchTop", (width, BENCH_DEPTH, 0.04), (cx, cy, BENCH_TOP - 0.02), top, bevel=0.004)
    for x in (x0 + 0.04, x1 - 0.04):
        for y in (-HALF + 0.05, -HALF + BENCH_DEPTH - 0.05):
            box("BenchLeg", (0.045, 0.045, BENCH_TOP - 0.04), (x, y, (BENCH_TOP - 0.04) / 2), steel)
    box("BenchShelf", (width - 0.05, BENCH_DEPTH - 0.06, 0.025), (cx, cy, 0.2), top)
    box("BenchRail", (width - 0.05, 0.03, 0.05), (cx, -HALF + BENCH_DEPTH - 0.05, BENCH_TOP - 0.07), steel)
    # The mat over the middle of the bench, where the boards are worked on.
    box("BenchMat", (1.95, 0.5, 0.003), (-0.05, -HALF + 0.33, BENCH_TOP + 0.0015), material("BenchMat", (0.2, 0.3, 0.36), 0.9))
    # Stacking parts bins on the shelf, each a different color, and a coax spool at the end.
    colors = [(0.75, 0.15, 0.1), (0.1, 0.3, 0.65), (0.85, 0.65, 0.1), (0.15, 0.45, 0.2), (0.75, 0.15, 0.1), (0.1, 0.3, 0.65)]
    for i, color in enumerate(colors):
        x = x0 + 0.25 + i * 0.36
        bin_mat = material(f"Bin{i}", color, 0.5)
        box("Bin", (0.3, 0.4, 0.15), (x, -HALF + 0.28, 0.2125 + 0.075), bin_mat, bevel=0.01)
        if i % 2 == 0:
            box("Bin", (0.3, 0.4, 0.12), (x, -HALF + 0.28, 0.3625 + 0.06), material(f"BinTop{i}", colors[(i + 2) % len(colors)], 0.5), bevel=0.01)
    spool(x1 - 0.3, -HALF + 0.75, material("Spool", (0.55, 0.42, 0.28), 0.7), material("CoaxJacket", (0.02, 0.02, 0.02), 0.55))


def spool(x, y, flange_mat, coil_mat):
    """A wooden cable spool on the floor, on its side, wound with coax."""
    for side in (-1, 1):
        cylinder("SpoolFlange", 0.2, (x + side * 0.1, y, 0.2), (x + side * 0.12, y, 0.2), flange_mat, segments=40)
    cylinder("SpoolCoil", 0.15, (x - 0.1, y, 0.2), (x + 0.1, y, 0.2), coil_mat, segments=40)


def soldering_station(x, d, display, body, knob):
    """A temperature-controlled soldering station with its iron in a coil stand, a wet sponge and a
    brass tip cleaner beside it, and the iron's cord running back to the station."""
    width, depth, height = 0.16, 0.17, 0.1
    box("SolderStation", (width, depth, height), (x, -HALF + d, BENCH_TOP + height / 2), body, bevel=0.006)
    front = d + depth / 2
    location, rotation = facing_room_from_back(x - 0.02, front + 0.001, BENCH_TOP + 0.065)
    plane("SolderReadout", 0.08, 0.032, location, rotation, display)
    cylinder("SolderKnob", 0.018, (x + 0.05, -HALF + front, BENCH_TOP + 0.04), (x + 0.05, -HALF + front + 0.02, BENCH_TOP + 0.04), knob, segments=24)
    box("SolderSwitch", (0.02, 0.01, 0.014), (x - 0.05, -HALF + front + 0.004, BENCH_TOP + 0.025), material("SolderSwitch", (0.75, 0.1, 0.08), 0.4))
    # The stand to its right: a heavy base, a coil leaning toward the wall, the iron in it.
    steel = material("IronSteel", (0.6, 0.6, 0.62), 0.3, metallic=1.0)
    sx, sy = x + 0.17, -HALF + d + 0.06
    box("IronStandBase", (0.1, 0.13, 0.02), (sx, sy, BENCH_TOP + 0.01), body, bevel=0.004)
    box("Sponge", (0.05, 0.05, 0.012), (sx, sy + 0.035, BENCH_TOP + 0.026), material("Sponge", (0.85, 0.7, 0.15), 0.9))
    cylinder("BrassWool", 0.022, (sx + 0.03, sy - 0.035, BENCH_TOP + 0.02), (sx + 0.03, sy - 0.035, BENCH_TOP + 0.05), material("BrassWool", (0.8, 0.62, 0.3), 0.7, metallic=0.8), segments=20)
    base = Vector((sx - 0.02, sy - 0.02, BENCH_TOP + 0.02))
    axis = Vector((0, -0.6, 0.8)).normalized()
    side = Vector((1, 0, 0))
    up = axis.cross(side)
    coil = [base + axis * (0.11 * t / 60) + (side * math.cos(t * 0.6) + up * math.sin(t * 0.6)) * (0.016 + 0.008 * t / 60) for t in range(61)]
    tube("IronCoil", coil, 0.0015, steel)
    grip = material("IronGrip", (0.05, 0.05, 0.05), 0.6)
    handle_start = base + axis * 0.18
    cylinder("IronHandle", 0.011, handle_start, base + axis * 0.06, grip, segments=16)
    cylinder("IronShaft", 0.004, base + axis * 0.06, base + axis * 0.0, steel, segments=10)
    cord = material("IronCord", (0.08, 0.08, 0.09), 0.6)
    station_back = Vector((x + 0.04, -HALF + d - depth / 2 - 0.01, BENCH_TOP + 0.03))
    tube("IronCord", [handle_start, handle_start + Vector((0, -0.04, 0.02)), (sx + 0.02, -HALF + 0.06, BENCH_TOP + 0.03), station_back], 0.003, cord)


def hot_air_station(x, d, display, body, knob):
    """A hot air rework station, its handpiece resting in the cradle on its side."""
    width, depth, height = 0.2, 0.2, 0.12
    box("HotAir", (width, depth, height), (x, -HALF + d, BENCH_TOP + height / 2), body, bevel=0.006)
    front = d + depth / 2
    location, rotation = facing_room_from_back(x - 0.03, front + 0.001, BENCH_TOP + 0.08)
    plane("HotAirReadout", 0.09, 0.036, location, rotation, display)
    for i in range(2):
        kx = x + 0.04 + i * 0.045
        cylinder("HotAirKnob", 0.014, (kx, -HALF + front, BENCH_TOP + 0.035), (kx, -HALF + front + 0.018, BENCH_TOP + 0.035), knob, segments=20)
    cradle = Vector((x + width / 2 + 0.01, -HALF + d, BENCH_TOP + 0.09))
    box("HotAirCradle", (0.02, 0.06, 0.04), cradle - Vector((0, 0, 0.02)), body)
    cylinder("HotAirHandle", 0.018, cradle + Vector((0.01, -0.07, 0.0)), cradle + Vector((0.01, 0.07, 0.0)), material("HotAirGrip", (0.15, 0.15, 0.16), 0.5), segments=20)
    cylinder("HotAirNozzle", 0.008, cradle + Vector((0.01, 0.07, 0)), cradle + Vector((0.01, 0.11, 0)), material("Nozzle", (0.6, 0.6, 0.62), 0.3, metallic=1.0), segments=12)


def helping_hands(x, d, metal):
    """A third hand: a heavy base with two arms and alligator clips, holding a board up off the
    mat to be soldered."""
    base = Vector((x, -HALF + d, BENCH_TOP))
    cylinder("HandsBase", 0.05, base, base + Vector((0, 0, 0.022)), material("HandsBase", (0.08, 0.08, 0.09), 0.5, metallic=0.5), segments=32)
    stem_top = base + Vector((0, 0, 0.14))
    cylinder("HandsStem", 0.005, base, stem_top, metal, segments=10)
    clip = material("Clip", (0.75, 0.75, 0.77), 0.3, metallic=1.0)
    for side in (-1, 1):
        end = base + Vector((side * 0.07, 0.06, 0.1))
        tube("HandsArm", [stem_top, stem_top + Vector((side * 0.04, 0.02, 0.02)), end + Vector((0, -0.01, 0.03)), end], 0.004, metal)
        box("HandsClip", (0.008, 0.025, 0.008), end + Vector((0, 0.01, 0)), clip)
    return base + Vector((0, 0.07, 0.09))


def multimeter(x, d, display, probes):
    """A yellow-holstered multimeter lying on the bench, reading a board's 3.3 V rail, its red and
    black leads trailing over the mat."""
    body = material("MeterHolster", (0.9, 0.7, 0.1), 0.6)
    width, length, height = 0.09, 0.18, 0.04
    cy = -HALF + d
    box("Multimeter", (width, length, height), (x, cy, BENCH_TOP + height / 2), body, bevel=0.01)
    plane("MeterReadout", 0.065, 0.035, (x, cy + 0.045, BENCH_TOP + height + 0.0005), (0, 0, 0), display)
    cylinder("MeterDial", 0.025, (x, cy - 0.02, BENCH_TOP + height), (x, cy - 0.02, BENCH_TOP + height + 0.006), material("MeterDial", (0.1, 0.1, 0.1), 0.5), segments=24)
    for i, mat in enumerate(probes):
        jack = Vector((x - 0.02 + i * 0.04, cy - length / 2 + 0.02, BENCH_TOP + height))
        tip = Vector((x - 0.35 + i * 0.08, cy + 0.12 + i * 0.03, BENCH_TOP + 0.006))
        tube("MeterLead", [jack, jack + Vector((0, -0.04, 0.02)), (jack.x - 0.1, jack.y - 0.03, BENCH_TOP + 0.004), (tip.x + 0.08, tip.y - 0.02, BENCH_TOP + 0.004), tip], 0.002, mat)
        cylinder("ProbeHandle", 0.005, tip, tip + Vector((0.09, 0.02, 0)), mat, segments=10)


def oscilloscope(x, d, body, knob):
    """A benchtop oscilloscope, its screen on the left of the panel and its knobs on the right,
    with a probe lead out to the board in the third hand."""
    width, depth, height = 0.34, 0.15, 0.16
    cy = -HALF + d
    box("Scope", (width, depth, height), (x, cy, BENCH_TOP + height / 2), body, bevel=0.008)
    front = d + depth / 2
    location, rotation = facing_room_from_back(x - 0.06, front + 0.001, BENCH_TOP + height * 0.55)
    plane("ScopeScreen", 0.18, 0.112, location, rotation, glowing("ScopeScreen", os.path.join(CACHE, "scope_screen.png"), 1.6))
    for i in range(3):
        for j in range(2):
            kx, kz = x + 0.085 + i * 0.028, BENCH_TOP + 0.05 + j * 0.055
            cylinder("ScopeKnob", 0.009, (kx, -HALF + front, kz), (kx, -HALF + front + 0.012, kz), knob, segments=16)
    return Vector((x + 0.1, -HALF + front, BENCH_TOP + 0.02))


def bench_supply(x, d, body, knob):
    """A bench power supply with its volts and amps readouts and red and black posts."""
    width, depth, height = 0.16, 0.2, 0.12
    cy = -HALF + d
    box("BenchSupply", (width, depth, height), (x, cy, BENCH_TOP + height / 2), body, bevel=0.006)
    front = d + depth / 2
    for i, name in enumerate(("volts", "amps")):
        location, rotation = facing_room_from_back(x - 0.035, front + 0.001, BENCH_TOP + 0.09 - i * 0.035)
        plane("SupplyReadout", 0.06, 0.024, location, rotation, glowing(f"Supply{name}", os.path.join(CACHE, f"readout_{name}.png"), 2.0))
        cylinder("SupplyKnob", 0.012, (x + 0.045, -HALF + front, BENCH_TOP + 0.09 - i * 0.035), (x + 0.045, -HALF + front + 0.015, BENCH_TOP + 0.09 - i * 0.035), knob, segments=20)
    for i, color in enumerate(((0.8, 0.05, 0.04), (0.03, 0.03, 0.03))):
        cylinder("SupplyPost", 0.007, (x - 0.05 + i * 0.03, -HALF + front, BENCH_TOP + 0.025), (x - 0.05 + i * 0.03, -HALF + front + 0.015, BENCH_TOP + 0.025), material(f"Post{i}", color, 0.4), segments=12)


def solder_spool(x, d):
    """A spool of solder on its dispenser."""
    y = -HALF + d
    stand = material("SpoolStand", (0.1, 0.1, 0.11), 0.5, metallic=0.6)
    box("SpoolStandBase", (0.1, 0.07, 0.01), (x, y, BENCH_TOP + 0.005), stand)
    for side in (-1, 1):
        box("SpoolStandArm", (0.005, 0.02, 0.06), (x + side * 0.04, y, BENCH_TOP + 0.04), stand)
    cylinder("SolderSpool", 0.03, (x - 0.035, y, BENCH_TOP + 0.05), (x + 0.035, y, BENCH_TOP + 0.05), material("Solder", (0.7, 0.7, 0.72), 0.35, metallic=0.9), segments=32)
    for side in (-1, 1):
        cylinder("SpoolSide", 0.034, (x + side * 0.036, y, BENCH_TOP + 0.05), (x + side * 0.032, y, BENCH_TOP + 0.05), material("SpoolSide", (0.15, 0.15, 0.8), 0.5), segments=32)
    tube("SolderWire", [(x, y + 0.02, BENCH_TOP + 0.08), (x, y + 0.08, BENCH_TOP + 0.03), (x - 0.03, y + 0.14, BENCH_TOP + 0.003), (x - 0.08, y + 0.16, BENCH_TOP + 0.003)], 0.0008,
         material("SolderWire", (0.7, 0.7, 0.72), 0.35, metallic=0.9))


def fume_extractor(x, d, body):
    """A small fume extractor fan box, its carbon filter toward the work."""
    cy = -HALF + d
    box("FumeBox", (0.18, 0.08, 0.18), (x, cy, BENCH_TOP + 0.09), body, bevel=0.006)
    box("FumeFilter", (0.15, 0.004, 0.15), (x, cy + 0.041, BENCH_TOP + 0.09), material("FumeFilter", (0.03, 0.03, 0.03), 0.95))
    for i in range(5):
        box("FumeGrille", (0.15, 0.006, 0.004), (x, cy + 0.045, BENCH_TOP + 0.03 + i * 0.03), body)


def magnifier_lamp(x, d, arm_mat):
    """An arm magnifier with a ring light, clamped to the back edge of the bench and reaching out
    over the work."""
    clamp = Vector((x, -HALF + 0.04, BENCH_TOP))
    box("MagClamp", (0.05, 0.06, 0.05), clamp + Vector((0, 0, 0.025)), arm_mat)
    elbow = clamp + Vector((0.05, 0.05, 0.45))
    head = Vector((x + 0.22, -HALF + d, BENCH_TOP + 0.3))
    cylinder("MagLower", 0.008, clamp + Vector((0, 0, 0.05)), elbow, arm_mat, segments=10)
    cylinder("MagUpper", 0.008, elbow, head + Vector((0, -0.09, 0.03)), arm_mat, segments=10)
    tilt = (math.radians(25), 0, 0)
    torus("MagRing", 0.085, 0.018, head, material("MagRing", (0.85, 0.86, 0.88), 0.4), rotation=tilt)
    ring = torus("MagLight", 0.085, 0.006, head - Vector((0, 0, 0.012)), material("MagLED", (1, 0.98, 0.94), emission=(1, 0.97, 0.92), strength=8), rotation=tilt)
    ring.visible_shadow = False
    glass = bpy.data.materials.new("MagLens")
    glass.use_nodes = True
    bsdf = glass.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1
    bsdf.inputs["Roughness"].default_value = 0.02
    bsdf.inputs["IOR"].default_value = 1.5

    def lens(bm):
        bmesh.ops.create_circle(bm, cap_ends=True, segments=48, radius=0.072)
    mesh_object("MagLens", lens, glass, head, tilt)
    spot = bpy.data.lights.new("MagLight", "SPOT")
    spot.energy = 14
    spot.color = (1, 0.97, 0.92)
    spot.spot_size = math.radians(80)
    spot.spot_blend = 0.8
    spot.shadow_soft_size = 0.08
    obj = bpy.data.objects.new("MagLight", spot)
    obj.location = head - Vector((0, 0, 0.03))
    link(obj)


def parts_cabinet(x, d):
    """A small-parts cabinet of clear drawers, some with resistors, connectors and screws showing."""
    frame = material("CabinetFrame", (0.82, 0.8, 0.76), 0.5)
    width, depth, height = 0.36, 0.16, 0.42
    cy = -HALF + d
    box("PartsCabinet", (width, depth, height), (x, cy, BENCH_TOP + height / 2), frame)
    drawer = material("Drawer", (0.75, 0.82, 0.88), 0.25)
    contents = [material(f"Parts{i}", c, 0.6) for i, c in enumerate(((0.8, 0.5, 0.2), (0.15, 0.15, 0.15), (0.2, 0.4, 0.8), (0.75, 0.75, 0.75), (0.8, 0.15, 0.1)))]
    cols, rows = 4, 7
    for r in range(rows):
        for c in range(cols):
            dx = x - width / 2 + (c + 0.5) * width / cols
            dz = BENCH_TOP + 0.02 + (r + 0.5) * (height - 0.03) / rows
            box("DrawerFront", (width / cols - 0.01, 0.01, (height - 0.03) / rows - 0.008), (dx, cy + depth / 2 + 0.004, dz), drawer)
            if (r * cols + c) % 3 != 1:
                box("DrawerParts", (width / cols - 0.03, 0.006, 0.012), (dx, cy + depth / 2 + 0.006, dz - 0.008), contents[(r * 7 + c * 3) % len(contents)])


def pegboard():
    """A pegboard on the wall over the left end of the bench, hung with pliers, cutters, a crimper,
    screwdrivers, wire on a dowel and coiled jumpers."""
    x0, x1, z0, z1 = -2.25, -1.0, 1.0, 1.8
    face = -HALF + 0.025
    board = material("Pegboard", (0.5, 0.38, 0.25), 0.8)
    box("Pegboard", (x1 - x0, 0.012, z1 - z0), ((x0 + x1) / 2, face - 0.006, (z0 + z1) / 2), board)
    steel = material("PegSteel", (0.6, 0.6, 0.62), 0.3, metallic=1.0)
    red = material("ToolRed", (0.75, 0.08, 0.06), 0.5)
    blue = material("ToolBlue", (0.1, 0.25, 0.7), 0.5)
    yellow = material("ToolYellow", (0.9, 0.7, 0.1), 0.5)
    black = material("ToolBlack", (0.04, 0.04, 0.04), 0.5)

    def peg(x, z):
        cylinder("Peg", 0.003, (x, face, z), (x, face + 0.05, z), steel, segments=8)

    # Pliers and cutters: two handles spread from a joint, the jaws up.
    for i, (x, grip) in enumerate(((-2.12, red), (-2.0, blue), (-1.88, yellow))):
        joint = Vector((x, face + 0.02, 1.62))
        peg(x, 1.68)
        box("ToolJaw", (0.012, 0.008, 0.05), joint + Vector((0, 0, 0.025)), steel)
        for side in (-1, 1):
            cylinder("ToolGrip", 0.007, joint, joint + Vector((side * 0.025, 0, -0.13)), grip, segments=10)
    # The crimper: big, with long red handles.
    joint = Vector((-1.72, face + 0.022, 1.6))
    peg(-1.72, 1.68)
    box("CrimperHead", (0.05, 0.012, 0.07), joint + Vector((0, 0, 0.03)), steel)
    for side in (-1, 1):
        cylinder("CrimperGrip", 0.009, joint, joint + Vector((side * 0.04, 0, -0.2)), red, segments=10)
    # Screwdrivers in a rack.
    box("DriverRack", (0.3, 0.05, 0.015), (-1.45, face + 0.025, 1.55), steel)
    for i, grip in enumerate((red, black, yellow, blue, red, black)):
        sx = -1.57 + i * 0.048
        cylinder("DriverGrip", 0.01, (sx, face + 0.025, 1.6), (sx, face + 0.025, 1.52), grip, segments=12)
        cylinder("DriverShaft", 0.0025, (sx, face + 0.025, 1.52), (sx, face + 0.025, 1.4 - 0.02 * (i % 3)), steel, segments=8)
    # Hookup wire on a dowel across the top right.
    cylinder("Dowel", 0.006, (-1.4, face + 0.03, 1.72), (-1.06, face + 0.03, 1.72), steel, segments=10)
    for i, color in enumerate(((0.75, 0.08, 0.06), (0.04, 0.04, 0.04), (0.9, 0.75, 0.1), (0.1, 0.45, 0.2), (0.1, 0.25, 0.7), (0.9, 0.9, 0.9))):
        wx = -1.37 + i * 0.054
        cylinder("WireSpool", 0.03, (wx - 0.02, face + 0.03, 1.72), (wx + 0.02, face + 0.03, 1.72), material(f"Wire{i}", color, 0.5), segments=24)
    # Coax jumpers and a USB cable coiled on hooks low down.
    for i, (x, mat) in enumerate(((-2.1, black), (-1.85, black), (-1.25, material("UsbCable", (0.85, 0.85, 0.85), 0.5)))):
        peg(x, 1.32)
        torus("Jumper", 0.075, 0.005, (x, face + 0.03, 1.25), mat, rotation=(math.pi / 2, 0, 0))


def build_soldering_bench():
    """The bench and everything on it: the soldering and hot air stations, a third hand holding a
    board, a multimeter, solder, a fume extractor, a magnifier, a parts cabinet, the pegboard of
    tools over it, and a spread of the app's bare boards on the mat being built into radios."""
    build_bench()
    body = material("StationBody", (0.15, 0.16, 0.18), 0.45)
    knob = material("StationKnob", (0.03, 0.03, 0.03), 0.4)
    metal = material("BenchMetal", (0.55, 0.55, 0.57), 0.3, metallic=1.0)
    soldering_station(-0.72, 0.15, glowing("IronReadout", os.path.join(CACHE, "readout_iron.png"), 2.0), body, knob)
    hot_air_station(-0.28, 0.14, glowing("AirReadout", os.path.join(CACHE, "readout_air.png"), 2.0), body, knob)
    held = helping_hands(0.12, 0.33, metal)
    probe = oscilloscope(0.12, 0.1, material("ScopeBody", (0.82, 0.82, 0.8), 0.45), knob)
    tube("ScopeProbe", [probe, probe + Vector((0, 0.05, 0.0)), (held.x + 0.06, held.y - 0.04, BENCH_TOP + 0.01), (held.x + 0.03, held.y, held.z + 0.01)], 0.0018,
         material("ProbeLead", (0.05, 0.05, 0.05), 0.5))
    bench_supply(0.47, 0.12, body, knob)
    multimeter(0.62, 0.3, glowing("MeterReadout", os.path.join(CACHE, "readout_meter.png"), 0.4),
               [material("LeadRed", (0.8, 0.05, 0.04), 0.5), material("LeadBlack", (0.03, 0.03, 0.03), 0.5)])
    solder_spool(0.74, 0.12)
    fume_extractor(-1.42, 0.12, body)
    magnifier_lamp(-1.15, 0.42, material("MagArm", (0.85, 0.86, 0.88), 0.4))
    parts_cabinet(-2.06, 0.12)
    pegboard()
    # A board held up in the third hand, and more laid out on the mat, in every stage of being
    # put together.
    place_model("heltec-v3.usdz", (held.x, held.y), 0.15, flat=True, top=held.z)
    mat_top = BENCH_TOP + 0.003
    for name, x, d, yaw in (
        ("heltec_v4.usdz", -0.92, 0.47, 0.35),
        ("rak4631.usdz", -0.66, 0.5, -0.2),
        ("wio-tracker-wm1110.usdz", -0.44, 0.42, 0.9),
        ("tbeam-s3-core.usdz", -0.2, 0.5, 1.45),
        ("tlora-t3s3-v1.usdz", -0.05, 0.36, -1.2),
        ("heltec-wireless-tracker.usdz", 0.1, 0.52, 0.12),
        ("heltec-mesh-node-t114.usdz", 0.3, 0.5, 0.25),
        ("seeed_xiao_nrf52_kit.usdz", 0.48, 0.48, -0.5),
        ("rak11310.usdz", 0.66, 0.42, -0.35),
        ("muzi_base.usdz", 0.7, 0.54, 0.4),
        ("rak3401.usdz", -1.12, 0.48, 1.3),
        ("heltec-t096.usdz", -1.38, 0.44, -0.3),
        ("seeed-xiao-s3.usdz", -1.65, 0.45, 0.2),
    ):
        place_model(name, on_bench(x, d), yaw, flat=True, top=mat_top if -1.02 < x < 0.93 else BENCH_TOP)
    # Light over the bench, so the boards read; unseen itself.
    light = bpy.data.lights.new("BenchLight", "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = 2.6, 0.3
    light.energy = 30
    light.color = (1, 0.9, 0.78)
    obj = bpy.data.objects.new("BenchLight", light)
    obj.location = (-0.7, -HALF + 0.45, 1.95)
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)


# MARK: - The rack, more radios and clutter

def build_rack():
    """A 19 inch rack under the band plan: a repeater, a big base station, a linear amplifier with
    its plate and grid meters, a power supply, and the repeater's duplexer cans on top."""
    frame = material("RackFrame", (0.05, 0.05, 0.055), 0.45, metallic=0.4)
    body = material("RackRadioBody", (0.08, 0.08, 0.085), 0.4, metallic=0.3)
    gray = material("RackGray", (0.55, 0.56, 0.58), 0.45, metallic=0.4)
    knob = material("RackKnob", (0.02, 0.02, 0.02), 0.35)
    y, width, depth, height = -1.65, 0.6, 0.55, 1.0
    x = -HALF + depth / 2
    front = -HALF + depth
    for side in (-1, 1):
        box("RackSide", (depth, 0.025, height), (x, y + side * (width / 2 - 0.0125), height / 2), frame)
        box("RackRail", (0.02, 0.03, height - 0.04), (front - 0.01, y + side * (width / 2 - 0.04), height / 2), material("RackRailMetal", (0.6, 0.6, 0.62), 0.35, metallic=1.0))
    box("RackTop", (depth, width, 0.025), (x, y, height - 0.0125), frame)
    box("RackBase", (depth, width, 0.06), (x, y, 0.03), frame)

    def display(name):
        return glowing("Display" + name, os.path.join(CACHE, f"radio_display_{name}.png"), 2.0)

    bottom = stacked(front - 0.005, y, 0.06, [("RackSupply", (0.45, 0.5, 0.13), None, gray)], knob)
    # The amplifier: a tall panel with its two meters and big tune and load knobs.
    amp_h = 0.2
    box("Amplifier", (0.45, 0.5, amp_h), (front - 0.005 - 0.225, y, bottom + amp_h / 2), body, bevel=0.004)
    for i, (label, offset) in enumerate((("plate", -0.12), ("grid", 0.0))):
        face = glowing(label.title() + "Face", os.path.join(CACHE, f"meter_{label}.png"), 0.6)
        plane("AmpMeter", 0.1, 0.07, (front - 0.004, y + offset, bottom + amp_h * 0.66), facing_in(-1), face)
    for i, offset in enumerate((0.12, 0.2)):
        cylinder("AmpKnob", 0.028, (front - 0.005, y + offset, bottom + amp_h * 0.35), (front + 0.025, y + offset, bottom + amp_h * 0.35), knob, segments=32)
    box("AmpSwitch", (0.01, 0.03, 0.02), (front, y - 0.18, bottom + amp_h * 0.3), material("AmpSwitch", (0.75, 0.1, 0.08), 0.4))
    bottom += amp_h
    bottom = stacked(front - 0.005, y, bottom, [("BaseStation", (0.42, 0.5, 0.15), display("80m"), body), ("Repeater", (0.4, 0.5, 0.09), display("repeater"), body)], knob)
    # Six duplexer cans standing on the repeater, joined by short jumpers.
    can = material("DuplexerCan", (0.75, 0.76, 0.78), 0.3, metallic=1.0)
    for i in range(6):
        cy = y - 0.2 + (i % 3) * 0.2
        cx = x - 0.1 + (i // 3) * 0.17
        cylinder("DuplexerCan", 0.055, (cx, cy, bottom), (cx, cy, bottom + 0.3 - 0.06), can, segments=32)
        cylinder("DuplexerTuner", 0.01, (cx, cy, bottom + 0.24), (cx, cy, bottom + 0.27), material("Tuner", (0.8, 0.62, 0.3), 0.3, metallic=1.0), segments=12)


def more_radios():
    """More of the app's radios round the room: cased ones on the shelf and the desk, and a solar
    node and a couple of trackers on the windowsill."""
    shelf_top = 1.22 + 0.0125
    shelf_x = -HALF + 0.15
    for name, y in (("thinknode_m1.usdz", 0.06), ("t-echo.usdz", 0.22), ("heltec-v3-case.usdz", 0.82), ("rak_wismesh_tag.usdz", -0.42)):
        place_model(name, (shelf_x, y), 0.0, flat=False, top=shelf_top)
    back = -HALF + 0.22
    place_model("seeed-sensecap-indicator.usdz", (back - 0.04, 1.14), 0.25, flat=False)
    place_model("rak-wismeshtap.usdz", (back - 0.08, 2.24), 0.3, flat=False)
    place_model("lilygo-tlora-pager.usdz", (back + 0.48, 2.36), 1.2, flat=True)
    place_model("t-watch-s3.usdz", (back + 0.45, 1.27), 0.5, flat=True)
    sill_top = WINDOW[2] - 0.01 + 0.0175
    sill_x = HALF - 0.06
    place_model("seeed_solar.usdz", (sill_x, -1.3), math.pi, flat=False, top=sill_top)
    place_model("wio_tracker_l1_case.usdz", (sill_x, -0.75), math.pi + 0.3, flat=False, top=sill_top)
    place_model("thinknode_m2.usdz", (sill_x, -0.45), math.pi - 0.25, flat=False, top=sill_top)


def window_cabinet():
    """A low cabinet under the window with the shack's oldest radio on it: a gray tube receiver
    with a lit slide-rule dial and its matching speaker, a mobile rig beside them, and a few of the
    app's cased radios in front of the glass."""
    wood = material("Cabinet", (0.36, 0.22, 0.12), 0.5)
    depth, height = 0.4, 0.66
    y0, y1 = -1.65, 0.15
    x = HALF - depth / 2
    box("WindowCabinet", (depth, y1 - y0, height), (x, (y0 + y1) / 2, height / 2), wood, bevel=0.004)
    for y in (-1.2, -0.3):
        box("CabinetDoorLine", (0.004, 0.006, height - 0.08), (HALF - depth - 0.001, y, height / 2), material("CabinetLine", (0.15, 0.09, 0.05), 0.6))
    top = height
    gray = material("BoatAnchor", (0.42, 0.44, 0.46), 0.5, metallic=0.3)
    knob = material("BoatKnob", (0.04, 0.04, 0.04), 0.35)
    # The receiver, facing the room (-X): a big gray box with its dial across the top of the panel.
    rx, ry, rd, rw, rh = HALF - 0.2, -1.25, 0.3, 0.46, 0.24
    box("Receiver", (rd, rw, rh), (rx, ry, top + rh / 2), gray, bevel=0.01)
    front = rx - rd / 2
    plane("ReceiverDial", rw * 0.8, rh * 0.3, (front - 0.001, ry, top + rh * 0.7), facing_in(1),
          glowing("SlideRule", os.path.join(CACHE, "slide_rule_dial.png"), 0.9))
    for i in range(5):
        ky = ry - rw * 0.36 + i * rw * 0.18
        size = 0.026 if i in (1, 3) else 0.016
        cylinder("ReceiverKnob", size, (front, ky, top + rh * 0.3), (front - 0.025, ky, top + rh * 0.3), knob, segments=24)
    # Its speaker, a smaller box with a round grille.
    sy = -0.85
    box("Speaker", (0.24, 0.26, 0.24), (HALF - 0.17, sy, top + 0.12), gray, bevel=0.01)
    cylinder("SpeakerGrille", 0.085, (HALF - 0.291, sy, top + 0.12), (HALF - 0.295, sy, top + 0.12), material("Grille", (0.08, 0.08, 0.08), 0.8), segments=40)
    # A mobile rig standing beside them, facing the room.
    body = material("CabinetRigBody", (0.06, 0.06, 0.065), 0.4, metallic=0.3)
    mobile = (HALF - 0.16, -0.5, top)
    box("MobileRig", (0.2, 0.17, 0.06), (mobile[0], mobile[1], top + 0.03), body, bevel=0.004)
    plane("MobileDisplay", 0.08, 0.025, (mobile[0] - 0.101, mobile[1], top + 0.035), facing_in(1),
          glowing("MobileDisplay", os.path.join(CACHE, "radio_display_10m.png"), 2.0))
    # Our radios along the front of the cabinet.
    for name, y, yaw in (("thinknode_m3.usdz", -0.22, math.pi + 0.2), ("tdeck_pro.usdz", -0.04, math.pi - 0.2), ("seeed_wio_tracker_l2.usdz", 0.08, math.pi)):
        place_model(name, (HALF - 0.3, y), yaw, flat=False, top=top)


def handhelds(x, y, top, yaw, body):
    """A row of handheld radios in a gang charger, their rubber duck antennas up."""
    charger = material("Charger", (0.06, 0.06, 0.065), 0.45)
    turn = Matrix.Rotation(yaw, 3, "Z")
    base = Vector((x, y, top))
    box("GangCharger", (0.09, 0.26, 0.03), base + Vector((0, 0, 0.015)), charger, rotation=(0, 0, yaw))
    duck = material("Duck", (0.03, 0.03, 0.03), 0.6)
    for i in range(3):
        c = base + turn @ Vector((0, -0.08 + i * 0.08, 0))
        box("Handheld", (0.035, 0.058, 0.11), c + Vector((0, 0, 0.03 + 0.055)), body, rotation=(0, 0, yaw), bevel=0.006)
        led = (0.1, 0.9, 0.2) if i != 1 else (0.95, 0.3, 0.05)
        box("ChargeLed", (0.006, 0.006, 0.004), c + turn @ Vector((0.046, 0, 0.022)), material(f"ChargeLed{i}", led, emission=led, strength=6), rotation=(0, 0, yaw))
        top_c = c + Vector((0, 0, 0.14))
        cylinder("DuckAntenna", 0.006, top_c + turn @ Vector((-0.008, 0.015, 0)), top_c + turn @ Vector((-0.008, 0.015, 0.14)), duck, segments=10)


def clutter():
    """Things that pile up in a shack: coax coiled on hooks by the window, boxes and a tripod mast
    with a handheld beam in the corner, a coffee mug on the desk and another on the bench, and
    handhelds charging on the desk."""
    black = material("ClutterCoax", (0.02, 0.02, 0.02), 0.55)
    gray = material("LMR", (0.3, 0.3, 0.32), 0.5)
    steel = material("ClutterSteel", (0.6, 0.6, 0.62), 0.3, metallic=1.0)
    face = HALF - 0.01
    for y, mat, radius in ((-2.45, black, 0.16), (-2.1, gray, 0.13)):
        cylinder("CoaxHook", 0.004, (face, y, 1.62), (face - 0.06, y, 1.62), steel, segments=8)
        for k in range(3):
            torus("CoaxCoil", radius - k * 0.006, 0.006, (face - 0.035, y, 1.62 - radius + 0.01), mat, rotation=(0, math.pi / 2, 0.05 * k))
    # Boxes stacked in the back right corner, past the bookcase.
    cardboard = material("Cardboard", (0.62, 0.46, 0.3), 0.85)
    box("ShipBox", (0.42, 0.36, 0.3), (2.45, -2.47, 0.15), cardboard)
    box("ShipBox", (0.34, 0.3, 0.22), (2.43, -2.45, 0.41), cardboard, rotation=(0, 0, 0.12))
    box("ShipTape", (0.42, 0.06, 0.002), (2.45, -2.47, 0.301), material("Tape", (0.75, 0.62, 0.42), 0.4))
    # A tripod mast leaning in the corner with a small handheld beam on top.
    foot = Vector((2.3, -2.15, 0))
    top = Vector((2.6, -2.58, 2.0))
    cylinder("Mast", 0.015, foot, top, material("MastAluminum", (0.75, 0.76, 0.78), 0.35, metallic=1.0), segments=12)
    boom_dir = Vector((-1, 0.15, 0)).normalized()
    boom_c = top - (top - foot).normalized() * 0.05
    cylinder("YagiBoom", 0.008, boom_c, boom_c + boom_dir * 0.4, steel, segments=8)
    for i, half in enumerate((0.18, 0.16, 0.14, 0.13)):
        c = boom_c + boom_dir * (0.05 + i * 0.11)
        cylinder("YagiElement", 0.003, c - Vector((0, 0, half)), c + Vector((0, 0, half)), steel, segments=6)
    # Coffee.
    mug_mat = material("Mug", (0.85, 0.83, 0.78), 0.4)
    coffee = material("Coffee", (0.12, 0.06, 0.02), 0.15)
    for name, at, base in (("DeskMug", (-HALF + 0.67, -0.18), DESK_TOP), ("BenchMug", (-1.82, -HALF + 0.3), BENCH_TOP)):
        cylinder(name, 0.04, (at[0], at[1], base), (at[0], at[1], base + 0.095), mug_mat, segments=32)
        cylinder(name + "Coffee", 0.036, (at[0], at[1], base + 0.08), (at[0], at[1], base + 0.0805), coffee, segments=32)
        torus(name + "Handle", 0.025, 0.006, (at[0] + 0.045, at[1], base + 0.05), mug_mat, rotation=(math.pi / 2, 0, 0))
    # Handhelds charging at the front end of the desk, by the lamp.
    handhelds(-HALF + 0.12, 2.0, DESK_TOP, 0.0, material("HandheldBody", (0.07, 0.07, 0.075), 0.45))


# MARK: - Boards and wall art

def board_light(name, location, target, width, energy):
    """An area light onto a board the app draws over, so the painted board is as bright as the
    panel. It can't be seen itself, in the image or on the board."""
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = width, 0.3
    light.energy = energy
    light.color = (1, 0.7, 0.45)
    light.spread = math.radians(70)
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector(target) - obj.location).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)


def build_boards():
    aluminum = material("BoardFrame", (0.7, 0.7, 0.72), 0.4, metallic=0.8)
    # The whiteboard over the front end of the desk, where the tent's is: the app draws the team
    # roster over it (the "teamStatus" anchor).
    width, height = 1.35, 0.9
    y, z = 1.9, 1.72
    board = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)
    box("WhiteboardFrame", (0.025, width + 0.06, height + 0.06), (-HALF + 0.0125, y, z), aluminum)
    surface = plane("Whiteboard", width, height, (-HALF + 0.026, y, z), facing_in(-1), board)
    anchor("teamStatus", surface, width, height)
    board_light("BoardLight", (-HALF + 0.9, y, 2.3), (-HALF, y, z + 0.05), width - 0.2, 3.0)

    # A portrait whiteboard on the front wall to the right of the screen, where net control logs
    # the check-ins: the app draws the nodes' status messages over it (the "nodeStatus" anchor).
    width, height = 0.8, 1.2
    x, z = 1.9, EYE_HEIGHT + 0.2
    box("CheckInFrame", (width + 0.06, 0.025, height + 0.06), (x, HALF - 0.0125, z), aluminum)
    surface = plane("CheckIn", width, height, (x, HALF - 0.026, z), (math.pi / 2, 0, 0), board)
    anchor("nodeStatus", surface, width, height)
    board_light("CheckInLight", (x, HALF - 0.9, 2.3), (x, HALF, z + 0.05), width - 0.2, 3.0)

    # The print on the right wall in front of the window: the app draws the latest trace route's
    # card over it (the "traceRoute" anchor).
    width, height = 1.1, 0.9
    y, z = 2.08, 1.4
    box("PrintFrame", (0.02, width + 0.05, height + 0.05), (HALF - 0.01, y, z), material("PrintFrame", (0.03, 0.03, 0.032), 0.5), bevel=0.003)
    surface = plane("Print", width, height, (HALF - 0.021, y, z), facing_in(1), material("PrintMat", (0.86, 0.85, 0.82), 0.85))
    anchor("traceRoute", surface, width, height)
    board_light("PrintLight", (HALF - 0.9, y, 2.3), (HALF, y, z + 0.05), width - 0.2, 3.0)


def build_back_wall():
    """The Meshtastic banner in the middle of the back wall and the QSL cards to its right, and
    Chirpy on the front wall, between the screen and the left corner."""
    face = -HALF + 0.012
    facing = (math.pi / 2, 0, math.pi)
    banner = image_material("Banner", os.path.join(CACHE, "banner.png"), 0.9)
    plane("Banner", 1.8, 0.9, (0, face, 1.55), facing, banner)
    poster = image_material("ChirpyPoster", os.path.join(CACHE, "chirpy_poster.png"), 0.7)
    box("PosterFrame", (0.54, 0.02, 0.74), (-2.0, HALF - 0.009, 1.45), material("PosterFrame", (0.03, 0.03, 0.032), 0.5))
    plane("Poster", 0.5, 0.7, (-2.0, HALF - 0.021, 1.45), (math.pi / 2, 0, 0), poster)
    cork_frame = material("CorkFrame", (0.3, 0.19, 0.1), 0.5)
    box("QSLFrame", (0.96, 0.02, 0.66), (1.65, face - 0.003, 1.45), cork_frame)
    plane("QSLCards", 0.9, 0.6, (1.65, face + 0.009, 1.45), facing, image_material("QSLWall", os.path.join(CACHE, "qsl_wall.png"), 0.8))
    # A low bookcase of ham books under the QSL cards.
    wood = material("Bookcase", (0.3, 0.19, 0.1), 0.45)
    bx, depth, width, height = 1.65, 0.3, 1.1, 0.8
    by = -HALF + depth / 2
    box("BookcaseTop", (width, depth, 0.025), (bx, by, height), wood)
    for x in (bx - width / 2 + 0.0125, bx + width / 2 - 0.0125):
        box("BookcaseSide", (0.025, depth, height), (x, by, height / 2), wood)
    box("BookcaseShelf", (width, depth, 0.02), (bx, by, height / 2), wood)
    box("BookcaseBase", (width, depth, 0.06), (bx, by, 0.03), wood)
    shelve_books(bx, by, width, depth, (0.06, height / 2 + 0.01), height + 0.0125)


def shelve_books(bx, by, width, depth, shelves, top):
    """Fills the bookcase with the made-up ham books from ham_books.py, their spines out, a bookend
    and a short flat stack beside them on each shelf, and stands a few face out on top, leaning on
    the wall, big enough to read from the seat."""
    steel = material("Bookend", (0.15, 0.15, 0.16), 0.4, metallic=0.9)
    plain = [material("PlainBook", c, 0.6) for c in ((0.75, 0.72, 0.62), (0.2, 0.25, 0.32))]
    half = (len(SPINES) + 1) // 2
    rows = [SPINES[half:], SPINES[:half]]
    first = [half, 0]
    front = by + depth / 2 - 0.02
    for row, z, start in zip(rows, shelves, first):
        x = bx - width / 2 + 0.035
        for i, (title, _, color, thickness, height) in enumerate(row):
            n = start + i
            book_depth = 0.17 + 0.02 * (n % 3)
            cloth = material(f"Book{n:02d}", tuple(c / 255 for c in color), 0.7)
            box(f"Book{n:02d}", (thickness, book_depth, height), (x + thickness / 2, front - book_depth / 2, z + height / 2), cloth, bevel=0.002)
            plane(f"Spine{n:02d}", thickness, height, (x + thickness / 2, front + 0.0012, z + height / 2), (math.pi / 2, 0, math.pi),
                  image_material(f"Spine{n:02d}", os.path.join(CACHE, f"spine_{n:02d}.png"), 0.7))
            x += thickness + 0.003
        # An L bookend holding the row up.
        box("BookendFoot", (0.08, 0.12, 0.003), (x + 0.04, front - 0.08, z + 0.0015), steel)
        box("BookendUpright", (0.003, 0.12, 0.16), (x + 0.0015, front - 0.08, z + 0.08), steel)
        # Two big books lying flat in whatever room is left past the bookend.
        room = bx + width / 2 - 0.03 - (x + 0.08)
        if room >= 0.2:
            stack_x = bx + width / 2 - 0.03 - room / 2
            for j, mat in enumerate(plain):
                box("FlatBook", (min(0.22, room - 0.02) - 0.02 * j, 0.2, 0.045), (stack_x, front - 0.11, z + 0.0225 + 0.045 * j), mat, bevel=0.002)

    # Three stood face out on top, leaning back against the wall.
    lean = math.radians(12)
    turn = Matrix.Rotation(lean, 3, "X")
    w, h, t = 0.22, 0.28, 0.03
    for i, (title, _, color, _, _) in enumerate(COVERS):
        foot = Vector((bx + (i - (len(COVERS) - 1) / 2) * 0.27, -HALF + 0.1, top))
        box(f"FaceOutBook{i}", (w, t, h), foot + turn @ Vector((0, -t / 2, h / 2)), material(f"FaceOut{i}", tuple(c / 255 for c in color), 0.7), rotation=(lean, 0, 0))
        plane(f"Cover{i}", w, h, foot + turn @ Vector((0, 0.0012, h / 2)), (math.pi / 2 - lean, 0, math.pi),
              image_material(f"Cover{i}", os.path.join(CACHE, f"cover_{i}.png"), 0.6))


def build_lights():
    """A flush ceiling light in the middle of the room, with its warm glow on the ceiling."""
    fixture = material("Fixture", (1, 0.95, 0.85), 0.3, emission=(1, 0.88, 0.7), strength=6)
    cylinder("CeilingFixture", 0.22, (0, 0, CEILING - 0.05), (0, 0, CEILING), fixture, segments=48)
    light = bpy.data.lights.new("Ceiling", "AREA")
    light.shape = "DISK"
    light.size = 0.4
    light.energy = 140
    light.color = (1, 0.85, 0.65)
    obj = bpy.data.objects.new("Ceiling", light)
    obj.location = (0, 0, CEILING - 0.06)
    obj.visible_camera = False
    link(obj)


def build():
    build_room()
    build_tower()
    build_desk()
    furnish_desk()
    build_shelf()
    build_boards()
    build_back_wall()
    build_soldering_bench()
    build_rack()
    more_radios()
    window_cabinet()
    clutter()
    build_lights()
    # On the plain front wall, its center a little above the eye, as in the tent.
    screen_anchor((0, HALF - 0.1, EYE_HEIGHT + 0.2), (math.pi / 2, 0, 0))


# The dusk forest, turned so the sunset is toward the window and the tower.
render_room(build, "sunset_forest_8k.hdr", hdri_rotation=200, hdri_strength=0.5)

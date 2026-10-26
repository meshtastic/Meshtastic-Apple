#
#  sar_tent.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  The search and rescue command tent for the visionOS cinema: the furnishings that go in the
#  shared tent from tent_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P sar_tent.py -- --out out/sar_tent.png --width 4096 --samples 160
#
#  On the left, the whiteboard the app draws the team roster on, then the comms and radio tables; the
#  map table on the back wall to the right, and a Solar Node on a tripod by the door, with the blank
#  print the app draws the latest trace route on beside it. Nothing else stands on the floor.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tent_base import (  # noqa: E402
    BACK_Y,
    CACHE,
    HALF_WIDTH,
    RIDGE_HEIGHT,
    WALL_HEIGHT,
    anchor,
    box,
    cylinder,
    facing_in,
    image_material,
    link,
    material,
    mesh_object,
    plane,
    render,
    sag,
    smooth,
    sphere,
    torus,
)


def folding_table(name, center, length, along_y, top_mat, leg_mat):
    cx, cy = center
    size = (0.76, length, 0.04) if along_y else (length, 0.76, 0.04)
    box(name, size, (cx, cy, 0.74), top_mat, bevel=0.01)
    hx, hy = size[0] / 2 - 0.06, size[1] / 2 - 0.06
    for dx in (-hx, hx):
        for dy in (-hy, hy):
            cylinder(name + "Leg", 0.015, (cx + dx, cy + dy, 0), (cx + dx, cy + dy, 0.72), leg_mat)


def furnish(layout):
    rng = random.Random(42)
    table_top = material("TableTop", (0.62, 0.61, 0.57), 0.5)
    steel = material("Steel", (0.15, 0.15, 0.16), 0.4, metallic=0.9)
    black_plastic = material("BlackPlastic", (0.02, 0.02, 0.02), 0.45)
    led_red = material("LEDRed", (1, 0, 0), emission=(1, 0.1, 0.05), strength=8)
    wall = HALF_WIDTH - 0.38

    # Comms table along the left wall, under the plaque. Short, and pushed back in its bay just clear
    # of the tent leg behind it, so its front end stays clear of the whiteboard's stand as seen from
    # the seat. Bare: the app puts its own radio models on it.
    comms_length = 1.6
    comms_y = -0.75 + comms_length / 2
    folding_table("CommsTable", (-wall, comms_y), comms_length, True, table_top, steel)
    # The logs that used to lie on it drew six numbers here. Still draw them, so the map pins
    # stay where they were.
    for _ in range(6):
        rng.random()

    # Radio table in the back corner on the left, under the window. Bare: the app puts its own
    # radio models on it.
    folding_table("RadioTable", (-wall, -1.8), 1.3, True, table_top, steel)

    # Map table along the back wall on the right, between the banner and the corner, so the front
    # stays clear for the screen and the right window stays open.
    map_x, map_y = 1.95, -wall + 0.1
    folding_table("MapTable", (map_x, map_y), 1.3, False, table_top, steel)
    topo = image_material("Topo", os.path.join(CACHE, "topo.png"), 0.8)
    plane("TopoMap", 0.6, 1.2, (map_x, map_y, 0.765), (0, 0, math.pi / 2), topo)
    for _ in range(9):
        pin = led_red if rng.random() < 0.6 else material("PinYellow", (0.95, 0.8, 0.1), 0.4)
        x, y = map_x + rng.uniform(-0.5, 0.5), map_y + rng.uniform(-0.26, 0.26)
        cylinder("PinShaft", 0.002, (x, y, 0.765), (x, y, 0.79), steel)
        sphere("PinHead", 0.007, (x, y, 0.795), pin, segments=8)
    box("Compass", (0.1, 0.06, 0.008), (map_x + 0.45, map_y - 0.25, 0.77), material("Compass", (0.8, 0.85, 0.9), 0.1))

    # A SenseCAP Solar Node on a tripod just past the door, far enough along that the tripod's legs
    # stay clear of the door jamb. A short mast stands up from the tripod's head and the node clamps
    # to it by the mount on its back, the way it goes on a pole.
    tripod_top = (wall + 0.05, 1.18, 1.35)
    for angle in (0, 2.1, 4.2):
        foot = (tripod_top[0] + 0.3 * math.cos(angle), tripod_top[1] + 0.3 * math.sin(angle), 0)
        cylinder("TripodLeg", 0.01, foot, tripod_top, steel)
    solar_node(tripod_top, steel, black_plastic)

    # Whiteboard on the left wall in the front bay, on clear canvas. Left blank: the app draws the
    # live team roster over it (the "teamStatus" anchor). The front bay is narrower than the back
    # one, so the board is sized to fit between its two tent legs. It stands on two legs under the
    # frame, the way a mobile whiteboard does, so nothing crosses the board or crowds the tent legs
    # at either end of the bay. Its top sits well under the eave.
    board = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)
    board_x, board_y, board_z = -HALF_WIDTH + 0.1, 2.0, 1.17
    board_w, board_h = 1.35, 0.9
    whiteboard = plane("Whiteboard", board_w, board_h, (board_x + 0.02, board_y, board_z), facing_in(-1), board)
    anchor("teamStatus", whiteboard, board_w, board_h)
    box("WhiteboardFrame", (0.03, board_w + 0.06, board_h + 0.06), (board_x, board_y, board_z), material("Frame", (0.7, 0.7, 0.72), 0.4, metallic=0.8))
    frame_bottom = board_z - board_h / 2 - 0.03
    for y in (board_y - board_w / 2 + 0.1, board_y + board_w / 2 - 0.1):
        cylinder("EaselLeg", 0.014, (board_x + 0.03, y, 0.02), (board_x + 0.03, y, frame_bottom), steel)
        cylinder("EaselFoot", 0.014, (board_x - 0.02, y, 0.02), (board_x + 0.3, y, 0.02), steel)

    # A light on the board, from up by the eave, so the painted board is as bright as the panel
    # the app draws over it. It can't be seen itself, in the image or on the board.
    board_light("BoardLight", (board_x + 0.9, board_y, 2.02), (board_x, board_y, board_z + 0.05), board_w - 0.2, 3.3)

    map_lamp(map_x, map_y - 0.06, steel, black_plastic)
    trace_route_print(steel)


def board_light(name, location, target, width, energy):
    """An area light from up by the eave onto a board the app draws over, so the painted board is
    as bright as the panel. It can't be seen itself, in the image or on the board."""
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = width, 0.3
    light.energy = energy
    light.color = (1, 0.55, 0.24)
    light.spread = math.radians(70)
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector(target) - obj.location).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)


def trace_route_print(hook_mat):
    """A blank print in a thin dark frame on the right wall's front bay, between the Solar Node and
    the front corner, hung from the eave on two cords. The app draws the latest trace route's share
    card over it (the "traceRoute" anchor). Landscape, a little wider than the card's usual shape,
    so a taller route still fits on the mat."""
    width, height = 1.1, 0.9
    border, depth = 0.025, 0.02
    y, z = 2.1, 1.3
    # Rigid, so it stands off the canvas by the most the canvas bows in across it.
    back = HALF_WIDTH - max(sag(y + dy) for dy in (-width / 2, 0, width / 2)) - 0.006
    box("PrintFrame", (depth, width + 2 * border, height + 2 * border), (back - depth / 2, y, z), material("PrintFrame", (0.03, 0.03, 0.032), 0.5), bevel=0.003)
    surface = plane("Print", width, height, (back - depth - 0.001, y, z), facing_in(1), material("PrintMat", (0.86, 0.85, 0.82), 0.85))
    anchor("traceRoute", surface, width, height)
    top = z + height / 2 + border
    eave_x, eave_z = HALF_WIDTH - 0.05, WALL_HEIGHT - 0.04
    cord = material("PrintCord", (0.08, 0.08, 0.08), 0.8)
    for dy in (-width / 2 + 0.12, width / 2 - 0.12):
        cylinder("PrintCord", 0.003, (back - depth / 2, y + dy, top), (eave_x - 0.01, y + dy, eave_z - 0.03), cord, segments=6)
        torus("PrintHook", 0.03, 0.003, (eave_x, y + dy, eave_z), hook_mat, rotation=(math.pi / 2, 0, 0))
    board_light("PrintLight", (back - 0.9, y, 2.02), (back, y, z + 0.05), width - 0.2, 3.3)


# The app's own model of the SenseCAP Solar Node, at real size (scripts/device-models).
SOLAR_NODE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels", "seeed_solar.usdz")
# Where its back mount is in the model, in meters: between the two threaded inserts on the back of
# the box (see specs/seeed_solar.toml), in the model's own axes (Y up, +Z out of the panel).
SOLAR_NODE_MOUNT = Vector((0.0027, 0.117, -0.0376))


def solar_node(tripod_top, mast_mat, clamp_mat):
    """Puts the Solar Node on a mast above the tripod's head: its panel tipped back toward the sky
    and turned to face the seat. The antenna is fixed to the box, so it leans back with it."""
    tilt = math.radians(20)
    x, y, z = tripod_top
    # Turned so the panel faces the seat at the middle of the tent.
    yaw = math.atan2(-y, -x)
    facing = Vector((math.cos(yaw), math.sin(yaw), 0))
    # The clamp around the mast and the arm out to the mount on the node's back. The mast stops
    # just above the clamp, so it stays clear of the box as the box tips back over it.
    mount = Vector((x, y, z + 0.17)) + facing * 0.045
    cylinder("NodeMast", 0.016, (x, y, z - 0.02), (x, y, mount.z + 0.035), mast_mat)
    cylinder("NodeClamp", 0.024, (x, y, mount.z - 0.03), (x, y, mount.z + 0.03), clamp_mat)
    cylinder("NodeArm", 0.01, (x, y, mount.z), mount - facing * 0.008, clamp_mat)

    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=os.path.abspath(SOLAR_NODE))
    root = next(obj for obj in bpy.data.objects if obj not in before and obj.parent is None)
    # The importer turns the model's Y up into Blender's Z up on the root, which leaves the panel
    # facing -Y. Move the mount to the origin, tip the panel back, turn it to face the seat, and put
    # the mount on the arm.
    mount_local = root.matrix_world @ SOLAR_NODE_MOUNT
    turn = Matrix.Rotation(yaw + math.pi / 2, 4, "Z") @ Matrix.Rotation(-tilt, 4, "X")
    root.matrix_world = Matrix.Translation(mount) @ turn @ Matrix.Translation(-mount_local) @ root.matrix_world

def map_lamp(x, y, arm_mat, cord_mat):
    """A work lamp over the map table, hung from an arm clamped to the back rafter. The shade is a
    shallow dish, so the lit bulb and the glowing inside of the shade show from the seat, and its
    light lands on the table, not the floor."""
    inset = HALF_WIDTH - 0.05
    rafter_z = WALL_HEIGHT - 0.04 + (RIDGE_HEIGHT - WALL_HEIGHT - 0.02) * (1 - x / inset)
    hook = rafter_z - 0.05
    rim = 1.42
    depth, radius = 0.09, 0.17
    box("LampClamp", (0.05, 0.03, 0.08), (x, BACK_Y + 0.04, rafter_z - 0.02), arm_mat)
    cylinder("LampArm", 0.008, (x, BACK_Y + 0.04, hook), (x, y, hook), arm_mat, segments=8)
    cylinder("LampCord", 0.004, (x, y, hook), (x, y, rim + depth + 0.06), cord_mat, segments=6)
    torus("LampHook", 0.018, 0.003, (x, y, hook), cord_mat, rotation=(0, math.pi / 2, 0))
    cylinder("LampSocket", 0.022, (x, y, rim + depth - 0.01), (x, y, rim + depth + 0.07), cord_mat)

    def dish(r):
        def build(bm):
            bmesh.ops.create_cone(bm, cap_ends=False, segments=40, radius1=r, radius2=0.03, depth=depth)
        return build
    enamel = material("LampShade", (0.07, 0.11, 0.08), 0.35, metallic=0.6)
    smooth(mesh_object("LampShade", dish(radius), enamel, (x, y, rim + depth / 2)))
    # White enamel inside, lit by the bulb. Its glow is for the eye only; the spot below does the
    # lighting, so nothing spills onto the floor.
    inside = material("LampInside", (0.9, 0.86, 0.78), 0.3, emission=(1, 0.8, 0.55), strength=4)
    lining = mesh_object("LampInside", dish(radius - 0.004), inside, (x, y, rim + depth / 2 - 0.002))
    smooth(lining)
    lining.visible_diffuse = False
    # The bulb hangs a little below the rim, where it shows from across the tent.
    bulb = sphere("LampBulb", 0.035, (x, y, rim + 0.012), material("LampBulb", (1, 0.85, 0.6), emission=(1, 0.8, 0.55), strength=30), segments=20)
    bulb.visible_diffuse = False
    bulb.visible_shadow = False
    spot = bpy.data.lights.new("MapLamp", "SPOT")
    spot.energy = 30
    spot.color = (1, 0.85, 0.65)
    # About 25 degrees each side of straight down: the table stops all of it.
    spot.spot_size = math.radians(50)
    spot.spot_blend = 0.5
    spot.shadow_soft_size = 0.03
    obj = bpy.data.objects.new("MapLamp", spot)
    obj.location = (x, y, rim - 0.03)
    link(obj)


render(furnish)

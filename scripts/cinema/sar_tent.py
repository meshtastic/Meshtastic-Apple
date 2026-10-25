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
#  map table on the back wall to the right, and a mesh node on a tripod by the door. Nothing else
#  stands on the floor.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tent_base as tent  # noqa: E402
from tent_base import CACHE, HALF_WIDTH, anchor, box, cylinder, image_material, link, material, plane, sphere  # noqa: E402


def folding_table(name, center, length, along_y, top_mat, leg_mat):
    cx, cy = center
    size = (0.76, length, 0.04) if along_y else (length, 0.76, 0.04)
    box(name, size, (cx, cy, 0.74), top_mat, bevel=0.01)
    hx, hy = size[0] / 2 - 0.06, size[1] / 2 - 0.06
    for dx in (-hx, hx):
        for dy in (-hy, hy):
            cylinder(name + "Leg", 0.015, (cx + dx, cy + dy, 0), (cx + dx, cy + dy, 0.72), leg_mat)


def radio(location, body_mat, antenna_mat, led_mat):
    x, y, z = location
    box("Radio", (0.06, 0.035, 0.13), (x, y, z + 0.065), body_mat, bevel=0.006)
    cylinder("RadioAntenna", 0.006, (x + 0.018, y, z + 0.13), (x + 0.018, y, z + 0.29), antenna_mat)
    sphere("RadioLED", 0.004, (x - 0.018, y + 0.018, z + 0.12), led_mat, segments=8)


def furnish(layout):
    rng = random.Random(42)
    table_top = material("TableTop", (0.62, 0.61, 0.57), 0.5)
    steel = material("Steel", (0.15, 0.15, 0.16), 0.4, metallic=0.9)
    black_plastic = material("BlackPlastic", (0.02, 0.02, 0.02), 0.45)
    led_green = material("LEDGreen", (0, 1, 0.3), emission=(0.1, 1, 0.3), strength=8)
    led_red = material("LEDRed", (1, 0, 0), emission=(1, 0.1, 0.05), strength=8)
    yellow_case = material("CaseYellow", (0.85, 0.65, 0.05), 0.5)
    mug = material("Mug", (0.75, 0.75, 0.72), 0.3)
    paper = material("Paper", (0.88, 0.87, 0.82), 0.8)
    bottle = material("Bottle", (0.3, 0.5, 0.8), 0.1)
    wall = HALF_WIDTH - 0.38

    # Comms table along the left wall, under the plaque and the poster.
    folding_table("CommsTable", (-wall, 0.3), 1.8, True, table_top, steel)
    box("ChargerBank", (0.16, 0.5, 0.04), (-wall - 0.15, 0.91, 0.78), black_plastic, bevel=0.005)
    for i in range(6):
        radio((-wall - 0.15, 0.72 + i * 0.075, 0.80), black_plastic, black_plastic, led_green if i % 3 else led_red)
    cylinder("Mug", 0.04, (-wall + 0.25, 1.08, 0.76), (-wall + 0.25, 1.08, 0.86), mug)
    cylinder("Bottle", 0.035, (-wall + 0.25, 0.23, 0.76), (-wall + 0.25, 0.23, 0.98), bottle)
    box("PowerStrip", (0.06, 0.4, 0.04), (-wall - 0.3, 0.2, 0.78), material("Strip", (0.8, 0.8, 0.78), 0.5))
    for i in range(3):
        box("Log", (0.21, 0.29, 0.004), (-wall + 0.2 + rng.uniform(-0.03, 0.03), -0.45 + i * 0.01, 0.765 + i * 0.004), paper, rotation=(0, 0, rng.uniform(-0.2, 0.2)))

    # Radio table in the back corner on the left, under the window.
    folding_table("RadioTable", (-wall, -1.8), 1.3, True, table_top, steel)
    box("BaseRadio", (0.25, 0.3, 0.09), (-wall - 0.1, -1.95, 0.805), black_plastic, bevel=0.01)
    plane("BaseRadioFace", 0.2, 0.06, (-wall + 0.03, -1.95, 0.81), (math.pi / 2, 0, math.pi / 2), material("RadioDisplay", (0.2, 0.5, 1), emission=(0.25, 0.55, 1), strength=3))
    cylinder("Mic", 0.025, (-wall + 0.15, -1.62, 0.76), (-wall + 0.15, -1.62, 0.85), black_plastic)
    box("Binder", (0.3, 0.26, 0.05), (-wall + 0.05, -1.35, 0.785), material("Binder", (0.1, 0.25, 0.6), 0.5))

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
    radio((map_x - 0.5, map_y + 0.25, 0.765), black_plastic, black_plastic, led_green)
    box("Compass", (0.1, 0.06, 0.008), (map_x + 0.45, map_y - 0.25, 0.77), material("Compass", (0.8, 0.85, 0.9), 0.1))

    # A mesh node on a tripod just past the door, its antenna up near the eave, far enough along
    # that its legs stay clear of the door jamb.
    tripod_top = (wall + 0.05, 1.18, 1.35)
    for angle in (0, 2.1, 4.2):
        foot = (tripod_top[0] + 0.3 * math.cos(angle), tripod_top[1] + 0.3 * math.sin(angle), 0)
        cylinder("TripodLeg", 0.01, foot, tripod_top, steel)
    box("NodeCase", (0.1, 0.06, 0.14), (tripod_top[0], tripod_top[1], tripod_top[2] + 0.07), yellow_case, bevel=0.01)
    cylinder("NodeAntenna", 0.008, (tripod_top[0], tripod_top[1], tripod_top[2] + 0.14), (tripod_top[0], tripod_top[1], tripod_top[2] + 0.5), black_plastic)
    sphere("NodeLED", 0.006, (tripod_top[0] - 0.05, tripod_top[1], tripod_top[2] + 0.1), led_green, segments=8)

    # Whiteboard on the left wall in the front bay, on clear canvas. Left blank: the app draws the
    # live team roster over it (the "teamStatus" anchor). The front bay is narrower than the back
    # one, so the board is sized to fit between its two tent legs. It stands on two legs under the
    # frame, the way a mobile whiteboard does, so nothing crosses the board or crowds the tent legs
    # at either end of the bay. Its top sits well under the eave.
    board = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)
    board_x, board_y, board_z = -HALF_WIDTH + 0.1, 2.0, 1.17
    board_w, board_h = 1.35, 0.9
    whiteboard = plane("Whiteboard", board_w, board_h, (board_x + 0.02, board_y, board_z), tent.facing_in(-1), board)
    anchor("teamStatus", whiteboard, board_w, board_h)
    box("WhiteboardFrame", (0.03, board_w + 0.06, board_h + 0.06), (board_x, board_y, board_z), material("Frame", (0.7, 0.7, 0.72), 0.4, metallic=0.8))
    frame_bottom = board_z - board_h / 2 - 0.03
    for y in (board_y - board_w / 2 + 0.1, board_y + board_w / 2 - 0.1):
        cylinder("EaselLeg", 0.014, (board_x + 0.03, y, 0.02), (board_x + 0.03, y, frame_bottom), steel)
        cylinder("EaselFoot", 0.014, (board_x - 0.02, y, 0.02), (board_x + 0.3, y, 0.02), steel)

    # A light on the board, from up by the eave, so the painted board is as bright as the panel
    # the app draws over it. It can't be seen itself, in the image or on the board.
    board_light = bpy.data.lights.new("BoardLight", "AREA")
    board_light.shape = "RECTANGLE"
    board_light.size, board_light.size_y = board_w - 0.2, 0.3
    board_light.energy = 3.3
    board_light.color = (1, 0.55, 0.24)
    board_light.spread = math.radians(70)
    obj = bpy.data.objects.new("BoardLight", board_light)
    obj.location = (board_x + 0.9, board_y, 2.02)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector((board_x, board_y, board_z + 0.05)) - obj.location).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)

    map_lamp(map_x, map_y - 0.06, steel, black_plastic)


def map_lamp(x, y, arm_mat, cord_mat):
    """A work lamp over the map table, hung from an arm clamped to the back rafter. The shade is a
    shallow dish, so the lit bulb and the glowing inside of the shade show from the seat, and its
    light lands on the table, not the floor."""
    inset = HALF_WIDTH - 0.05
    rafter_z = tent.WALL_HEIGHT - 0.04 + (tent.RIDGE_HEIGHT - tent.WALL_HEIGHT - 0.02) * (1 - x / inset)
    hook = rafter_z - 0.05
    rim = 1.42
    depth, radius = 0.09, 0.17
    box("LampClamp", (0.05, 0.03, 0.08), (x, tent.BACK_Y + 0.04, rafter_z - 0.02), arm_mat)
    cylinder("LampArm", 0.008, (x, tent.BACK_Y + 0.04, hook), (x, y, hook), arm_mat, segments=8)
    cylinder("LampCord", 0.004, (x, y, hook), (x, y, rim + depth + 0.06), cord_mat, segments=6)
    tent.torus("LampHook", 0.018, 0.003, (x, y, hook), cord_mat, rotation=(0, math.pi / 2, 0))
    cylinder("LampSocket", 0.022, (x, y, rim + depth - 0.01), (x, y, rim + depth + 0.07), cord_mat)

    def dish(r):
        def build(bm):
            bmesh.ops.create_cone(bm, cap_ends=False, segments=40, radius1=r, radius2=0.03, depth=depth)
        return build
    enamel = material("LampShade", (0.07, 0.11, 0.08), 0.35, metallic=0.6)
    tent.smooth(tent.mesh_object("LampShade", dish(radius), enamel, (x, y, rim + depth / 2)))
    # White enamel inside, lit by the bulb. Its glow is for the eye only; the spot below does the
    # lighting, so nothing spills onto the floor.
    inside = material("LampInside", (0.9, 0.86, 0.78), 0.3, emission=(1, 0.8, 0.55), strength=4)
    lining = tent.mesh_object("LampInside", dish(radius - 0.004), inside, (x, y, rim + depth / 2 - 0.002))
    tent.smooth(lining)
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


tent.render(furnish)

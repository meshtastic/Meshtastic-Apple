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
#  Comms and radio tables on the left, the map table past the door on the right, a mesh node on a
#  tripod by the door, and the whiteboard the app draws the team roster on. The floor is left clear.

import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

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


def laptop(center, facing_angle, screen_mat, body_mat):
    cx, cy, z = center
    box("LaptopBase", (0.34, 0.24, 0.02), (cx, cy, z + 0.01), body_mat, rotation=(0, 0, facing_angle), bevel=0.004)
    lid_center = Vector((0, 0.12 + 0.02, 0.115))
    lid_center.rotate(Euler((0, 0, facing_angle)))
    box("LaptopLid", (0.34, 0.012, 0.23), (cx + lid_center.x, cy + lid_center.y, z + 0.02 + 0.105), body_mat, rotation=(-0.25, 0, facing_angle), bevel=0.003)
    screen = Vector((0, 0.12 + 0.012, 0))
    screen.rotate(Euler((0, 0, facing_angle)))
    plane("LaptopScreen", 0.31, 0.2, (cx + screen.x, cy + screen.y, z + 0.13), (math.pi / 2 - 0.25, 0, facing_angle + math.pi), screen_mat)


def radio(location, body_mat, antenna_mat, led_mat):
    x, y, z = location
    box("Radio", (0.06, 0.035, 0.13), (x, y, z + 0.065), body_mat, bevel=0.006)
    cylinder("RadioAntenna", 0.006, (x + 0.018, y, z + 0.13), (x + 0.018, y, z + 0.29), antenna_mat)
    sphere("RadioLED", 0.004, (x - 0.018, y + 0.018, z + 0.12), led_mat, segments=8)


def furnish():
    rng = random.Random(42)
    table_top = material("TableTop", (0.62, 0.61, 0.57), 0.5)
    steel = material("Steel", (0.15, 0.15, 0.16), 0.4, metallic=0.9)
    black_plastic = material("BlackPlastic", (0.02, 0.02, 0.02), 0.45)
    laptop_body = material("LaptopBody", (0.12, 0.12, 0.13), 0.35, metallic=0.6)
    screen_a = image_material("ScreenA", os.path.join(CACHE, "laptop_a.png"), 0.2, emission_strength=1.2)
    screen_b = image_material("ScreenB", os.path.join(CACHE, "laptop_b.png"), 0.2, emission_strength=1.2)
    led_green = material("LEDGreen", (0, 1, 0.3), emission=(0.1, 1, 0.3), strength=8)
    led_red = material("LEDRed", (1, 0, 0), emission=(1, 0.1, 0.05), strength=8)
    yellow_case = material("CaseYellow", (0.85, 0.65, 0.05), 0.5)
    mug = material("Mug", (0.75, 0.75, 0.72), 0.3)
    paper = material("Paper", (0.88, 0.87, 0.82), 0.8)
    bottle = material("Bottle", (0.3, 0.5, 0.8), 0.1)
    wall = HALF_WIDTH - 0.38

    # Comms table along the left wall.
    folding_table("CommsTable", (-wall, 0.9), 2.2, True, table_top, steel)
    laptop((-wall + 0.05, 0.3, 0.76), -math.pi / 2, screen_a, laptop_body)
    laptop((-wall + 0.05, 1.05, 0.76), -math.pi / 2, screen_b, laptop_body)
    box("ChargerBank", (0.16, 0.5, 0.04), (-wall - 0.15, 1.65, 0.78), black_plastic, bevel=0.005)
    for i in range(6):
        radio((-wall - 0.15, 1.45 + i * 0.08, 0.80), black_plastic, black_plastic, led_green if i % 3 else led_red)
    cylinder("Mug", 0.04, (-wall + 0.25, 1.75, 0.76), (-wall + 0.25, 1.75, 0.86), mug)
    cylinder("Bottle", 0.035, (-wall + 0.25, 0.65, 0.76), (-wall + 0.25, 0.65, 0.98), bottle)
    box("PowerStrip", (0.06, 0.4, 0.04), (-wall - 0.3, 0.6, 0.78), material("Strip", (0.8, 0.8, 0.78), 0.5))
    for i in range(3):
        box("Log", (0.21, 0.29, 0.004), (-wall + 0.2 + rng.uniform(-0.03, 0.03), -0.05 + i * 0.01, 0.765 + i * 0.004), paper, rotation=(0, 0, rng.uniform(-0.2, 0.2)))

    # Radio table further forward on the left.
    folding_table("RadioTable", (-wall, 3.1), 1.6, True, table_top, steel)
    box("BaseRadio", (0.25, 0.3, 0.09), (-wall - 0.1, 2.9, 0.805), black_plastic, bevel=0.01)
    plane("BaseRadioFace", 0.2, 0.06, (-wall + 0.03, 2.9, 0.81), (math.pi / 2, 0, math.pi / 2), material("RadioDisplay", (0.2, 0.5, 1), emission=(0.25, 0.55, 1), strength=3))
    cylinder("Mic", 0.025, (-wall + 0.15, 3.25, 0.76), (-wall + 0.15, 3.25, 0.85), black_plastic)
    box("Binder", (0.3, 0.26, 0.05), (-wall + 0.05, 3.55, 0.785), material("Binder", (0.1, 0.25, 0.6), 0.5))

    # Map table on the right, past the door.
    folding_table("MapTable", (wall - 0.1, 2.6), 1.8, True, table_top, steel)
    topo = image_material("Topo", os.path.join(CACHE, "topo.png"), 0.8)
    plane("TopoMap", 0.7, 1.4, (wall - 0.1, 2.6, 0.765), (0, 0, 0), topo)
    for _ in range(9):
        pin = led_red if rng.random() < 0.6 else material("PinYellow", (0.95, 0.8, 0.1), 0.4)
        x, y = wall - 0.1 + rng.uniform(-0.3, 0.3), 2.6 + rng.uniform(-0.6, 0.6)
        cylinder("PinShaft", 0.002, (x, y, 0.765), (x, y, 0.79), steel)
        sphere("PinHead", 0.007, (x, y, 0.795), pin, segments=8)
    radio((wall - 0.35, 2.0, 0.765), black_plastic, black_plastic, led_green)
    box("Compass", (0.06, 0.1, 0.008), (wall + 0.15, 3.1, 0.77), material("Compass", (0.8, 0.85, 0.9), 0.1))

    # A mesh node on a tripod by the door, its antenna up near the eave.
    tripod_top = (wall + 0.05, 1.25, 1.35)
    for angle in (0, 2.1, 4.2):
        foot = (tripod_top[0] + 0.3 * math.cos(angle), tripod_top[1] + 0.3 * math.sin(angle), 0)
        cylinder("TripodLeg", 0.01, foot, tripod_top, steel)
    box("NodeCase", (0.1, 0.06, 0.14), (tripod_top[0], tripod_top[1], tripod_top[2] + 0.07), yellow_case, bevel=0.01)
    cylinder("NodeAntenna", 0.008, (tripod_top[0], tripod_top[1], tripod_top[2] + 0.14), (tripod_top[0], tripod_top[1], tripod_top[2] + 0.5), black_plastic)
    sphere("NodeLED", 0.006, (tripod_top[0] - 0.05, tripod_top[1], tripod_top[2] + 0.1), led_green, segments=8)

    # Whiteboard on the left wall, behind the viewer's shoulder. Left blank: the app draws the live
    # team roster over it (the "teamStatus" anchor). The easel legs stand outside the frame so the
    # panel doesn't cover them; the near one is closer to the camera, so it stands farther out to
    # stay clear of the frame's edge in the image.
    board = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)
    board_x = -HALF_WIDTH + 0.1
    whiteboard = plane("Whiteboard", 1.8, 1.2, (board_x + 0.02, -1.6, 1.25), tent.facing_in(-1), board)
    anchor("teamStatus", whiteboard, 1.8, 1.2)
    box("WhiteboardFrame", (0.03, 1.86, 1.26), (board_x, -1.6, 1.25), material("Frame", (0.7, 0.7, 0.72), 0.4, metallic=0.8))
    for y in (-1.6 - 0.96, -1.6 + 1.08):
        cylinder("EaselLeg", 0.012, (board_x + 0.3, y, 0), (board_x + 0.02, y, 1.8), steel)

    # Clamp lamp over the map table.
    spot = bpy.data.lights.new("MapLamp", "SPOT")
    spot.energy = 60
    spot.color = (1, 0.85, 0.65)
    spot.spot_size = 1.3
    spot.shadow_soft_size = 0.1
    obj = bpy.data.objects.new("MapLamp", spot)
    obj.location = (1.85, 2.6, 1.7)
    link(obj)
    # Screen glow on the comms table.
    for y in (0.8, 1.6):
        area = bpy.data.lights.new("ScreenGlow", "AREA")
        area.energy = 4
        area.color = (0.6, 0.9, 0.7)
        area.size = 0.3
        obj = bpy.data.objects.new("ScreenGlow", area)
        obj.location = (-1.9, y, 0.92)
        obj.rotation_euler = (0, -math.pi / 2, 0)
        link(obj)


tent.render(furnish)

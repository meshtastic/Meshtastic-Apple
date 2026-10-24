#
#  sar_tent.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  Builds the search and rescue command tent for the visionOS cinema and renders it as a 360°
#  equirectangular panorama from the viewer's seat. Run with build.sh, not by hand:
#
#    Blender -b -P sar_tent.py -- --out out/sar_tent.png --width 4096 --samples 256
#
#  Everything in the tent is modeled here. The view out of the door is Poly Haven's
#  "Sunset Forest" HDRI (CC0), downloaded by build.sh. The image's center looks at the front
#  wall, which is left plain for the app window; Blender's +Y is that direction.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    options = {"out": os.path.join(HERE, "out", "sar_tent.png"), "width": 2048, "samples": 64, "blend": None}
    for i in range(0, len(argv) - 1, 2):
        key = argv[i].lstrip("-")
        options[key] = argv[i + 1]
    options["width"] = int(options["width"])
    options["samples"] = int(options["samples"])
    return options


# MARK: - Tent dimensions (meters, Z up, viewer at the origin)

HALF_WIDTH = 2.6
BACK_Y = -3.0
FRONT_Y = 4.2
WALL_HEIGHT = 1.95
RIDGE_HEIGHT = 3.0
DOOR = (-0.6, 0.9, 1.85)  # right wall: from y, to y, top
RAFTERS = [-3.0, -1.8, -0.6, 0.9, 2.0, 3.1, 4.2]
EYE_HEIGHT = 1.15


# MARK: - Helpers

def material(name, color=(0.5, 0.5, 0.5), roughness=0.6, metallic=0.0, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def image_material(name, path, roughness=0.5, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_strength:
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def link(obj, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_object(name, build, mat=None, location=(0, 0, 0), rotation=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.rotation_euler = rotation
    if mat:
        obj.data.materials.append(mat)
    return link(obj)


def box(name, size, location, mat, rotation=(0, 0, 0), bevel=0.0):
    sx, sy, sz = size

    def build(bm):
        bmesh.ops.create_cube(bm, size=1)
        for v in bm.verts:
            v.co.x *= sx
            v.co.y *= sy
            v.co.z *= sz
    obj = mesh_object(name, build, mat, location, rotation)
    if bevel:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 4
        smooth(obj)
    return obj


def smooth(obj):
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def cylinder(name, radius, start, end, mat, segments=16):
    start, end = Vector(start), Vector(end)
    direction = end - start

    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=direction.length)
    obj = mesh_object(name, build, mat, (start + end) / 2)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    smooth(obj)
    return obj


def sphere(name, radius, location, mat, segments=12):
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2, radius=radius)
    obj = mesh_object(name, build, mat, location)
    smooth(obj)
    return obj


def torus(name, major, minor, location, mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=10, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    smooth(obj)
    return obj


def plane(name, width, height, location, rotation, mat):
    def build(bm):
        w, h = width / 2, height / 2
        verts = [bm.verts.new(co) for co in [(-w, -h, 0), (w, -h, 0), (w, h, 0), (-w, h, 0)]]
        face = bm.faces.new(verts)
        uv = bm.loops.layers.uv.new()
        for loop, coord in zip(face.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            loop[uv].uv = coord
    return mesh_object(name, build, mat, location, rotation)


# MARK: - Materials

def canvas_material():
    mat = bpy.data.materials.new("Canvas")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    output = nodes["Material Output"]
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.36, 0.31, 0.21, 1)
    bsdf.inputs["Roughness"].default_value = 0.95
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.6
    noise.inputs["Detail"].default_value = 6
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.20, 0.17, 0.11, 1)
    ramp.color_ramp.elements[1].color = (0.29, 0.25, 0.17, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    weave = nodes.new("ShaderNodeTexNoise")
    weave.inputs["Scale"].default_value = 220
    links.new(coords.outputs["Object"], weave.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    links.new(weave.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    # Light from outside glows through the canvas.
    translucent = nodes.new("ShaderNodeBsdfTranslucent")
    translucent.inputs["Color"].default_value = (0.85, 0.62, 0.38, 1)
    mix = nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = 0.12
    links.new(bsdf.outputs["BSDF"], mix.inputs[1])
    links.new(translucent.outputs["BSDF"], mix.inputs[2])
    links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return mat


def floor_material():
    mat = bpy.data.materials.new("Floor")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3
    noise.inputs["Detail"].default_value = 8
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.035, 0.04, 0.035, 1)
    ramp.color_ramp.elements[1].color = (0.075, 0.08, 0.07, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    # Seams between the floor mats.
    bricks = nodes.new("ShaderNodeTexBrick")
    bricks.inputs["Scale"].default_value = 1
    bricks.inputs["Mortar Size"].default_value = 0.004
    bricks.offset = 0
    links.new(coords.outputs["Object"], bricks.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    links.new(bricks.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# MARK: - The tent

def build_tent(canvas, metal):
    x, back, front = HALF_WIDTH, BACK_Y, FRONT_Y
    door_from, door_to, door_top = DOOR

    def walls(bm):
        def face(points):
            bm.faces.new([bm.verts.new(p) for p in points])
        face([(-x, back, 0), (-x, front, 0), (-x, front, WALL_HEIGHT), (-x, back, WALL_HEIGHT)])
        face([(x, back, 0), (x, door_from, 0), (x, door_from, WALL_HEIGHT), (x, back, WALL_HEIGHT)])
        face([(x, door_to, 0), (x, front, 0), (x, front, WALL_HEIGHT), (x, door_to, WALL_HEIGHT)])
        face([(x, door_from, door_top), (x, door_to, door_top), (x, door_to, WALL_HEIGHT), (x, door_from, WALL_HEIGHT)])
        face([(-x, back, WALL_HEIGHT), (-x, front, WALL_HEIGHT), (0, front, RIDGE_HEIGHT), (0, back, RIDGE_HEIGHT)])
        face([(x, back, WALL_HEIGHT), (0, back, RIDGE_HEIGHT), (0, front, RIDGE_HEIGHT), (x, front, WALL_HEIGHT)])
        for y in (back, front):
            face([(-x, y, 0), (x, y, 0), (x, y, WALL_HEIGHT), (0, y, RIDGE_HEIGHT), (-x, y, WALL_HEIGHT)])
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=12, use_grid_fill=True)
    tent = mesh_object("Tent", walls, canvas)
    # Canvas sags a little between the rafters.
    for v in tent.data.vertices:
        nearest = min(abs(v.co.y - r) for r in RAFTERS)
        if 0.05 < v.co.z and abs(v.co.x) < x - 0.01:
            v.co.z -= 0.05 * math.sin(min(nearest / 0.75, 1) * math.pi / 2)
        elif abs(abs(v.co.x) - x) < 0.01 and 0.1 < v.co.z < WALL_HEIGHT - 0.05:
            v.co.x -= math.copysign(0.04 * math.sin(min(nearest / 0.75, 1) * math.pi / 2), v.co.x)
    smooth(tent)

    # The rolled-up door flap.
    cylinder("DoorRoll", 0.08, (x + 0.06, door_from - 0.05, door_top - 0.05), (x + 0.06, door_to + 0.05, door_top - 0.05), canvas)
    for y in (door_from + 0.2, door_to - 0.2):
        cylinder("DoorTie", 0.008, (x + 0.02, y, WALL_HEIGHT - 0.02), (x + 0.15, y, door_top - 0.12), material("Strap", (0.05, 0.05, 0.05), 0.8))

    radius = 0.022
    inset = x - 0.05
    for y in RAFTERS:
        for side in (-1, 1):
            cylinder("Leg", radius, (side * inset, y, 0), (side * inset, y, WALL_HEIGHT - 0.04), metal)
            cylinder("Rafter", radius, (side * inset, y, WALL_HEIGHT - 0.04), (0, y, RIDGE_HEIGHT - 0.06), metal)
    for side in (-1, 1):
        cylinder("Eave", radius, (side * inset, BACK_Y, WALL_HEIGHT - 0.04), (side * inset, FRONT_Y, WALL_HEIGHT - 0.04), metal)
    cylinder("Ridge", radius, (0, BACK_Y, RIDGE_HEIGHT - 0.06), (0, FRONT_Y, RIDGE_HEIGHT - 0.06), metal)

    floor = floor_material()
    box("Floor", (2 * x, front - back, 0.01), (0, (front + back) / 2, -0.005), floor)


# MARK: - Furniture and gear

def folding_table(name, center, length, along_y, top_mat, leg_mat):
    cx, cy = center
    size = (0.76, length, 0.04) if along_y else (length, 0.76, 0.04)
    box(name, size, (cx, cy, 0.74), top_mat, bevel=0.01)
    hx, hy = size[0] / 2 - 0.06, size[1] / 2 - 0.06
    for dx in (-hx, hx):
        for dy in (-hy, hy):
            cylinder(name + "Leg", 0.015, (cx + dx, cy + dy, 0), (cx + dx, cy + dy, 0.72), leg_mat)


def folding_chair(center, facing, mat):
    cx, cy = center
    angle = math.atan2(facing[1], facing[0]) - math.pi / 2
    seat = box("ChairSeat", (0.42, 0.40, 0.03), (cx, cy, 0.45), mat, rotation=(0, 0, angle), bevel=0.01)
    back_offset = Vector((-facing[0], -facing[1], 0)).normalized() * 0.2
    box("ChairBack", (0.42, 0.03, 0.28), (cx + back_offset.x, cy + back_offset.y, 0.78), mat, rotation=(0.15, 0, angle), bevel=0.01)
    for dx in (-0.18, 0.18):
        for dy in (-0.17, 0.17):
            leg = Vector((dx, dy, 0))
            leg.rotate(Euler((0, 0, angle)))
            cylinder("ChairLeg", 0.011, (cx + leg.x, cy + leg.y, 0), (cx + leg.x, cy + leg.y, 0.44), mat)
    return seat


def laptop(center, facing_angle, screen_mat, body_mat):
    cx, cy, z = center
    box("LaptopBase", (0.34, 0.24, 0.02), (cx, cy, z + 0.01), body_mat, rotation=(0, 0, facing_angle), bevel=0.004)
    hinge = Vector((0, 0.12, 0))
    hinge.rotate(Euler((0, 0, facing_angle)))
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


def build_props():
    rng = random.Random(42)
    table_top = material("TableTop", (0.62, 0.61, 0.57), 0.5)
    steel = material("Steel", (0.15, 0.15, 0.16), 0.4, metallic=0.9)
    chair = material("Chair", (0.08, 0.10, 0.12), 0.6)
    black_plastic = material("BlackPlastic", (0.02, 0.02, 0.02), 0.45)
    laptop_body = material("LaptopBody", (0.12, 0.12, 0.13), 0.35, metallic=0.6)
    screen_a = image_material("ScreenA", os.path.join(CACHE, "laptop_a.png"), 0.2, emission_strength=1.2)
    screen_b = image_material("ScreenB", os.path.join(CACHE, "laptop_b.png"), 0.2, emission_strength=1.2)
    led_green = material("LEDGreen", (0, 1, 0.3), emission=(0.1, 1, 0.3), strength=8)
    led_red = material("LEDRed", (1, 0, 0), emission=(1, 0.1, 0.05), strength=8)
    orange = material("RescueOrange", (0.85, 0.22, 0.02), 0.55)
    case_gray = material("CaseGray", (0.06, 0.065, 0.07), 0.5)
    yellow_case = material("CaseYellow", (0.85, 0.65, 0.05), 0.5)
    rope_blue = material("RopeBlue", (0.05, 0.18, 0.55), 0.8)
    rope_orange = material("RopeOrange", (0.9, 0.35, 0.05), 0.8)
    mug = material("Mug", (0.75, 0.75, 0.72), 0.3)
    paper = material("Paper", (0.88, 0.87, 0.82), 0.8)
    bottle = material("Bottle", (0.3, 0.5, 0.8), 0.1)
    olive = material("Olive", (0.12, 0.15, 0.08), 0.8)
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
    folding_chair((-wall + 0.6, 0.4), (-1, 0), chair)
    folding_chair((-wall + 0.6, 1.2), (-1, 0), chair)
    box("CaseUnderTable", (0.5, 0.35, 0.22), (-wall - 0.05, 1.6, 0.11), case_gray, bevel=0.02)

    # Radio table further forward on the left.
    folding_table("RadioTable", (-wall, 3.1), 1.6, True, table_top, steel)
    box("BaseRadio", (0.25, 0.3, 0.09), (-wall - 0.1, 2.9, 0.805), black_plastic, bevel=0.01)
    plane("BaseRadioFace", 0.2, 0.06, (-wall + 0.03, 2.9, 0.81), (math.pi / 2, 0, math.pi / 2), material("RadioDisplay", (0.2, 0.5, 1), emission=(0.25, 0.55, 1), strength=3))
    cylinder("Mic", 0.025, (-wall + 0.15, 3.25, 0.76), (-wall + 0.15, 3.25, 0.85), black_plastic)
    box("Binder", (0.3, 0.26, 0.05), (-wall + 0.05, 3.55, 0.785), material("Binder", (0.1, 0.25, 0.6), 0.5))
    box("Battery", (0.3, 0.2, 0.2), (-wall - 0.05, 3.4, 0.1), yellow_case, bevel=0.015)
    folding_chair((-wall + 0.6, 3.0), (-1, 0), chair)

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
    folding_chair((wall - 0.7, 2.8), (1, 0), chair)
    folding_chair((wall - 0.7, 2.1), (1, 0), chair)

    # A mesh node on a tripod by the door, its antenna up near the eave.
    tripod_top = (wall + 0.05, 1.25, 1.35)
    for angle in (0, 2.1, 4.2):
        foot = (tripod_top[0] + 0.3 * math.cos(angle), tripod_top[1] + 0.3 * math.sin(angle), 0)
        cylinder("TripodLeg", 0.01, foot, tripod_top, steel)
    box("NodeCase", (0.1, 0.06, 0.14), (tripod_top[0], tripod_top[1], tripod_top[2] + 0.07), yellow_case, bevel=0.01)
    cylinder("NodeAntenna", 0.008, (tripod_top[0], tripod_top[1], tripod_top[2] + 0.14), (tripod_top[0], tripod_top[1], tripod_top[2] + 0.5), black_plastic)
    sphere("NodeLED", 0.006, (tripod_top[0] - 0.05, tripod_top[1], tripod_top[2] + 0.1), led_green, segments=8)

    # Whiteboard on the left wall, behind the viewer's shoulder.
    board = image_material("Whiteboard", os.path.join(CACHE, "status_board.png"), 0.25)
    board_x = -HALF_WIDTH + 0.1
    plane("Whiteboard", 1.8, 1.2, (board_x + 0.02, -1.6, 1.25), (math.pi / 2, 0, math.pi / 2), board)
    box("WhiteboardFrame", (0.03, 1.86, 1.26), (board_x, -1.6, 1.25), material("Frame", (0.7, 0.7, 0.72), 0.4, metallic=0.8))
    for x, y in ((board_x + 0.3, -2.4), (board_x + 0.3, -0.8)):
        cylinder("EaselLeg", 0.012, (x, y, 0), (board_x + 0.02, y, 1.8), steel)

    # Gear along the back wall and the right rear corner.
    back = BACK_Y + 0.35
    for i, (x, y) in enumerate([(1.3, back), (1.7, back - 0.05), (2.05, back + 0.05), (-0.4, back)]):
        box("Pack", (0.34, 0.24, 0.56), (x, y, 0.28), orange, rotation=(0.08 * (i % 2), 0, rng.uniform(-0.3, 0.3)), bevel=0.06)
    box("CaseLarge", (0.9, 0.5, 0.42), (wall, -1.7, 0.21), case_gray, rotation=(0, 0, math.pi / 2), bevel=0.03)
    box("CaseSmall", (0.55, 0.38, 0.24), (wall, -1.75, 0.54), yellow_case, rotation=(0, 0, math.pi / 2 + 0.1), bevel=0.02)
    for i, mat in enumerate([rope_blue, rope_orange, rope_blue]):
        torus("Rope", 0.2, 0.022, (wall - 0.05, -1.7 + (i - 1) * 0.02, 0.69 + i * 0.045), mat)
    box("Litter", (0.6, 2.0, 0.12), (-0.9, back, 0.06), material("Litter", (0.75, 0.15, 0.08), 0.5), rotation=(0, 0, math.pi / 2), bevel=0.04)
    for x in (-2.0, -1.5):
        box("Bin", (0.45, 0.6, 0.35), (x, back, 0.175), material("Bin", (0.12, 0.13, 0.12), 0.6), bevel=0.02)
        box("BinLid", (0.47, 0.62, 0.03), (x, back, 0.36), material("BinLid", (0.85, 0.7, 0.1), 0.5), bevel=0.01)
        box("Bin", (0.45, 0.6, 0.35), (x, back, 0.55), material("Bin", (0.12, 0.13, 0.12), 0.6), bevel=0.02)
    for i in range(4):
        box("WaterCase", (0.4, 0.27, 0.22), (0.35 + (i % 2) * 0.42, back, 0.11 + (i // 2) * 0.22), material("Water", (0.55, 0.7, 0.9), 0.2), bevel=0.01)
    for y in (back + 0.4, back + 0.7):
        box("Helmet", (0.22, 0.26, 0.14), (-1.75, y, 0.8), orange, bevel=0.06)
    # On the floor near the seat: a cooler and a duffel.
    box("Cooler", (0.6, 0.38, 0.4), (1.0, -1.0, 0.2), material("Cooler", (0.1, 0.3, 0.6), 0.4), rotation=(0, 0, 0.3), bevel=0.03)
    box("CoolerLid", (0.62, 0.4, 0.06), (1.0, -1.0, 0.42), material("CoolerLid", (0.85, 0.85, 0.82), 0.4), rotation=(0, 0, 0.3), bevel=0.02)
    box("Duffel", (0.7, 0.32, 0.3), (-1.1, -0.9, 0.15), olive, rotation=(0, 0, -0.4), bevel=0.12)

    # Jackets hanging from the rear rafter.
    for i, x in enumerate((-0.9, -0.55, 0.9)):
        box("Jacket", (0.42, 0.08, 0.7), (x, BACK_Y + 0.12, 1.4), orange if i != 1 else material("JacketYellow", (0.8, 0.75, 0.05), 0.7), bevel=0.04)


# MARK: - Lights

def build_lights():
    bulb = material("Bulb", (1, 0.75, 0.45), emission=(1, 0.62, 0.3), strength=18)
    wire = material("Wire", (0.02, 0.02, 0.02), 0.6)
    # A string of bulbs down each side of the roof, drooping between rafters.
    for side in (-1, 1):
        points = []
        y = BACK_Y + 0.2
        while y < FRONT_Y - 0.2:
            nearest = min(abs(y - r) for r in RAFTERS)
            sag = 0.12 * math.sin(min(nearest / 0.75, 1) * math.pi / 2)
            x = side * 1.2
            z = WALL_HEIGHT + (RIDGE_HEIGHT - WALL_HEIGHT) * (1 - 1.2 / HALF_WIDTH) - 0.12 - sag
            points.append((x, y, z))
            y += 0.42
        for a, b in zip(points, points[1:]):
            cylinder("LightWire", 0.003, a, b, wire, segments=6)
        for p in points:
            sphere("Bulb", 0.03, (p[0], p[1], p[2] - 0.05), bulb)
    warm = (1.0, 0.70, 0.42)
    for y in (-1.8, 0.9):
        light = bpy.data.lights.new("Work", "POINT")
        light.energy = 25
        light.color = warm
        light.shadow_soft_size = 0.25
        obj = bpy.data.objects.new("Work", light)
        obj.location = (0, y, RIDGE_HEIGHT - 0.8)
        link(obj)
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


def build_world():
    world = bpy.data.worlds.new("Dusk")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    background = nodes["Background"]
    environment = nodes.new("ShaderNodeTexEnvironment")
    environment.image = bpy.data.images.load(os.path.join(CACHE, "sunset_forest_4k.hdr"))
    mapping = nodes.new("ShaderNodeMapping")
    coords = nodes.new("ShaderNodeTexCoord")
    # Turns the sunset toward the open door.
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(200))
    links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], environment.inputs["Vector"])
    links.new(environment.outputs["Color"], background.inputs["Color"])
    background.inputs["Strength"].default_value = 0.4
    bpy.context.scene.world = world


def build_camera():
    data = bpy.data.cameras.new("Seat")
    data.type = "PANO"
    data.panorama_type = "EQUIRECTANGULAR"
    camera = bpy.data.objects.new("Seat", data)
    camera.location = (0, 0, EYE_HEIGHT)
    # Looks along +Y, at the front wall.
    camera.rotation_euler = (math.pi / 2, 0, 0)
    link(camera)
    bpy.context.scene.camera = camera


def configure_render(options):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    preferences = bpy.context.preferences.addons["cycles"].preferences
    try:
        preferences.compute_device_type = "METAL"
        preferences.get_devices()
        for device in preferences.devices:
            device.use = True
        scene.cycles.device = "GPU"
    except TypeError:
        scene.cycles.device = "CPU"
    scene.cycles.samples = options["samples"]
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.render.resolution_x = options["width"]
    scene.render.resolution_y = options["width"] // 2
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.0
    scene.render.filepath = options["out"]


def main():
    options = arguments()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    canvas = canvas_material()
    metal = material("Aluminum", (0.75, 0.76, 0.78), 0.35, metallic=1.0)
    build_tent(canvas, metal)
    build_props()
    build_lights()
    build_world()
    build_camera()
    configure_render(options)
    if options["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(options["blend"]))
    bpy.ops.render.render(write_still=True)
    print("rendered", options["out"])


main()

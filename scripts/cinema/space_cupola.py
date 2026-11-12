#
#  space_cupola.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  A space station module under its cupola for the visionOS cinema, built on room_base.py. Run
#  with build.sh, not by hand:
#
#    Blender -b -P space_cupola.py -- --out out/space_cupola.png --width 4096 --samples 160
#
#  The viewer sits in the middle of a node module, lined with racks of off-white panels, with
#  handrails and the clutter of a station that's lived in. Overhead and a little ahead, the
#  cupola opens out of the ceiling: six trapezoid windows round a round one at the top, with Earth
#  through them. The screen hangs on the plain front bulkhead. The two whiteboards the app draws
#  the team roster and the nodes' status messages on are strapped to the racks on the left, and
#  the print it draws the latest trace route on to the racks on the right. The ham radio station
#  is on the right behind the print, with a Meshtastic radio strapped beside it, and the hatch to
#  the next module, a mission patch and Chirpy's poster are behind the seat.
#
#  The image is a cutout lit only by its own lights, with nothing past the windows: the app paints
#  the view from space_earth.py behind it, and the light through the cupola comes from where that
#  view puts Earth.

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orbit import earth_direction  # noqa: E402
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
)

DEVICE_MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels")

# MARK: - The module (meters)

# The racks on the left and right are HALF from the seat, the front bulkhead FRONT ahead and the
# back one BACK behind. Wider than a real node, so everything is at the distance the cinema's
# image reads well at.
HALF = 2.3
FRONT = 2.4
BACK = 2.5
CEILING = 2.05
# The utility runs along the module's four long corners, cut across at 45°.
CORNER = 0.38

# The cupola, centered this far ahead of the seat over a round opening in the ceiling.
CUPOLA_Y = 0.3
THROAT = 1.2
THROAT_TOP = CEILING + 0.18
# Its six trapezoid windows lean in between a hexagon of BASE radius (to the corners) at the bottom
# and one of TOP radius at the top, where the round window is.
BASE = 1.45
TOP = 0.72
TOP_Z = CEILING + 0.82
ROUND_WINDOW = 0.42
# How far each trapezoid window's opening is in from its frame's edges.
MULLION = 0.11

# Boards on the racks: each one's center along the wall (y) and its size.
ROSTER = (-1, 0.72, 0.95, 0.633)
STATUS = (-1, -0.55, 0.95, 0.633)
TRACE = (1, 0.62, 0.9, 0.74)
BOARD_Z = EYE_HEIGHT + 0.22


# MARK: - Materials

def panel_material(name, color, roughness=0.55):
    """Painted aluminum panels: a faint mottle so a wall of them isn't one flat color."""
    mat = material(name, color, roughness)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6
    noise.inputs["Detail"].default_value = 4
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*[c * 0.93 for c in color], 1)
    ramp.color_ramp.elements[1].color = (*[min(1, c * 1.04) for c in color], 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def fabric(name, color):
    """Nomex cloth, as the cargo bags and the closeout curtains are made of."""
    mat = material(name, color, 0.95)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Sheen Weight"].default_value = 0.3
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 300
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glass_material():
    mat = bpy.data.materials.new("WindowGlass")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.remove(nodes["Principled BSDF"])
    glass = nodes.new("ShaderNodeBsdfGlass")
    glass.inputs["Color"].default_value = (0.96, 0.98, 1.0, 1)
    glass.inputs["Roughness"].default_value = 0.0
    glass.inputs["IOR"].default_value = 1.47
    links.new(glass.outputs[0], nodes["Material Output"].inputs["Surface"])
    return mat


def glowing(name, path, strength):
    """A screen or display that gives its own light."""
    mat = image_material(name, path, 0.3)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = next(node for node in nodes if node.type == "TEX_IMAGE")
    links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


MATERIALS = {}


def mats():
    """The module's shared materials, made once."""
    if not MATERIALS:
        MATERIALS.update({
            "rack": panel_material("Rack", (0.66, 0.65, 0.61)),
            "rack_light": panel_material("RackLight", (0.74, 0.73, 0.69)),
            "rack_gray": panel_material("RackGray", (0.52, 0.53, 0.53)),
            "deck": panel_material("Deck", (0.3, 0.3, 0.29), 0.7),
            "bulkhead": panel_material("Bulkhead", (0.8, 0.79, 0.75), 0.6),
            "frame": material("Frame", (0.6, 0.61, 0.63), 0.35, metallic=0.8),
            "dark": material("Dark", (0.035, 0.035, 0.04), 0.5),
            "handrail": material("Handrail", (0.12, 0.26, 0.55), 0.35, metallic=0.4),
            "velcro": fabric("Velcro", (0.06, 0.06, 0.065)),
            "bag": fabric("Bag", (0.6, 0.57, 0.5)),
            "bag_blue": fabric("BagBlue", (0.2, 0.3, 0.5)),
            "strap": fabric("Strap", (0.32, 0.3, 0.27)),
            "label": material("Label", (0.92, 0.92, 0.88), 0.7),
            "yellow": material("Yellow", (0.85, 0.65, 0.08), 0.5),
            "cable": material("Cable", (0.04, 0.04, 0.045), 0.6),
            "cable_gray": material("CableGray", (0.4, 0.4, 0.42), 0.6),
            "glass": glass_material(),
            "led": material("LED", (1, 1, 1), 0.3, emission=(1.0, 0.97, 0.92), strength=2.5),
        })
    return MATERIALS


# MARK: - Helpers

def on_wall(side, y, out, z):
    """A point `out` toward the seat from the racks' faces on the left (-1) or right (1) wall."""
    return (side * (HALF - out), y, z)


def wall_box(name, side, y, out, z, size, mat, bevel=0.004):
    """A box against the left or right racks, `size` as (along the wall, out from it, height)."""
    along, depth, height = size
    return box(name, (depth, along, height), on_wall(side, y, out + depth / 2, z), mat, bevel=bevel)


def facing(side):
    """The turn that stands a plane up on the left or right wall, facing the seat."""
    return (math.pi / 2, 0, -side * math.pi / 2)


def curve(name, points, radius, mat):
    """A smooth tube through `points`, for cables."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 3
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, data)
    obj.data.materials.append(mat)
    return link(obj)


def light(name, kind, location, energy, color=(1, 1, 1), size=0.2, target=None, size_y=None):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.shape = "RECTANGLE"
        data.size = size
        data.size_y = size_y or size
    else:
        data.shadow_soft_size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    if target is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    return link(obj)


# MARK: - The module's shell

def build_shell():
    m = mats()
    inner = HALF - CORNER
    length = FRONT + BACK
    middle = (FRONT - BACK) / 2
    # The deck, the racks either side and the overhead, between the corner runs.
    box("Deck", (2 * inner, length, 0.1), (0, middle, -0.05), m["deck"])
    for side in (-1, 1):
        box("RackBack", (0.1, length, CEILING - 2 * CORNER), (side * (HALF + 0.05), middle, CEILING / 2), m["rack"])
    overhead = box("Overhead", (2 * inner, length, 0.1), (0, middle, CEILING + 0.05), m["rack_light"])
    cut = cylinder("OverheadCut", THROAT, (0, CUPOLA_Y, CEILING - 0.2), (0, CUPOLA_Y, CEILING + 0.3), None, segments=96)
    modifier = overhead.modifiers.new("Opening", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.object = cut
    bpy.context.view_layer.objects.active = overhead
    bpy.ops.object.modifier_apply(modifier="Opening")
    bpy.data.objects.remove(cut)

    # The corner runs: flat panels at 45°, the top two with the module's light strips.
    run = CORNER * math.sqrt(2)
    for side in (-1, 1):
        for top in (False, True):
            z = CEILING - CORNER / 2 if top else CORNER / 2
            x = side * (HALF - CORNER / 2)
            tilt = side * math.pi / 4 * (1 if top else -1)
            box("CornerRun", (run, length, 0.06), (x + side * 0.03, middle, z + (0.03 if top else -0.03)), m["rack_gray"], rotation=(0, tilt, 0))
            if top:
                for y in (-1.6, 0.0, 1.6):
                    box("LightStrip", (0.16, 1.1, 0.02), (x - side * 0.005, y, z - 0.005), m["led"], rotation=(0, tilt, 0))
                    light("Ceiling", "AREA", (x - side * 0.06, y, z - 0.06), 8, (1.0, 0.97, 0.92), size=0.16, size_y=1.1,
                          target=(-side * 1.2, y, 0.6))
            else:
                # Cable trays along the bottom runs.
                box("Tray", (0.1, length - 0.4, 0.03), (x - side * 0.02, middle, z + 0.05), m["dark"], rotation=(0, tilt, 0))

    # The bulkheads: plain closeout panels in front for the screen, the hatch behind.
    for y, name in ((FRONT, "Front"), (-BACK, "Back")):
        sign = 1 if y > 0 else -1
        box(name + "Bulkhead", (2 * HALF, 0.1, CEILING + 0.1), (0, y + sign * 0.05, CEILING / 2), m["bulkhead"])
        for side in (-1, 1):
            for top in (False, True):
                corner = Vector((side * (HALF - CORNER / 2), y - sign * 0.01, CEILING - CORNER / 2 if top else CORNER / 2))
                box(name + "Corner", (CORNER * 1.45, 0.02, CORNER * 1.45), corner + Vector((side * CORNER / 2, 0, (CORNER / 2) * (1 if top else -1))),
                    m["rack_gray"], rotation=(0, math.pi / 4, 0))


def deck_details():
    """Seams in the deck panels, seat track and foot loops along the racks."""
    m = mats()
    # Seams only out by the racks: lines under the seat would bend into arcs across the view.
    for side in (-1, 1):
        for y in (-1.8, -0.6, 0.6, 1.8):
            box("DeckSeam", (0.5, 0.012, 0.004), (side * (HALF - CORNER - 0.25), y, 0.002), m["dark"])
    # A rail of seat track down each side of the deck, out by the racks.
    for x in (-1.55, 1.55):
        box("SeatTrack", (0.05, FRONT + BACK - 0.6, 0.012), (x, (FRONT - BACK) / 2, 0.006), m["frame"])
    # Foot loops along the deck by the racks, for holding still at them.
    for side in (-1, 1):
        for y in (-1.6, -0.4, 0.8, 1.9):
            for dy in (0, 0.22):
                p = Vector((side * (HALF - CORNER - 0.12), y + dy, 0))
                curve("FootLoop", [p, p + Vector((side * 0.02, 0.05, 0.07)), p + Vector((0, 0.15, 0.07)), p + Vector((0, 0.2, 0))], 0.012, m["strap"])


def handrail(name, start, end, up=(1, 0, 0)):
    """A handrail on two standoffs, 6 cm out from the surface it's on, `up` its outward direction."""
    m = mats()
    start, end, up = Vector(start), Vector(end), Vector(up)
    offset = up * 0.06
    cylinder(name, 0.016, start + offset, end + offset, m["handrail"], segments=12)
    for at in (start, end):
        cylinder(name + "Standoff", 0.014, at, at + offset, m["handrail"], segments=12)
        box(name + "Foot", (0.05, 0.05, 0.05), at, m["frame"])


# MARK: - The racks

def rack(side, y, width, seed):
    """One rack's face: closeout panels, a drawer bank, labels, velcro and the odd bag strapped on."""
    m = mats()
    rng = random.Random(seed)
    height = CEILING - 2 * CORNER
    z0 = CORNER
    wall_box("RackFrame", side, y, 0, z0 + height / 2, (width, 0.04, height), m["rack"])
    z = z0 + 0.03
    while z < z0 + height - 0.12:
        h = min(rng.choice((0.22, 0.3, 0.36, 0.44)), z0 + height - 0.03 - z)
        mat = rng.choice((m["rack_light"], m["rack_light"], m["rack"], m["rack_gray"]))
        wall_box("RackPanel", side, y, 0.04, z + h / 2, (width - 0.05, 0.015, h - 0.02), mat)
        # Quarter-turn fasteners in the corners and a label.
        for du in (-1, 1):
            for dz in (-1, 1):
                sphere("Fastener", 0.009, on_wall(side, y + du * (width / 2 - 0.05), 0.06, z + h / 2 + dz * (h / 2 - 0.04)), m["frame"], segments=8)
        if rng.random() < 0.7:
            wall_box("RackLabel", side, y + rng.uniform(-0.2, 0.2), 0.055, z + h / 2 + h * 0.2, (rng.uniform(0.08, 0.2), 0.003, 0.03), m["label"])
        if h >= 0.3 and rng.random() < 0.35:
            # A drawer pull.
            wall_box("Pull", side, y, 0.055, z + h / 2, (0.18, 0.025, 0.02), m["frame"])
        if rng.random() < 0.35:
            wall_box("Velcro", side, y + rng.uniform(-0.3, 0.3), 0.055, z + h / 2, (0.08, 0.004, 0.05), m["velcro"])
        z += h


def stowage(side, y, z, size, mat, seed):
    """A soft bag velcroed to the racks, bulging a little, with a strap across it and a tag."""
    m = mats()
    rng = random.Random(seed)
    along, depth, height = size
    bag = wall_box("StowageBag", side, y, 0.05, z, (along, depth, height), mat, bevel=0.03)
    bag.rotation_euler = (rng.uniform(-0.04, 0.04), 0, 0)
    wall_box("StowageStrap", side, y + rng.uniform(-0.1, 0.1), 0.05, z, (0.035, depth + 0.01, height + 0.01), m["strap"])
    wall_box("StowageTag", side, y - along * 0.25, 0.05 + depth + 0.001, z + height * 0.2, (0.08, 0.002, 0.05), m["label"])


def payload(side, y, z, seed):
    """An experiment's black box on the racks, with a row of status lights and a cable out of it."""
    m = mats()
    rng = random.Random(seed)
    wall_box("Payload", side, y, 0.05, z, (0.42, 0.12, 0.26), m["dark"], bevel=0.008)
    for i in range(4):
        lit = material("StatusLight", (0.02, 0.02, 0.02), 0.4, emission=rng.choice(((0.1, 1, 0.2), (0.1, 1, 0.2), (1, 0.6, 0.05), (0.2, 0.5, 1))), strength=4)
        wall_box("PayloadLight", side, y - 0.15 + i * 0.035, 0.171, z + 0.08, (0.012, 0.004, 0.012), lit)
    wall_box("PayloadPanel", side, y + 0.08, 0.171, z - 0.02, (0.18, 0.004, 0.1), m["rack_gray"])
    curve("PayloadCable", [Vector(on_wall(side, y + 0.2, 0.12, z - 0.1)), Vector(on_wall(side, y + 0.32, 0.22, z - 0.3)),
                           Vector(on_wall(side, y + 0.25, 0.1, z - 0.5))], 0.006, m["cable"])


def build_racks():
    m = mats()
    for side in (-1, 1):
        for i, y in enumerate((-1.95, -0.75, 0.45, 1.65)):
            rack(side, y, 1.12, seed=side * 10 + i)
        # The posts between the racks.
        for y in (-2.51, -1.35, -0.15, 1.05, 2.25):
            wall_box("RackPost", side, y, 0, CEILING / 2, (0.06, 0.07, CEILING - 2 * CORNER), m["rack_gray"])
        handrail("WallRail", on_wall(side, -2.2, 0, 1.95), on_wall(side, 2.1, 0, 1.95), up=(-side, 0, 0))
        handrail("WallRailLow", on_wall(side, -1.2, 0, 0.55), on_wall(side, 0.2, 0, 0.55), up=(-side, 0, 0))
    # What's stowed on the racks, kept clear of the boards, laptops and the ham station.
    stowage(-1, -1.9, 0.75, (0.5, 0.18, 0.34), m["bag"], 1)
    stowage(-1, -1.75, 1.3, (0.38, 0.14, 0.28), m["bag_blue"], 2)
    stowage(-1, 1.95, 0.7, (0.44, 0.16, 0.3), m["bag"], 3)
    stowage(1, 2.0, 0.72, (0.4, 0.16, 0.32), m["bag_blue"], 4)
    stowage(1, -2.0, 1.55, (0.46, 0.16, 0.3), m["bag"], 5)
    stowage(1, 0.62, 0.72, (0.6, 0.15, 0.28), m["bag"], 6)
    payload(-1, 0.1, 0.72, 7)
    payload(1, -1.9, 0.8, 8)
    # Cargo bags bundled behind the seat, on the deck and strapped to the back racks.
    bags = [((-1.5, -2.1, 0.2), (0.5, 0.42, 0.4), "bag"), ((-1.45, -2.08, 0.6), (0.45, 0.4, 0.34), "bag"),
            ((-0.95, -2.2, 0.17), (0.4, 0.35, 0.34), "bag_blue"), ((1.55, -2.15, 0.22), (0.5, 0.4, 0.44), "bag")]
    for location, size, kind in bags:
        bag = box("CargoBag", size, location, m[kind], rotation=(0, 0, random.Random(location[0]).uniform(-0.1, 0.1)), bevel=0.04)
        box("BagStrap", (size[0] + 0.01, 0.04, size[2] + 0.01), location, m["strap"], rotation=bag.rotation_euler)
    box("BungeeL", (0.012, 0.012, 1.2), (-1.5, -2.36, 0.75), m["yellow"], rotation=(0, 1.3, 0))


# MARK: - Boards, laptops and the ham station

def board(board_id, spec, frame_mat):
    """A whiteboard or print strapped to the racks in a thin dark frame, lit as bright as the panel
    the app draws over it."""
    side, y, width, height = spec
    m = mats()
    wall_box("BoardFrame", side, y, 0.05, BOARD_Z, (width + 0.05, 0.02, height + 0.05), frame_mat)
    face = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25) if board_id != "traceRoute" \
        else material("Print", (0.86, 0.85, 0.82), 0.85)
    surface = plane("Board" + board_id, width, height, on_wall(side, y, 0.072, BOARD_Z), facing(side), face)
    anchor(board_id, surface, width, height)
    # Velcro straps over the top corners.
    for du in (-1, 1):
        wall_box("BoardStrap", side, y + du * (width / 2 - 0.04), 0.076, BOARD_Z + height / 2 + 0.01, (0.035, 0.008, 0.12), m["velcro"])
    light("BoardLight", "AREA", on_wall(side, y, 0.9, BOARD_Z + 0.75), 2.6, (1.0, 0.98, 0.95), size=width - 0.2, size_y=0.3,
          target=on_wall(side, y, 0, BOARD_Z + 0.05))


def laptop(side, y, z, screen, yaw):
    """A laptop on a swing arm off the racks, its screen tipped toward the seat."""
    m = mats()
    base = Vector(on_wall(side, y, 0.06, z))
    arm_end = base + Vector((-side * 0.32, 0, 0))
    cylinder("LaptopArm", 0.018, base, arm_end, m["frame"], segments=12)
    box("LaptopArmMount", (0.05, 0.12, 0.12), base, m["frame"])
    turn = Matrix.Rotation(yaw, 4, "Z")
    keyboard = box("LaptopBase", (0.34, 0.24, 0.022), arm_end + Vector((0, 0, 0.0)), m["dark"], bevel=0.004)
    keyboard.matrix_world = Matrix.Translation(arm_end) @ turn
    hinge = arm_end + turn.to_3x3() @ Vector((0, 0.11, 0.01))
    tilt = Matrix.Rotation(math.radians(-14), 4, "X")
    lid = box("LaptopLid", (0.34, 0.012, 0.23), (0, 0, 0), m["dark"], bevel=0.004)
    lid.matrix_world = Matrix.Translation(hinge) @ turn @ tilt @ Matrix.Translation((0, 0, 0.115))
    shown = plane("LaptopScreen", 0.31, 0.19, (0, 0, 0), (0, 0, 0), glowing("LaptopScreen", os.path.join(CACHE, screen), 1.6))
    shown.matrix_world = Matrix.Translation(hinge) @ turn @ tilt @ Matrix.Translation((0, -0.0075, 0.118)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    # The power cable floats down in a loose loop to the racks.
    start = arm_end + Vector((0, -0.08, -0.02))
    curve("LaptopCable", [start, start + Vector((side * 0.05, -0.1, -0.25)), Vector(on_wall(side, y - 0.2, 0.15, z - 0.45)),
                          Vector(on_wall(side, y - 0.25, 0.05, z - 0.3))], 0.004, m["cable"])


def place_model(file_name, location, normal_side):
    """One of the app's device models at real size, standing up against the right or left racks."""
    path = os.path.abspath(os.path.join(DEVICE_MODELS, file_name))
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [obj for obj in bpy.data.objects if obj not in before]
    root = next(obj for obj in new if obj.parent is None)
    # The importer leaves the models facing -Y with Z up; turn this one to face the seat from the wall.
    root.matrix_world = Matrix.Rotation(normal_side * math.pi / 2, 4, "Z") @ root.matrix_world
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(corner) for obj in new if obj.type == "MESH" for corner in obj.bound_box]
    center = Vector((
        (min(c.x for c in corners) + max(c.x for c in corners)) / 2,
        (min(c.y for c in corners) + max(c.y for c in corners)) / 2,
        (min(c.z for c in corners) + max(c.z for c in corners)) / 2,
    ))
    depth = (max(c.x for c in corners) - min(c.x for c in corners)) / 2
    target = Vector(location) + Vector((-normal_side * depth, 0, 0))
    root.matrix_world = Matrix.Translation(target - center) @ root.matrix_world
    return max(c.z for c in corners) - min(c.z for c in corners)


def ham_station():
    """The station's amateur radio: a placard, the radio and its display, a hand mic on its cord and a
    headset, all on the right racks behind the print, with a Meshtastic radio strapped beside it."""
    m = mats()
    side, y = 1, -1.0
    placard = plane("Placard", 0.5, 0.25, on_wall(side, y, 0.06, 1.72), facing(side), image_material("Placard", os.path.join(CACHE, "space_placard.png"), 0.6))
    placard.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    wall_box("Radio", side, y, 0.05, 1.32, (0.24, 0.2, 0.08), m["dark"])
    plane("RadioDisplay", 0.12, 0.04, on_wall(side, y - 0.03, 0.252, 1.335), facing(side), glowing("RadioDisplay", os.path.join(CACHE, "space_radio.png"), 2.5))
    for i in range(3):
        cylinder("RadioKnob", 0.012, on_wall(side, y + 0.06 + i * 0.025, 0.25, 1.31), on_wall(side, y + 0.06 + i * 0.025, 0.27, 1.31), m["frame"], segments=12)
    wall_box("RadioVelcro", side, y, 0.045, 1.32, (0.28, 0.006, 0.05), m["velcro"])
    # The hand mic, floating on its coiled cord.
    mic = Vector(on_wall(side, y + 0.22, 0.32, 1.12))
    box("HandMic", (0.04, 0.05, 0.1), mic, m["dark"], rotation=(0.3, 0.2, 0), bevel=0.01)
    points = [Vector(on_wall(side, y + 0.1, 0.25, 1.3))]
    for i in range(1, 14):
        t = i / 14
        a = i * 2.2
        base = points[0].lerp(mic, t)
        points.append(base + Vector((0.012 * math.cos(a), 0.012 * math.sin(a), 0.012 * math.cos(a))))
    points.append(mic + Vector((0, 0, 0.05)))
    curve("MicCord", points, 0.003, m["cable"])
    # A headset hung by its band from a strap.
    center = Vector(on_wall(side, y - 0.22, 0.12, 1.25))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.08, minor_radius=0.007, location=center, rotation=(0, math.pi / 2, 0))
    band = bpy.context.active_object
    band.data.materials.append(m["dark"])
    for du in (-1, 1):
        cylinder("EarCup", 0.04, center + Vector((0, du * 0.08, -0.04)) + Vector((-0.012, 0, 0)), center + Vector((0, du * 0.08, -0.04)) + Vector((0.012, 0, 0)), m["dark"], segments=24)

    # A Meshtastic radio held to the racks by a velcro strap, past the station.
    height = place_model("t-echo.usdz", on_wall(side, y - 0.5, 0.06, 1.35), -1)
    wall_box("RadioStrap", side, y - 0.5, 0.06, 1.35 - height * 0.15, (0.12, 0.03, 0.03), m["strap"])
    wall_box("RadioStrapPad", side, y - 0.5, 0.045, 1.35, (0.14, 0.008, 0.16), m["velcro"])


def back_wall():
    """The hatch to the next module, with the mission patch above it and Chirpy's poster beside it."""
    m = mats()
    y = -BACK
    frame = box("HatchFrame", (1.14, 0.06, 1.14), (0, y + 0.03, 1.02), m["frame"], bevel=0.06)
    door = box("Hatch", (1.0, 0.08, 1.0), (0, y + 0.06, 1.02), m["rack_light"], bevel=0.06)
    door.name = "Hatch"
    frame.name = "HatchFrame"
    cylinder("HatchWindow", 0.09, (0, y + 0.09, 1.25), (0, y + 0.11, 1.25), m["dark"], segments=32)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.1, minor_radius=0.012, location=(0, y + 0.11, 1.25), rotation=(math.pi / 2, 0, 0))
    bpy.context.active_object.data.materials.append(m["frame"])
    box("HatchHandle", (0.32, 0.06, 0.05), (0, y + 0.13, 0.86), m["frame"], bevel=0.01)
    for x in (-0.16, 0.16):
        box("HatchHandlePost", (0.03, 0.06, 0.03), (x, y + 0.11, 0.86), m["frame"])
    for x in (-0.6, 0.6):
        box("HatchLatch", (0.05, 0.05, 0.16), (x, y + 0.09, 1.02), m["yellow"], bevel=0.008)
    patch = image_material("Patch", os.path.join(CACHE, "space_patch.png"), 0.8)
    nodes, links = patch.node_tree.nodes, patch.node_tree.links
    tex = next(node for node in nodes if node.type == "TEX_IMAGE")
    links.new(tex.outputs["Alpha"], nodes["Principled BSDF"].inputs["Alpha"])
    # Between the hatch frame's top (1.59 m) and the light fixture overhead, so the whole patch
    # shows when the viewer looks back.
    plane("Patch", 0.3, 0.3, (0, y + 0.105, 1.755), (math.pi / 2, 0, math.pi), patch)
    poster = image_material("Chirpy", os.path.join(CACHE, "chirpy_poster.png"), 0.6)
    plane("Chirpy", 0.42, 0.59, (1.0, y + 0.105, 1.3), (math.pi / 2, 0, math.pi), poster)
    for dx, dz in ((-0.19, 0.27), (0.19, 0.27), (-0.19, -0.27), (0.19, -0.27)):
        box("Tape", (0.06, 0.004, 0.03), (1.0 + dx, y + 0.108, 1.3 + dz), material("Tape", (0.75, 0.72, 0.6), 0.6))
    handrail("HatchRail", (-0.75, y, 0.55), (-0.75, y, 1.5), up=(0, 1, 0))
    handrail("HatchRail", (0.75, y, 0.55), (0.75, y, 1.15), up=(0, 1, 0))


def front_wall():
    """The plain closeout panels the screen hangs on, seamed and with a strip of handrail under them."""
    m = mats()
    y = FRONT - 0.005
    for x in (-1.15, 1.15):
        box("FrontSeam", (0.01, 0.004, CEILING - 0.3), (x, y, CEILING / 2), m["dark"])
    box("FrontSeamLow", (2 * HALF - 0.8, 0.004, 0.01), (0, y, 0.45), m["dark"])
    handrail("FrontRail", (-0.9, FRONT, 0.3), (0.9, FRONT, 0.3), up=(0, -1, 0))
    for x in (-1.75, 1.75):
        box("FrontVelcro", (0.1, 0.006, 0.06), (x, y - 0.003, 1.5), m["velcro"])


def overhead_and_corners():
    """Vents and stowage on the overhead, and the emergency kit at the front corners: a fire
    extinguisher and a breathing mask's bag, under their red labels."""
    m = mats()
    for x in (-1.3, 1.3):
        box("Vent", (0.3, 0.3, 0.02), (x, -1.7, CEILING - 0.01), m["rack_gray"])
        for i in range(6):
            box("VentSlat", (0.26, 0.012, 0.015), (x, -1.82 + i * 0.048, CEILING - 0.022), m["dark"])
    for x, mat in ((-0.7, m["bag"]), (0.0, m["bag"]), (0.7, m["bag_blue"])):
        box("OverheadBag", (0.5, 0.38, 0.2), (x, -2.05, CEILING - 0.1), mat, bevel=0.04)
    box("OverheadNet", (1.9, 0.02, 0.24), (0, -1.85, CEILING - 0.11), m["strap"])
    red = material("Red", (0.7, 0.06, 0.04), 0.5)
    for side in (-1, 1):
        p = Vector(on_wall(side, 2.3, 0.09, 1.25))
        if side < 0:
            cylinder("Extinguisher", 0.07, p + Vector((0, 0, -0.25)), p + Vector((0, 0, 0.22)), m["rack_gray"], segments=24)
            cylinder("ExtinguisherNozzle", 0.025, p + Vector((0, 0, 0.22)), p + Vector((0, 0, 0.32)), m["dark"], segments=12)
            wall_box("ExtinguisherBand", side, 2.3, 0.02, 1.25, (0.18, 0.15, 0.06), red)
        else:
            wall_box("MaskBag", side, 2.3, 0.04, 1.2, (0.2, 0.12, 0.3), red, bevel=0.03)
        wall_box("EmergencyLabel", side, 2.3, 0.01, 1.62, (0.22, 0.004, 0.07), red)


def floating_things():
    """A few things adrift: a cable loop, a pen and a cloth bag on a tether, near the walls."""
    m = mats()
    curve("Cable", [Vector((-2.05, 1.95, 1.75)), Vector((-1.85, 2.1, 1.55)), Vector((-1.95, 2.2, 1.3)), Vector((-2.2, 2.25, 1.45))], 0.005, m["cable_gray"])
    cylinder("Pen", 0.006, (1.75, 1.9, 1.62), (1.83, 1.95, 1.7), m["handrail"], segments=8)
    bag = box("DriftBag", (0.22, 0.14, 0.16), (1.9, -1.9, 1.6), m["bag_blue"], rotation=(0.3, 0.4, 0.2), bevel=0.04)
    curve("Tether", [Vector((2.25, -1.85, 1.75)), Vector((2.1, -1.9, 1.7)), Vector(bag.location)], 0.002, m["yellow"])


# MARK: - The cupola

def hex_point(radius, azimuth):
    """The point on a hexagon with corners `radius` out, whose flat sides face the front and back,
    in the direction `azimuth` radians clockwise from the front."""
    apothem = radius * math.cos(math.pi / 6)
    nearest = round(azimuth / (math.pi / 3)) * (math.pi / 3)
    r = apothem / math.cos(azimuth - nearest)
    return Vector((r * math.sin(azimuth), r * math.cos(azimuth), 0))


def ring(name, inner, outer, z_inner, z_outer, mat, segments=96):
    """A band between two closed outlines, each a function of the azimuth."""
    def build(bm):
        a = [bm.verts.new(inner(i / segments * 2 * math.pi) + Vector((0, 0, z_inner))) for i in range(segments)]
        b = [bm.verts.new(outer(i / segments * 2 * math.pi) + Vector((0, 0, z_outer))) for i in range(segments)]
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    obj = mesh_object(name, build, mat, (0, CUPOLA_Y, 0))
    obj.data.materials[0].use_backface_culling = False
    smooth(obj)
    return obj


def quad_frame(name, outer, inner, mat, depth):
    """A frame between an outer and an inner quad, with a sleeve `depth` deep through the inner
    one along the outward normal: one of the cupola's window frames."""
    normal = (outer[1] - outer[0]).cross(outer[3] - outer[0]).normalized()
    outward = normal if normal.z > 0 or normal.dot(sum(outer, Vector()) / 4 - Vector((0, CUPOLA_Y, 0))) > 0 else -normal

    def build(bm):
        o = [bm.verts.new(v) for v in outer]
        n = [bm.verts.new(v) for v in inner]
        s = [bm.verts.new(v + outward * depth) for v in inner]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((o[i], o[j], n[j], n[i]))
            bm.faces.new((n[i], n[j], s[j], s[i]))
    obj = mesh_object(name, build, mat)
    obj.data.materials[0].use_backface_culling = False
    modifier = obj.modifiers.new("Thick", "SOLIDIFY")
    modifier.thickness = 0.02
    return obj, outward


def build_cupola():
    m = mats()
    frame = panel_material("CupolaFrame", (0.7, 0.7, 0.68), 0.45)
    metal = m["frame"]
    center = Vector((0, CUPOLA_Y, 0))
    # The throat up from the ceiling, then the flat ring out to the bottom of the windows.
    ring("Throat", lambda a: Vector((THROAT * math.sin(a), THROAT * math.cos(a), 0)),
         lambda a: Vector((THROAT * math.sin(a), THROAT * math.cos(a), 0)), CEILING, THROAT_TOP, m["rack_gray"])
    ring("CupolaFloor", lambda a: Vector((THROAT * math.sin(a), THROAT * math.cos(a), 0)), lambda a: hex_point(BASE, a), THROAT_TOP, THROAT_TOP, frame)
    bpy.ops.mesh.primitive_torus_add(major_radius=THROAT, minor_radius=0.03, location=(0, CUPOLA_Y, CEILING), major_segments=96)
    bpy.context.active_object.data.materials.append(metal)

    # The six trapezoid windows.
    for k in range(6):
        a0, a1 = (k - 0.5) * math.pi / 3, (k + 0.5) * math.pi / 3
        corners = [hex_point(BASE, a0 + 1e-6) + Vector((0, 0, THROAT_TOP)), hex_point(BASE, a1 - 1e-6) + Vector((0, 0, THROAT_TOP)),
                   hex_point(TOP, a1 - 1e-6) + Vector((0, 0, TOP_Z)), hex_point(TOP, a0 + 1e-6) + Vector((0, 0, TOP_Z))]
        corners = [c + center for c in corners]
        mid = sum(corners, Vector()) / 4
        inner = []
        for c in corners:
            toward = (mid - c)
            inner.append(c + toward.normalized() * MULLION * 1.4)
        _, outward = quad_frame("WindowFrame", corners, inner, frame, 0.14)
        glass = mesh_object("WindowGlass", lambda bm, inner=inner, outward=outward: bm.faces.new([bm.verts.new(v + outward * 0.1) for v in inner]), m["glass"])
        glass.data.materials[0].use_backface_culling = False
        # A handle on the frame under each window, and the seal round the glass.
        bottom = (inner[0] + inner[1]) / 2 - outward * 0.0 + (corners[0] + corners[1] - inner[0] - inner[1]) / 4
        cylinder("WindowHandle", 0.012, bottom + (inner[0] - inner[1]) * 0.2 - outward * 0.04, bottom - (inner[0] - inner[1]) * 0.2 - outward * 0.04, metal, segments=10)
        for i in range(4):
            cylinder("WindowSeal", 0.008, inner[i] + outward * 0.1, inner[(i + 1) % 4] + outward * 0.1, m["dark"], segments=8)

    # The top: a flat hexagon with the round window in it, recessed in a sleeve.
    top = Vector((0, 0, TOP_Z))
    ring("CupolaTop", lambda a: Vector((ROUND_WINDOW * math.sin(a), ROUND_WINDOW * math.cos(a), 0)), lambda a: hex_point(TOP, a), TOP_Z, TOP_Z, frame)
    ring("RoundSleeve", lambda a: Vector((ROUND_WINDOW * math.sin(a), ROUND_WINDOW * math.cos(a), 0)),
         lambda a: Vector((ROUND_WINDOW * math.sin(a), ROUND_WINDOW * math.cos(a), 0)), TOP_Z, TOP_Z + 0.16, metal)

    def disc(bm):
        verts = [bm.verts.new((ROUND_WINDOW * math.sin(i / 64 * 2 * math.pi), ROUND_WINDOW * math.cos(i / 64 * 2 * math.pi), 0)) for i in range(64)]
        bm.faces.new(verts)
    glass = mesh_object("RoundGlass", disc, m["glass"], center + top + Vector((0, 0, 0.14)))
    glass.data.materials[0].use_backface_culling = False
    bpy.ops.mesh.primitive_torus_add(major_radius=ROUND_WINDOW, minor_radius=0.012, location=center + top + Vector((0, 0, 0.005)), major_segments=64)
    bpy.context.active_object.data.materials.append(metal)
    # Handrails round the cupola's floor ring, and the robotic workstation's hand controllers.
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        p = center + Vector((math.sin(a), math.cos(a), 0)) * (THROAT - 0.08) + Vector((0, 0, CEILING + 0.02))
        q = center + Vector((math.sin(a + 0.5), math.cos(a + 0.5), 0)) * (THROAT - 0.08) + Vector((0, 0, CEILING + 0.02))
        if k in (1, 4):
            handrail("CupolaRail", p, q, up=(0, 0, -1))

    # Earthshine: the light of the sunlit ground through the cupola, from where the view puts it.
    toward = earth_direction()
    glow_at = center + Vector((0, 0, TOP_Z - 0.1)) + toward * 0.2
    light("Earthshine", "AREA", glow_at, 70, (0.72, 0.82, 1.0), size=1.4, target=glow_at - toward * 3)
    light("EarthFill", "AREA", center + Vector((0, 0, THROAT_TOP)), 20, (0.75, 0.85, 1.0), size=2.0, target=center)


def build():
    build_shell()
    deck_details()
    build_racks()
    front_wall()
    back_wall()
    build_cupola()
    board("teamStatus", ROSTER, mats()["dark"])
    board("nodeStatus", STATUS, mats()["dark"])
    board("traceRoute", TRACE, mats()["dark"])
    laptop(-1, 1.75, 1.25, "space_checklist.png", math.radians(49))
    laptop(1, 1.7, 1.3, "space_ground_track.png", math.radians(-49))
    ham_station()
    floating_things()
    overhead_and_corners()
    # On the front bulkhead's plain panels, under the ceiling, with the cupola above it.
    screen_anchor((0, FRONT - 0.03, EYE_HEIGHT + 0.16), (math.pi / 2, 0, 0), width=1.9)


# Lit only by the module's own lights and the light through the cupola; the app paints Earth and
# space (space_earth.py) behind the windows.
render_room(build, None, cutout=True)

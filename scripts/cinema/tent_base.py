#
#  tent_base.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/24/26.
#
#  The parts of a cinema tent that every tent environment shares: the canvas shell with its clear
#  vinyl windows, the floor, the string lights, the Meshtastic branding, the dusk forest outside,
#  the seated camera, the render settings, and the anchors file the app places its live panels
#  from. An environment script (sar_tent.py) imports this, adds its own furnishings, and calls
#  render(). See README.md.
#
#  Blender's +Y is the image's center: the front wall, left plain for the app window. +X is the
#  viewer's right, Z is up, and the viewer sits at the origin.

import json
import math
import os
import sys
from dataclasses import dataclass, field

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    options = {"out": os.path.join(HERE, "out", "tent.png"), "width": 2048, "samples": 64, "blend": None}
    for i in range(0, len(argv) - 1, 2):
        key = argv[i].lstrip("-")
        options[key] = argv[i + 1]
    options["width"] = int(options["width"])
    options["samples"] = int(options["samples"])
    return options


# MARK: - Tent dimensions (meters)

# 5.6 m square, with the viewer in the middle, so every wall is about 2.8 m away.
HALF_WIDTH = 2.8
BACK_Y = -2.8
FRONT_Y = 2.8
WALL_HEIGHT = 1.95
RIDGE_HEIGHT = 3.0
DOOR = (-0.6, 0.9, 1.85)  # right wall: from y, to y, top
# Frame tents have wide bays; these leave room for a full-size window between two legs in the
# back and front bays, and for the door and the plaque in the middle one.
RAFTERS = [-2.8, -0.8, 1.2, 2.8]
EYE_HEIGHT = 1.15


@dataclass
class WallSpot:
    """A rectangle on a side wall: `side` is -1 for the left wall, +1 for the right. Keep spots
    between two rafters, clear of the door."""
    side: int
    y: float
    z: float
    width: float
    height: float
    # Windows only: how strongly the vinyl reflects the room, 1 for the usual amount. A window that
    # faces a brightly lit stretch of wall needs less, or the reflection hides the forest.
    shine: float = 1.0


@dataclass
class BackSpot:
    """A rectangle on the back wall, centered at `x` (+X is the viewer's right)."""
    x: float
    z: float
    width: float
    height: float


@dataclass
class Layout:
    """Where the windows and the branding go. The defaults suit the search and rescue tent; another
    environment passes its own to fit its furniture, and None leaves an item out. The front wall
    is never used, and nothing should cover a board the app draws on."""
    # High on the wall, up under the eave, as frame-tent windows are. Sizes are the clear vinyl.
    windows: list = field(default_factory=lambda: [
        WallSpot(side=1, y=-1.8, z=1.34, width=1.36, height=0.8, shine=0.5),
        WallSpot(side=-1, y=-1.8, z=1.34, width=1.3, height=0.8, shine=0.5),
    ])
    # The banner hangs on the back wall: center x, center z, width, height.
    banner: tuple = (0.0, 1.62, 2.0, 1.0)
    # Chirpy, on the back wall to the left of the banner, centered between the banner's end and the
    # back corner as seen from the seat, above the radio table and clear of the left window.
    poster: BackSpot = field(default_factory=lambda: BackSpot(x=-1.78, z=1.45, width=0.5, height=0.7))
    # Big enough that its small top line reads from the seat. In the middle of the left wall's
    # middle bay.
    plaque: WallSpot = field(default_factory=lambda: WallSpot(side=-1, y=0.2, z=1.42, width=1.26, height=0.62))


# Surfaces the app covers with live panels, by the id the app knows them by. Filled in as the
# scene is built, written out by write_anchors().
ANCHORS = {}


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


def image_material(name, path, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
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


def torus(name, major, minor, location, mat, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=10, location=location, rotation=rotation)
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


def facing_in(side):
    """The rotation that turns a plane() to lie on a side wall, its face toward the room and its
    image upright."""
    return (math.pi / 2, 0, -side * math.pi / 2)


def sag(y):
    """How far a side wall's canvas bows into the tent at `y`: nothing at a rafter, most midway."""
    nearest = min(abs(y - r) for r in RAFTERS)
    return 0.04 * math.sin(min(nearest / 0.75, 1) * math.pi / 2)


def anchor(board_id, obj, width, height):
    """Records a plane of the given mesh size as a board the app draws on. The plane's +X is the
    board's right and its +Z faces the viewer. write_anchors() reads where it ends up."""
    ANCHORS[board_id] = (obj, width, height)


def screen_anchor():
    """The app's screen on the plain front wall (the "screen" anchor): an anchor only, nothing is
    drawn. 2.6 m wide in the screen's shape, just off the wall, its center a little above the eye.
    The gable carries the wall up past the eave in the middle, so the top can sit above the eave
    line."""
    width = 2.6
    height = width * 940 / 1500
    surface = plane("Screen", width, height, (0, FRONT_Y - 0.1, EYE_HEIGHT + 0.2), (math.pi / 2, 0, 0), None)
    surface.hide_render = True
    anchor("screen", surface, width, height)


def write_anchors(out, camera):
    """Writes each board's place relative to the camera, in the camera's own axes, which are
    RealityKit's: +X right, +Y up, -Z toward the image's center."""
    bpy.context.view_layer.update()
    to_camera = camera.matrix_world.to_3x3().normalized().inverted()
    eye = camera.matrix_world.translation
    boards = {}
    for board_id, (obj, width, height) in ANCHORS.items():
        world = obj.matrix_world
        right = world.to_3x3() @ Vector((1, 0, 0))
        up = world.to_3x3() @ Vector((0, 1, 0))
        normal = world.to_3x3() @ Vector((0, 0, 1))
        boards[board_id] = {
            "center": rounded(to_camera @ (world.translation - eye)),
            "size": [round(width * right.length, 4), round(height * up.length, 4)],
            "right": rounded(to_camera @ right.normalized()),
            "normal": rounded(to_camera @ normal.normalized()),
        }
    path = os.path.splitext(out)[0] + "_anchors.json"
    data = {
        "comment": "Written by scripts/cinema/tent_base.py. Meters, RealityKit axes (+X right, +Y up, "
                   "-Z toward the image's center), relative to the camera the image was rendered from.",
        "eyeHeight": round(eye.z, 4),
        "boards": boards,
    }
    with open(path, "w") as file:
        json.dump(data, file, indent=2, sort_keys=True)
        file.write("\n")
    print("wrote", path)


def rounded(v):
    return [round(v.x, 4) + 0.0, round(v.y, 4) + 0.0, round(v.z, 4) + 0.0]


# MARK: - Materials

class Nodes:
    """Small wrapper for building math in a node tree."""

    def __init__(self, tree):
        self.nodes, self.links = tree.nodes, tree.links

    def math(self, operation, a, b=0.0):
        node = self.nodes.new("ShaderNodeMath")
        node.operation = operation
        for socket, value in zip(node.inputs, (a, b)):
            if isinstance(value, (int, float)):
                socket.default_value = value
            else:
                self.links.new(value, socket)
        return node.outputs[0]

    def mix(self, fac, a, b):
        node = self.nodes.new("ShaderNodeMixShader")
        self.links.new(fac, node.inputs["Fac"])
        self.links.new(a, node.inputs[1])
        self.links.new(b, node.inputs[2])
        return node.outputs["Shader"]


def principled(nodes, color, roughness):
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return bsdf


def canvas_material(windows):
    """The tent's canvas. Each window in `windows` is cut into it as clear vinyl with a stitched
    binding round it, worked out from the object's coordinates so it follows the canvas's sag."""
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
    glow = nodes.new("ShaderNodeMixShader")
    glow.inputs["Fac"].default_value = 0.12
    links.new(bsdf.outputs["BSDF"], glow.inputs[1])
    links.new(translucent.outputs["BSDF"], glow.inputs[2])
    shader = glow.outputs["Shader"]

    if windows:
        n = Nodes(mat.node_tree)
        xyz = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], xyz.inputs[0])
        x, y, z = xyz.outputs["X"], xyz.outputs["Y"], xyz.outputs["Z"]
        band_width = 0.04
        inside = band = stitch = shine = None
        # Short stitches along the binding: y runs along its top and bottom, z up its sides.
        dash = n.math("LESS_THAN", n.math("FRACT", n.math("MULTIPLY", n.math("ADD", y, z), 90)), 0.6)
        for window in windows:
            on_wall = n.math("GREATER_THAN", n.math("MULTIPLY", x, window.side), HALF_WIDTH - 0.2)
            dy = n.math("SUBTRACT", n.math("ABSOLUTE", n.math("SUBTRACT", y, window.y)), window.width / 2)
            dz = n.math("SUBTRACT", n.math("ABSOLUTE", n.math("SUBTRACT", z, window.z)), window.height / 2)
            # Distance outside the window's edge; negative inside it.
            d = n.math("MAXIMUM", dy, dz)
            this_inside = n.math("MULTIPLY", n.math("LESS_THAN", d, 0), on_wall)
            this_band = n.math("MULTIPLY", n.math("MULTIPLY", n.math("GREATER_THAN", d, -0.0001), n.math("LESS_THAN", d, band_width)), on_wall)
            # One row of stitches along the middle of the binding.
            row = n.math("LESS_THAN", n.math("ABSOLUTE", n.math("SUBTRACT", d, band_width / 2)), 0.0018)
            this_stitch = n.math("MULTIPLY", n.math("MULTIPLY", row, dash), this_band)
            inside = this_inside if inside is None else n.math("MAXIMUM", inside, this_inside)
            this_shine = n.math("MULTIPLY", this_inside, window.shine)
            shine = this_shine if shine is None else n.math("MAXIMUM", shine, this_shine)
            band = this_band if band is None else n.math("MAXIMUM", band, this_band)
            stitch = this_stitch if stitch is None else n.math("MAXIMUM", stitch, this_stitch)
        # Binding: webbing a shade darker than the canvas, sewn round the vinyl, with a slight
        # ridge so it reads as a folded edge.
        binding = principled(nodes, (0.21, 0.18, 0.12), 0.85)
        ridge = nodes.new("ShaderNodeBump")
        ridge.inputs["Strength"].default_value = 0.6
        ridge.inputs["Distance"].default_value = 0.004
        links.new(band, ridge.inputs["Height"])
        links.new(ridge.outputs["Normal"], binding.inputs["Normal"])
        thread = principled(nodes, (0.27, 0.24, 0.17), 0.85)
        # Clear vinyl. Mostly see-through, with a little milky haze, and a soft sheen that picks
        # up the string lights. A slow ripple in the sheet bends the reflections.
        ripple = nodes.new("ShaderNodeTexNoise")
        ripple.inputs["Scale"].default_value = 2.2
        ripple.inputs["Detail"].default_value = 2
        # The sheet hangs in long, shallow waves across it, which tip it up and down enough to
        # catch the string lights overhead.
        stretch = nodes.new("ShaderNodeMapping")
        stretch.inputs["Scale"].default_value = (1, 0.7, 2.6)
        links.new(coords.outputs["Object"], stretch.inputs["Vector"])
        links.new(stretch.outputs["Vector"], ripple.inputs["Vector"])
        wobble = nodes.new("ShaderNodeBump")
        wobble.inputs["Strength"].default_value = 1.0
        wobble.inputs["Distance"].default_value = 0.015
        links.new(ripple.outputs["Fac"], wobble.inputs["Height"])
        # And it leans back a little toward the top, as slack vinyl does with its bottom edge
        # pulled in, so it faces up toward the lights rather than straight across the tent.
        bow = nodes.new("ShaderNodeBump")
        bow.inputs["Strength"].default_value = 1.0
        bow.inputs["Distance"].default_value = 0.15
        links.new(n.math("MULTIPLY", z, -1), bow.inputs["Height"])
        links.new(wobble.outputs["Normal"], bow.inputs["Normal"])
        wobble = bow
        clear = nodes.new("ShaderNodeBsdfTransparent")
        clear.inputs["Color"].default_value = (1.2, 1.2, 1.15, 1)
        # The haze scatters the evening light coming through as well as the light inside.
        haze_lit = principled(nodes, (0.8, 0.79, 0.75), 0.9)
        haze_glow = nodes.new("ShaderNodeBsdfTranslucent")
        haze_glow.inputs["Color"].default_value = (0.85, 0.8, 0.7, 1)
        haze = nodes.new("ShaderNodeMixShader")
        haze.inputs["Fac"].default_value = 0.5
        links.new(haze_lit.outputs["BSDF"], haze.inputs[1])
        links.new(haze_glow.outputs["BSDF"], haze.inputs[2])
        # And a little dusk sky caught in it, so a window never goes dark on the forest's dim side.
        sky = nodes.new("ShaderNodeEmission")
        sky.inputs["Color"].default_value = (0.75, 0.68, 0.56, 1)
        sky.inputs["Strength"].default_value = 0.3
        glowing = nodes.new("ShaderNodeAddShader")
        links.new(haze.outputs["Shader"], glowing.inputs[0])
        links.new(sky.outputs["Emission"], glowing.inputs[1])
        sheen = nodes.new("ShaderNodeBsdfGlossy")
        sheen.inputs["Roughness"].default_value = 0.18
        links.new(wobble.outputs["Normal"], sheen.inputs["Normal"])
        fresnel = nodes.new("ShaderNodeFresnel")
        fresnel.inputs["IOR"].default_value = 1.5
        links.new(wobble.outputs["Normal"], fresnel.inputs["Normal"])
        # Haze thickens a little in patches, as on old vinyl.
        cloud = nodes.new("ShaderNodeTexNoise")
        cloud.inputs["Scale"].default_value = 4
        links.new(coords.outputs["Object"], cloud.inputs["Vector"])
        hazy = n.math("ADD", 0.11, n.math("MULTIPLY", cloud.outputs["Fac"], 0.07))
        vinyl = n.mix(hazy, clear.outputs["BSDF"], glowing.outputs["Shader"])
        # Kept low, so only the string lights show clearly in it, as faint warm streaks.
        reflect = n.math("MULTIPLY", n.math("ADD", fresnel.outputs["Fac"], 0.08), shine)
        vinyl = n.mix(reflect, vinyl, sheen.outputs["BSDF"])
        shader = n.mix(band, shader, binding.outputs["BSDF"])
        shader = n.mix(stitch, shader, thread.outputs["BSDF"])
        shader = n.mix(inside, shader, vinyl)
    links.new(shader, output.inputs["Surface"])
    return mat


def floor_material():
    """A ripstop groundsheet: olive-tan panels with welded seams, a darker band where it turns up
    at the walls, and a little wear and dirt, worst by the door."""
    mat = bpy.data.materials.new("Floor")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    n = Nodes(mat.node_tree)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    geometry = nodes.new("ShaderNodeNewGeometry")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], xyz.inputs[0])
    x, y = xyz.outputs["X"], xyz.outputs["Y"]

    # Cloth: a soft mottle in the color, slightly lighter in worn patches.
    mottle = nodes.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 1.4
    mottle.inputs["Detail"].default_value = 6
    links.new(geometry.outputs["Position"], mottle.inputs["Vector"])
    cloth = nodes.new("ShaderNodeValToRGB")
    cloth.color_ramp.elements[0].color = (0.11, 0.105, 0.075, 1)
    cloth.color_ramp.elements[1].color = (0.20, 0.185, 0.13, 1)
    links.new(mottle.outputs["Fac"], cloth.inputs["Fac"])
    color = cloth.outputs["Color"]
    # Each panel was cut from a different roll and has faded differently.
    panel = n.math("FLOOR", n.math("DIVIDE", x, 1.4))
    tint = n.math("FRACT", n.math("MULTIPLY", n.math("SINE", n.math("MULTIPLY", panel, 12.9898)), 43758.55))
    shade = nodes.new("ShaderNodeMix")
    shade.data_type = "RGBA"
    shade.blend_type = "MULTIPLY"
    shade.inputs["Factor"].default_value = 1
    links.new(color, shade.inputs[6])
    value = nodes.new("ShaderNodeCombineXYZ")
    brightness = n.math("ADD", 0.86, n.math("MULTIPLY", tint, 0.24))
    for socket in ("X", "Y", "Z"):
        links.new(brightness, value.inputs[socket])
    links.new(value.outputs[0], shade.inputs[7])
    color = shade.outputs[2]

    def mix_color(fac, a, b):
        node = nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        links.new(fac, node.inputs["Factor"])
        for socket, value in ((node.inputs[6], a), (node.inputs[7], b)):
            if isinstance(value, tuple):
                socket.default_value = (*value, 1)
            else:
                links.new(value, socket)
        return node.outputs[2]

    wear = nodes.new("ShaderNodeTexNoise")
    wear.inputs["Scale"].default_value = 0.7
    wear.inputs["Detail"].default_value = 3
    links.new(geometry.outputs["Position"], wear.inputs["Vector"])
    scuff = nodes.new("ShaderNodeTexNoise")
    scuff.inputs["Scale"].default_value = 9
    scuff.inputs["Detail"].default_value = 4
    links.new(geometry.outputs["Position"], scuff.inputs["Vector"])
    worn = n.math("MINIMUM", 1, n.math("MAXIMUM", 0, n.math("MULTIPLY", n.math("SUBTRACT", wear.outputs["Fac"], 0.47), 4)))
    worn = n.math("MULTIPLY", n.math("MULTIPLY", worn, scuff.outputs["Fac"]), 0.9)
    color = mix_color(worn, color, (0.27, 0.25, 0.2))
    # Creases where the sheet was folded for packing.
    fold_x = n.math("ABSOLUTE", n.math("SUBTRACT", n.math("FRACT", n.math("DIVIDE", n.math("ADD", x, 0.25), 0.93)), 0.5))
    fold_y = n.math("ABSOLUTE", n.math("SUBTRACT", n.math("FRACT", n.math("DIVIDE", n.math("ADD", y, 0.4), 1.12)), 0.5))
    crease = n.math("MAXIMUM", n.math("GREATER_THAN", fold_x, 0.49), n.math("GREATER_THAN", fold_y, 0.492))
    # Pressed flat in places, so the creases come and go.
    crease = n.math("MULTIPLY", crease, n.math("GREATER_THAN", wear.outputs["Fac"], 0.42))
    color = mix_color(n.math("MULTIPLY", crease, 0.14), color, (0.28, 0.26, 0.2))
    # Dirt walked in at the door, on the right wall.
    door_from, door_to, _ = DOOR
    to_door = n.math("SUBTRACT", HALF_WIDTH, x)
    along = n.math("MAXIMUM", n.math("SUBTRACT", door_from, y), n.math("SUBTRACT", y, door_to))
    near_door = n.math("MULTIPLY", n.math("MAXIMUM", 0, n.math("SUBTRACT", 1, n.math("DIVIDE", to_door, 1.3))), n.math("LESS_THAN", along, 0.25))
    dirt = n.math("MULTIPLY", near_door, n.math("GREATER_THAN", scuff.outputs["Fac"], 0.5))
    color = mix_color(n.math("MULTIPLY", dirt, 0.6), color, (0.075, 0.06, 0.04))

    # The band round the edge, where the sheet turns up at the walls: a heavier, darker cloth.
    edge = n.math("MINIMUM", n.math("SUBTRACT", HALF_WIDTH, n.math("ABSOLUTE", x)),
                  n.math("MINIMUM", n.math("SUBTRACT", y, BACK_Y), n.math("SUBTRACT", FRONT_Y, y)))
    border = 0.4
    in_border = n.math("LESS_THAN", edge, border)
    color = mix_color(n.math("MULTIPLY", in_border, 0.7), color, (0.04, 0.04, 0.03))

    # Welded seams between the panels, 1.4 m apart across the tent with one right under the seat,
    # each a raised strip with a line of stitching down both sides; the same seam runs round the
    # border.
    seam_width = 0.05
    across = n.math("ABSOLUTE", n.math("SUBTRACT", n.math("FRACT", n.math("DIVIDE", x, 1.4)), 0.5))
    panel_seam = n.math("ABSOLUTE", n.math("SUBTRACT", n.math("MULTIPLY", across, 1.4), 0.7))
    to_border = n.math("ABSOLUTE", n.math("SUBTRACT", edge, border))
    seam = n.math("MINIMUM", n.math("ADD", panel_seam, n.math("MULTIPLY", in_border, 10)), to_border)
    welt = n.math("LESS_THAN", seam, seam_width / 2)
    stitch_line = n.math("LESS_THAN", n.math("ABSOLUTE", n.math("SUBTRACT", seam, seam_width / 2 - 0.004)), 0.0025)
    color = mix_color(n.math("MULTIPLY", welt, 0.85), color, (0.05, 0.045, 0.032))
    color = mix_color(n.math("MULTIPLY", stitch_line, 0.9), color, (0.32, 0.3, 0.21))
    links.new(color, bsdf.inputs["Base Color"])

    # Ripstop: a fine grid of heavier threads, about 7 mm, felt more than seen.
    grid = n.math("MAXIMUM",
                  n.math("LESS_THAN", n.math("FRACT", n.math("DIVIDE", x, 0.007)), 0.14),
                  n.math("LESS_THAN", n.math("FRACT", n.math("DIVIDE", y, 0.007)), 0.14))
    height = n.math("ADD", n.math("MULTIPLY", grid, 0.15), n.math("ADD", welt, n.math("MULTIPLY", crease, 0.5)))
    height = n.math("ADD", height, n.math("MULTIPLY", mottle.outputs["Fac"], 0.6))
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.002
    links.new(height, bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def print_material(name, path, roughness=0.85, weave=0.0):
    """Ink on paper or cloth: lit by the tent's lights, no glow of its own."""
    mat = image_material(name, path, roughness)
    if weave:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        coords = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 260
        links.new(coords.outputs["Object"], noise.inputs["Vector"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = weave
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], nodes["Principled BSDF"].inputs["Normal"])
    return mat


# MARK: - The tent

def build_tent(canvas, metal, layout):
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
            v.co.x -= math.copysign(sag(v.co.y), v.co.x)
    smooth(tent)

    strap = material("Strap", (0.05, 0.05, 0.05), 0.8)
    # The rolled-up door flap.
    cylinder("DoorRoll", 0.08, (x + 0.06, door_from - 0.05, door_top - 0.05), (x + 0.06, door_to + 0.05, door_top - 0.05), canvas)
    for y in (door_from + 0.2, door_to - 0.2):
        cylinder("DoorTie", 0.008, (x + 0.02, y, WALL_HEIGHT - 0.02), (x + 0.15, y, door_top - 0.12), strap)

    # Each window's canvas cover, rolled up inside above it. Two webbing ties hang from the top of
    # the wall and wrap round the roll.
    webbing = material("Webbing", (0.17, 0.145, 0.10), 0.85)
    for window in layout.windows or []:
        side, top = window.side, window.z + window.height / 2
        cloth = side * (HALF_WIDTH - sag(window.y))
        radius = 0.045
        wall = cloth - side * (radius + 0.012)
        start, end = window.y - window.width / 2 - 0.06, window.y + window.width / 2 + 0.06
        roll_z = top + 0.04 + radius + 0.005
        cylinder("WindowRoll", radius, (wall, start, roll_z), (wall, end, roll_z), canvas, segments=24)
        for y in (window.y - window.width / 2 + 0.12, window.y + window.width / 2 - 0.12):
            tie = torus("WindowTie", radius + 0.004, 0.004, (wall, y, roll_z), webbing, rotation=(math.pi / 2, 0, 0))
            # Flatten the ring into a strap about 25 mm wide.
            tie.scale = (1, 1, 3)
            box("WindowTieStrap", (0.004, 0.025, WALL_HEIGHT - 0.03 - roll_z), (cloth - side * 0.008, y, (WALL_HEIGHT - 0.03 + roll_z) / 2), webbing)

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


def wall_sheet(name, spot, gap, mat):
    """A thin sheet on a side wall that bows with the canvas behind it, like a poster pinned to it."""
    columns, rows = 12, 2

    def build(bm):
        uv = bm.loops.layers.uv.new()
        grid = []
        for j in range(rows + 1):
            row = []
            for i in range(columns + 1):
                u, v = i / columns, j / rows
                # The image's right is away from the viewer's left on the left wall, and so on.
                y = spot.y + (u - 0.5) * spot.width * -spot.side
                z = spot.z + (v - 0.5) * spot.height
                x = spot.side * (HALF_WIDTH - sag(y) - gap)
                row.append((bm.verts.new((x, y, z)), (u, v)))
            grid.append(row)
        for j in range(rows):
            for i in range(columns):
                corners = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
                face = bm.faces.new([vert for vert, _ in corners])
                for loop, (_, coord) in zip(face.loops, corners):
                    loop[uv].uv = coord
    return mesh_object(name, build, mat)


def build_branding(layout):
    """Meshtastic's own artwork, printed and hung like the showcase room's: the mark and wordmark
    on a canvas banner on the back wall, Chirpy on a poster, and the "Comms equipment provided by"
    plaque. make_textures.py draws them from the app's SVGs."""
    steel = material("Grommet", (0.6, 0.6, 0.62), 0.35, metallic=1.0)
    cord = material("Cord", (0.08, 0.08, 0.08), 0.8)

    if layout.banner:
        build_banner(layout.banner, steel, cord)
    if layout.poster:
        build_poster(layout.poster)
    if layout.plaque:
        build_plaque(layout.plaque)


def build_banner(spot, steel, cord):
    """The banner on the back wall, hung by its top grommets from the rafter."""
    bx, bz, bw, bh = spot
    banner_y = BACK_Y + 0.035
    plane("Banner", bw, bh, (bx, banner_y, bz), (math.pi / 2, 0, math.pi), print_material("Banner", os.path.join(CACHE, "banner.png"), 0.9, weave=0.08))
    for dx in (-bw / 2 + 0.04, bw / 2 - 0.04):
        for dz in (-bh / 2 + 0.04, bh / 2 - 0.04):
            torus("BannerGrommet", 0.011, 0.003, (bx + dx, banner_y + 0.002, bz + dz), steel, rotation=(math.pi / 2, 0, 0))
        # Up to the rafter along the back wall, which rises toward the ridge.
        top = Vector((bx + dx, banner_y, bz + bh / 2 - 0.04))
        rafter_z = WALL_HEIGHT - 0.04 + (RIDGE_HEIGHT - WALL_HEIGHT - 0.02) * (1 - abs(top.x) / (HALF_WIDTH - 0.05))
        cylinder("BannerCord", 0.004, top, (top.x, BACK_Y + 0.01, rafter_z - 0.02), cord, segments=6)


def build_poster(spot):
    """Chirpy on white, pinned at the corners, on a side wall (WallSpot) or the back wall (BackSpot)."""
    mat = print_material("ChirpyPoster", os.path.join(CACHE, "chirpy_poster.png"), 0.7)
    pin = material("PushPin", (0.75, 0.08, 0.06), 0.35)
    if isinstance(spot, BackSpot):
        # The back wall is flat: it doesn't sag between rafters like the side walls.
        plane("ChirpyPoster", spot.width, spot.height, (spot.x, BACK_Y + 0.01, spot.z), (math.pi / 2, 0, math.pi), mat)
        for du in (-1, 1):
            for dv in (-1, 1):
                x = spot.x + du * (spot.width / 2 - 0.025)
                z = spot.z + dv * (spot.height / 2 - 0.025)
                sphere("PosterPin", 0.008, (x, BACK_Y + 0.018, z), pin, segments=10)
        return
    wall_sheet("ChirpyPoster", spot, 0.004, mat)
    for du in (-1, 1):
        for dv in (-1, 1):
            y = spot.y + du * (spot.width / 2 - 0.025)
            z = spot.z + dv * (spot.height / 2 - 0.025)
            x = spot.side * (HALF_WIDTH - sag(y) - 0.012)
            sphere("PosterPin", 0.008, (x, y, z), pin, segments=10)


def build_plaque(spot):
    """A thin charcoal board on the wall."""
    depth = 0.012
    span = [spot.y - spot.width / 2, spot.y, spot.y + spot.width / 2]
    front = HALF_WIDTH - max(sag(y) for y in span) - 0.006 - depth
    edge = material("PlaqueEdge", (0.024, 0.027, 0.042), 0.8)
    box("Plaque", (depth, spot.width, spot.height), (spot.side * (front + depth / 2), spot.y, spot.z), edge, bevel=0.002)
    plane("PlaqueFace", spot.width, spot.height, (spot.side * (front - 0.0005), spot.y, spot.z), facing_in(spot.side), print_material("Plaque", os.path.join(CACHE, "solutions_plaque.png"), 0.8))


# MARK: - Lights, world, camera

def build_lights():
    bulb = material("Bulb", (1, 0.75, 0.45), emission=(1, 0.62, 0.3), strength=18)
    wire = material("Wire", (0.02, 0.02, 0.02), 0.6)
    # A string of bulbs down each side of the roof, drooping between rafters.
    for side in (-1, 1):
        points = []
        y = BACK_Y + 0.2
        while y < FRONT_Y - 0.2:
            nearest = min(abs(y - r) for r in RAFTERS)
            droop = 0.12 * math.sin(min(nearest / 0.75, 1) * math.pi / 2)
            x = side * 1.2
            z = WALL_HEIGHT + (RIDGE_HEIGHT - WALL_HEIGHT) * (1 - 1.2 / HALF_WIDTH) - 0.12 - droop
            points.append((x, y, z))
            y += 0.42
        for a, b in zip(points, points[1:]):
            cylinder("LightWire", 0.003, a, b, wire, segments=6)
        for p in points:
            sphere("Bulb", 0.03, (p[0], p[1], p[2] - 0.05), bulb)
    warm = (1.0, 0.70, 0.42)
    for y in (-1.4, 1.4):
        light = bpy.data.lights.new("Work", "POINT")
        light.energy = 25
        light.color = warm
        light.shadow_soft_size = 0.25
        obj = bpy.data.objects.new("Work", light)
        obj.location = (0, y, RIDGE_HEIGHT - 0.8)
        link(obj)


def build_window_lights(windows):
    """A little evening light coming in at each window. The lights can't be seen themselves, in
    the image or in the vinyl."""
    for window in windows:
        area = bpy.data.lights.new("WindowLight", "AREA")
        area.shape = "RECTANGLE"
        area.size, area.size_y = window.width, window.height
        area.energy = 9
        area.color = (0.95, 0.85, 0.72)
        # A beam into the room, tipped down a little, so it doesn't light up the roof just above
        # the window or wash out the far wall.
        area.spread = math.radians(70)
        obj = bpy.data.objects.new("WindowLight", area)
        obj.location = (window.side * (HALF_WIDTH - 0.3), window.y, window.z)
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((-window.side, 0, -0.4)).to_track_quat("-Z", "Y")
        obj.visible_camera = False
        obj.visible_glossy = False
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
    return camera


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
    scene.cycles.transparent_max_bounces = 8
    scene.render.resolution_x = options["width"]
    scene.render.resolution_y = options["width"] // 2
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.0
    scene.render.filepath = options["out"]


def render(furnish, layout=None):
    """Builds the tent, calls `furnish(layout)` to add the environment's own furniture, lights and
    boards, renders the panorama and writes its anchors. `layout` places the windows and branding."""
    options = arguments()
    layout = layout or Layout()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ANCHORS.clear()
    canvas = canvas_material(layout.windows)
    metal = material("Aluminum", (0.75, 0.76, 0.78), 0.35, metallic=1.0)
    build_tent(canvas, metal, layout)
    furnish(layout)
    screen_anchor()
    build_lights()
    build_window_lights(layout.windows or [])
    build_branding(layout)
    build_world()
    camera = build_camera()
    configure_render(options)
    if options["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(options["blend"]))
    if os.path.exists(options["out"]):
        os.remove(options["out"])
    if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
        raise SystemExit("render failed: " + options["out"])
    print("rendered", options["out"])
    # Only once the image exists, so the anchors never describe an image that wasn't made.
    write_anchors(options["out"], camera)

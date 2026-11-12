#
#  room_base.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/29/26.
#
#  What every cinema environment shares, whatever room it is: the seated camera, the sky and
#  light from an HDRI (or none, for a room lit only by its own lights), the render settings, the anchors file the app places its live panels from,
#  and small helpers for building the scene. An environment script builds its room and calls
#  render_room(); tent_base.py builds the tent on top of this. See README.md.
#
#  Blender's +Y is the image's center, where the app's screen goes. +X is the viewer's right,
#  Z is up, and the viewer sits at the origin.

import json
import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")

# The camera's height above the floor: a seated viewer's eyes.
EYE_HEIGHT = 1.15

# Surfaces the app covers with live panels, by the id the app knows them by. Filled in as the
# scene is built, written out by write_anchors().
ANCHORS = {}

def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    options = {"out": os.path.join(HERE, "out", "tent.png"), "width": 2048, "samples": 64, "blend": None}
    for i in range(0, len(argv) - 1, 2):
        key = argv[i].lstrip("-")
        options[key] = argv[i + 1]
    options["width"] = int(options["width"])
    options["samples"] = int(options["samples"])
    return options


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


# MARK: - Anchors

def anchor(board_id, obj, width, height):
    """Records a plane of the given mesh size as a board the app draws on. The plane's +X is the
    board's right and its +Z faces the viewer. write_anchors() reads where it ends up."""
    ANCHORS[board_id] = (obj, width, height)


def screen_anchor(center, rotation, width=2.6):
    """The app's screen (the "screen" anchor): an anchor only, nothing is drawn. `width` meters
    wide in the screen's shape, centered at `center`, turned by `rotation` from a plane lying flat
    and facing up. (math.pi / 2, 0, 0) stands it up facing the viewer from straight ahead (+Y).
    Every environment needs one, on a plain surface the viewer faces."""
    height = width * 940 / 1500
    surface = plane("Screen", width, height, center, rotation, None)
    surface.hide_render = True
    anchor("screen", surface, width, height)
    return surface


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
        "comment": "Written by scripts/cinema/room_base.py. Meters, RealityKit axes (+X right, +Y up, "
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


# MARK: - Views

# For the landscapes a cutout environment shows behind its glass when there is no real terrain:
# forest_view.py and sea_view.py.

def horizon_color(hdri, rotation):
    """The sky's average color just above the horizon, for the haze that fades far ground into it."""
    image = bpy.data.images.load(os.path.join(CACHE, hdri), check_existing=True)
    width, rows = image.size
    pixels = numpy.empty(width * rows * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(rows, width, 4)
    # Rows run bottom to top; one degree above the horizon.
    row = int(rows / 2 + rows / 180)
    color = pixels[row, :, :3].mean(axis=0)
    # Half of it cooled to a blue gray of the same brightness: distant ridges go blue, not the
    # sunset's pink.
    luminance = float(color @ numpy.array([0.2126, 0.7152, 0.0722]))
    cool = numpy.array([0.82, 0.95, 1.2]) * luminance
    return tuple(float(c) for c in (color + cool) / 2)


def hazed(name, surface, haze, distance):
    """A material whose `surface` (a function adding a BSDF to the tree) fades into `haze` with
    distance from the camera, as far ground does into the sky."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = surface(nodes, links)
    glow = nodes.new("ShaderNodeEmission")
    glow.inputs["Color"].default_value = (*haze, 1)
    camera = nodes.new("ShaderNodeCameraData")
    fade = nodes.new("ShaderNodeMath")
    fade.operation = "MULTIPLY"
    fade.inputs[1].default_value = -1 / distance
    links.new(camera.outputs["View Distance"], fade.inputs[0])
    power = nodes.new("ShaderNodeMath")
    power.operation = "EXPONENT"
    links.new(fade.outputs[0], power.inputs[0])
    amount = nodes.new("ShaderNodeMath")
    amount.operation = "SUBTRACT"
    amount.inputs[0].default_value = 1
    links.new(power.outputs[0], amount.inputs[1])
    mix = nodes.new("ShaderNodeMixShader")
    links.new(amount.outputs[0], mix.inputs["Fac"])
    links.new(bsdf.outputs[0], mix.inputs[1])
    links.new(glow.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs["Surface"])
    return mat


# MARK: - World, camera and render

def build_world(hdri, rotation=0.0, strength=0.4):
    """Lights the scene and fills everything past its walls with `hdri`, a file in cache/ that
    build.sh downloads. `rotation` turns it about the vertical in degrees; `strength` scales its
    light."""
    path = os.path.join(CACHE, hdri)
    if not os.path.exists(path):
        raise SystemExit(f"missing HDRI {path}: add an `hdri` line for it to build.sh")
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    background = nodes["Background"]
    environment = nodes.new("ShaderNodeTexEnvironment")
    environment.image = bpy.data.images.load(path)
    mapping = nodes.new("ShaderNodeMapping")
    coords = nodes.new("ShaderNodeTexCoord")
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(rotation))
    links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], environment.inputs["Vector"])
    links.new(environment.outputs["Color"], background.inputs["Color"])
    background.inputs["Strength"].default_value = strength
    bpy.context.scene.world = world


def build_dark_world():
    """A black world that gives no light, for a room lit only by its own lights."""
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0
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


def render_room(build, hdri, hdri_rotation=0.0, hdri_strength=0.4, cutout=False):
    """Starts an empty scene, calls `build()` to add the room, its furniture, lights and boards,
    renders the panorama and writes its anchors. `build()` must place the screen with
    screen_anchor(). With `cutout`, the HDRI lights the room but isn't painted: the image is
    transparent wherever the camera sees past the room's geometry, through glass included, so the
    app can put its own sky and terrain behind it. With `hdri` None the world is black and gives
    no light, so the room is lit only by the lights `build()` adds."""
    options = arguments()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ANCHORS.clear()
    build()
    if "screen" not in ANCHORS:
        raise SystemExit("no screen: the environment must call screen_anchor()")
    if hdri is None:
        build_dark_world()
    else:
        build_world(hdri, hdri_rotation, hdri_strength)
    camera = build_camera()
    configure_render(options)
    if cutout:
        scene = bpy.context.scene
        scene.render.film_transparent = True
        scene.cycles.film_transparent_glass = True
        scene.cycles.film_transparent_roughness = 0.1
        scene.render.image_settings.color_mode = "RGBA"
    if options["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(options["blend"]))
    if os.path.exists(options["out"]):
        os.remove(options["out"])
    if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
        raise SystemExit("render failed: " + options["out"])
    print("rendered", options["out"])
    # Only once the image exists, so the anchors never describe an image that wasn't made.
    write_anchors(options["out"], camera)

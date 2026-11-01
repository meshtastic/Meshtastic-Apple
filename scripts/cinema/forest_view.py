#
#  forest_view.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/30/26.
#
#  Renders the view from the fire lookout's tower when the app has no terrain to draw: a summit
#  falling away into forested valleys, with ridges behind, at sunset. It is the sky the lookout's
#  cutout image shows behind its glass. Run with build.sh, not by hand:
#
#    Blender -b -P forest_view.py -- --hdri kloppenheim_06_puresky_4k.hdr --rotation 5.5 --out out/x.png --width 4096
#
#  The sky is the clear sunset the app shows behind real terrain, at the same rotation, so the sun
#  sits where the cab's own light says it is.

import math
import os
import sys

import bpy
import numpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_base import CACHE, EYE_HEIGHT, arguments, build_camera, build_world, configure_render, link  # noqa: E402

# The cab floor stands this far above the summit (LookoutTerrain.cabHeight in the app).
TOWER = 34.0
# Ground at distance r is drawn from the summit out to here, far enough that its edge is the horizon.
REACH = 120_000.0
RINGS = 260
SPOKES = 1440
# Trees are real geometry out to here; past it the ground's own color stands in for them.
TREES_OUT = 2_600.0
# Earth's radius with the usual allowance for refraction, as in the app.
EARTH = 7_450_000.0


def height(x, y):
    """Ground height relative to the summit, in meters."""
    r = math.hypot(x, y)
    # The summit's slopes, falling to the valley floors: gently enough that the forest on them
    # shows above the sill from the seat, not just the ridges past them.
    h = -380 * (1 - math.exp(-r / 4_000))
    # Ridges that rise out of the valleys with distance.
    ridge = noise.ridged_multi_fractal(Vector((x / 9_000 + 3.1, y / 9_000 - 7.4, 0)), 1.0, 2.1, 6, 1.0, 2.0)
    h += 500 * ridge * min(1, max(0, (r - 2_500) / 10_000))
    # Rolling ground everywhere but the summit itself.
    hills = noise.fractal(Vector((x / 1_400, y / 1_400, 0.5)), 0.8, 2.0, 5)
    h += 70 * hills * min(1, r / 1_500)
    return h - r * r / (2 * EARTH)


def forest(x, y):
    """How wooded the ground is, 0 to 1: bare rock on the summit, and the odd clearing."""
    r = math.hypot(x, y)
    if r < 120:
        return 0.0
    clearing = noise.noise(Vector((x / 450, y / 450, 2.7)))
    return min(1.0, max(0.0, (r - 120) / 120)) * (0.0 if clearing > 0.55 else 1.0)


def build_ground():
    base = EYE_HEIGHT - TOWER - EYE_HEIGHT
    verts, wooded, faces = [], [], []
    distances = [0.0] + [20 * (REACH / 20) ** (i / (RINGS - 1)) for i in range(RINGS)]
    for ring, r in enumerate(distances):
        count = 1 if ring == 0 else SPOKES
        for spoke in range(count):
            angle = 2 * math.pi * spoke / SPOKES
            x, y = r * math.sin(angle), r * math.cos(angle)
            verts.append((x, y, base + height(x, y)))
            wooded.append(forest(x, y) if r < TREES_OUT else 0.0)
    for spoke in range(SPOKES):
        faces.append((0, 1 + spoke, 1 + (spoke + 1) % SPOKES))
    for ring in range(1, len(distances) - 1):
        inner, outer = 1 + (ring - 1) * SPOKES, 1 + ring * SPOKES
        for spoke in range(SPOKES):
            nxt = (spoke + 1) % SPOKES
            faces.append((inner + spoke, outer + spoke, outer + nxt, inner + nxt))
    mesh = bpy.data.meshes.new("Ground")
    mesh.from_pydata(verts, [], faces)
    mesh.shade_smooth()
    attribute = mesh.attributes.new("forest", "FLOAT", "POINT")
    attribute.data.foreach_set("value", wooded)
    ground = bpy.data.objects.new("Ground", mesh)
    link(ground)
    return ground


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


def ground_surface(nodes, links):
    """Forest canopy from a distance: dark greens in patches, with paler ground in the clearings."""
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.9
    # No sheen off the ground: at this low an angle it mirrors the sky.
    bsdf.inputs["Specular IOR Level"].default_value = 0
    patches = nodes.new("ShaderNodeTexNoise")
    patches.inputs["Scale"].default_value = 0.004
    patches.inputs["Detail"].default_value = 8
    coords = nodes.new("ShaderNodeTexCoord")
    links.new(coords.outputs["Object"], patches.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.018, 0.034, 0.016, 1)
    ramp.color_ramp.elements[1].color = (0.045, 0.06, 0.026, 1)
    links.new(patches.outputs["Fac"], ramp.inputs["Fac"])
    # Clearings and the summit: dry grass and rock.
    wooded = nodes.new("ShaderNodeAttribute")
    wooded.attribute_name = "forest"
    near = nodes.new("ShaderNodeCameraData")
    far = nodes.new("ShaderNodeMath")
    far.operation = "GREATER_THAN"
    far.inputs[1].default_value = TREES_OUT - 50
    links.new(near.outputs["View Distance"], far.inputs[0])
    covered = nodes.new("ShaderNodeMath")
    covered.operation = "MAXIMUM"
    links.new(wooded.outputs["Fac"], covered.inputs[0])
    links.new(far.outputs[0], covered.inputs[1])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(covered.outputs[0], mix.inputs["Factor"])
    mix.inputs["A"].default_value = (0.12, 0.11, 0.06, 1)
    links.new(ramp.outputs["Color"], mix.inputs["B"])
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return bsdf


def tree_surface(nodes, links):
    """Needles, a little different on every tree."""
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Specular IOR Level"].default_value = 0
    info = nodes.new("ShaderNodeObjectInfo")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.012, 0.03, 0.014, 1)
    ramp.color_ramp.elements[1].color = (0.04, 0.062, 0.025, 1)
    links.new(info.outputs["Random"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return bsdf


def build_tree(mat):
    """A conifer about 12 m tall: a trunk and three stacked cones."""
    parts = []
    for radius, depth, z in ((0.25, 3.0, 1.5), (2.4, 6.0, 5.0), (1.8, 5.0, 8.0), (1.1, 4.0, 10.5)):
        if radius < 0.5:
            bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=radius, depth=depth, location=(0, 0, z))
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=radius, depth=depth, location=(0, 0, z))
        parts.append(bpy.context.active_object)
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    tree = bpy.context.active_object
    tree.name = "Conifer"
    tree.data.materials.append(mat)
    tree.hide_render = True
    tree.location = (0, 0, -10_000)
    return tree


def scatter(ground, tree):
    """Plants the tree over the wooded ground, turned and sized at random."""
    group = bpy.data.node_groups.new("Forest", "GeometryNodeTree")
    group.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    group.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    nodes, links = group.nodes, group.links
    source = nodes.new("NodeGroupInput")
    sink = nodes.new("NodeGroupOutput")
    wooded = nodes.new("GeometryNodeInputNamedAttribute")
    wooded.data_type = "FLOAT"
    wooded.inputs["Name"].default_value = "forest"
    density = nodes.new("ShaderNodeMath")
    density.operation = "MULTIPLY"
    # About one tree to every 30 square meters.
    density.inputs[1].default_value = 1 / 30
    links.new(wooded.outputs["Attribute"], density.inputs[0])
    points = nodes.new("GeometryNodeDistributePointsOnFaces")
    links.new(source.outputs["Geometry"], points.inputs["Mesh"])
    links.new(density.outputs[0], points.inputs["Density"])
    info = nodes.new("GeometryNodeObjectInfo")
    info.inputs["Object"].default_value = tree
    info.inputs["As Instance"].default_value = True
    turn = nodes.new("FunctionNodeRandomValue")
    turn.data_type = "FLOAT_VECTOR"
    turn.inputs["Max"].default_value = (0, 0, 2 * math.pi)
    size = nodes.new("FunctionNodeRandomValue")
    size.data_type = "FLOAT"
    size.inputs["Min"].default_value = 0.6
    size.inputs["Max"].default_value = 1.5
    size.inputs["Seed"].default_value = 7
    planted = nodes.new("GeometryNodeInstanceOnPoints")
    links.new(points.outputs["Points"], planted.inputs["Points"])
    links.new(info.outputs["Geometry"], planted.inputs["Instance"])
    links.new(turn.outputs["Value"], planted.inputs["Rotation"])
    links.new(size.outputs["Value"], planted.inputs["Scale"])
    join = nodes.new("GeometryNodeJoinGeometry")
    links.new(source.outputs["Geometry"], join.inputs["Geometry"])
    links.new(planted.outputs["Instances"], join.inputs["Geometry"])
    links.new(join.outputs["Geometry"], sink.inputs["Geometry"])
    modifier = ground.modifiers.new("Forest", "NODES")
    modifier.node_group = group


options = arguments()
bpy.ops.wm.read_factory_settings(use_empty=True)
rotation = float(options.get("rotation", 0))
build_world(options["hdri"], rotation, float(options.get("strength", 1)))
camera = build_camera()
# Out past the horizon, not the default 100 m.
camera.data.clip_end = 2 * REACH
haze = horizon_color(options["hdri"], rotation)
ground = build_ground()
ground.data.materials.append(hazed("Ground", ground_surface, haze, 25_000))
scatter(ground, build_tree(hazed("Needles", tree_surface, haze, 25_000)))
configure_render(options)
if os.path.exists(options["out"]):
    os.remove(options["out"])
if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
    raise SystemExit("render failed: " + options["out"])
print("rendered", options["out"])

#
#  space_earth.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  Renders the view out of the space station's cupola: Earth from 420 km, with clouds, a thin
#  blue edge of atmosphere, city lights coming on past the line between day and night, and black
#  space beyond. It is the sky the cupola's cutout image (space_cupola.py) shows behind its
#  windows. Run with build.sh, not by hand:
#
#    Blender -b -P space_earth.py -- --out out/space_earth.png --width 4096 --samples 64
#
#  The ground is NASA's Blue Marble Next Generation (July, with topography and bathymetry) and the
#  city lights NASA's Black Marble 2016, both public domain, which build.sh downloads into cache/.
#  The clouds are procedural. The scene is in kilometers.

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orbit import (  # noqa: E402
    ALTITUDE,
    EARTH_RADIUS,
    NADIR_LATITUDE,
    NADIR_LONGITUDE,
    NORTH,
    earth_direction,
    sun_direction,
)
from room_base import CACHE, arguments, build_camera, configure_render, link, smooth  # noqa: E402

BLUE_MARBLE = "blue_marble_july_16384.jpg"
BLACK_MARBLE = "BlackMarble_2016_3km_gray.jpg"
# How high the clouds and the top of the glowing atmosphere sit above the ground, in kilometers.
CLOUD_HEIGHT = 8.0
AIR_HEIGHT = 70.0


def cached(name):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        raise SystemExit(f"missing {path}: build.sh downloads it")
    return path


def earth_sphere(name, radius, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=512, ring_count=256, radius=radius)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    smooth(obj)
    return obj


def latlon_vector(nodes, links):
    """The equirectangular image coordinates of the shading point, from its object-space
    position: longitude 0 on +X, north on +Z."""
    coords = nodes.new("ShaderNodeTexCoord")
    normal = nodes.new("ShaderNodeVectorMath")
    normal.operation = "NORMALIZE"
    links.new(coords.outputs["Object"], normal.inputs[0])
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(normal.outputs[0], split.inputs[0])
    lon = nodes.new("ShaderNodeMath")
    lon.operation = "ARCTAN2"
    links.new(split.outputs["Y"], lon.inputs[0])
    links.new(split.outputs["X"], lon.inputs[1])
    u = nodes.new("ShaderNodeMath")
    u.operation = "MULTIPLY_ADD"
    u.inputs[1].default_value = 1 / (2 * math.pi)
    u.inputs[2].default_value = 0.5
    links.new(lon.outputs[0], u.inputs[0])
    lat = nodes.new("ShaderNodeMath")
    lat.operation = "ARCSINE"
    links.new(split.outputs["Z"], lat.inputs[0])
    v = nodes.new("ShaderNodeMath")
    v.operation = "MULTIPLY_ADD"
    v.inputs[1].default_value = 1 / math.pi
    v.inputs[2].default_value = 0.5
    links.new(lat.outputs[0], v.inputs[0])
    combine = nodes.new("ShaderNodeCombineXYZ")
    links.new(u.outputs[0], combine.inputs["X"])
    links.new(v.outputs[0], combine.inputs["Y"])
    return combine


def sunlit(nodes, links, low, high):
    """0 to 1 across the line between night and day: how much the shading point faces the sun,
    from `low` (night) to `high` (day), in the cosine of the sun's angle."""
    geometry = nodes.new("ShaderNodeNewGeometry")
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = sun_direction()
    links.new(geometry.outputs["Normal"], dot.inputs[0])
    ramp = nodes.new("ShaderNodeMapRange")
    ramp.interpolation_type = "SMOOTHSTEP"
    ramp.inputs["From Min"].default_value = low
    ramp.inputs["From Max"].default_value = high
    links.new(dot.outputs["Value"], ramp.inputs["Value"])
    return ramp


def ground_material():
    mat = bpy.data.materials.new("Ground")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    vector = latlon_vector(nodes, links)
    day = nodes.new("ShaderNodeTexImage")
    day.image = bpy.data.images.load(cached(BLUE_MARBLE))
    day.interpolation = "Cubic"
    links.new(vector.outputs[0], day.inputs["Vector"])
    # The Blue Marble is a little dark and flat to light as a surface; lift it toward how the
    # ground looks from orbit.
    lift = nodes.new("ShaderNodeBrightContrast")
    lift.inputs["Bright"].default_value = 0.04
    lift.inputs["Contrast"].default_value = 0.12
    links.new(day.outputs["Color"], lift.inputs["Color"])
    links.new(lift.outputs["Color"], bsdf.inputs["Base Color"])
    # Water is the blue that is darker than it is red: shinier, for the sun's glint.
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(day.outputs["Color"], split.inputs[0])
    water = nodes.new("ShaderNodeMath")
    water.operation = "SUBTRACT"
    links.new(split.outputs["Blue"], water.inputs[0])
    links.new(split.outputs["Red"], water.inputs[1])
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["From Min"].default_value = 0.02
    rough.inputs["From Max"].default_value = 0.12
    rough.inputs["To Min"].default_value = 0.9
    rough.inputs["To Max"].default_value = 0.32
    links.new(water.outputs[0], rough.inputs["Value"])
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    # City lights, only on the night side.
    night = nodes.new("ShaderNodeTexImage")
    night.image = bpy.data.images.load(cached(BLACK_MARBLE))
    night.image.colorspace_settings.name = "Non-Color"
    links.new(vector.outputs[0], night.inputs["Vector"])
    dark = sunlit(nodes, links, 0.08, -0.12)
    lights = nodes.new("ShaderNodeMath")
    lights.operation = "MULTIPLY"
    links.new(night.outputs["Color"], lights.inputs[0])
    links.new(dark.outputs["Result"], lights.inputs[1])
    curve = nodes.new("ShaderNodeMath")
    curve.operation = "POWER"
    curve.inputs[1].default_value = 2.2
    links.new(lights.outputs[0], curve.inputs[0])
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.62, 0.3, 1)
    strength = nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    strength.inputs[1].default_value = 6.0
    links.new(curve.outputs[0], strength.inputs[0])
    links.new(strength.outputs[0], bsdf.inputs["Emission Strength"])
    return mat


def cloud_material():
    """White cloud over the ground: swirls of noise, thinned out to about half cover."""
    mat = bpy.data.materials.new("Clouds")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    output = nodes["Material Output"]
    nodes.remove(nodes["Principled BSDF"])
    coords = nodes.new("ShaderNodeTexCoord")
    unit = nodes.new("ShaderNodeVectorMath")
    unit.operation = "NORMALIZE"
    links.new(coords.outputs["Object"], unit.inputs[0])
    # Warp the lookup by a broad noise, so the cloud forms bands and swirls rather than blobs.
    warp = nodes.new("ShaderNodeTexNoise")
    warp.noise_dimensions = "3D"
    warp.inputs["Scale"].default_value = 6
    warp.inputs["Detail"].default_value = 3
    links.new(unit.outputs[0], warp.inputs["Vector"])
    offset = nodes.new("ShaderNodeVectorMath")
    offset.operation = "MULTIPLY_ADD"
    offset.inputs[1].default_value = (0.18, 0.18, 0.18)
    links.new(warp.outputs["Color"], offset.inputs[0])
    links.new(unit.outputs[0], offset.inputs[2])
    cloud = nodes.new("ShaderNodeTexNoise")
    cloud.noise_dimensions = "3D"
    cloud.inputs["Scale"].default_value = 38
    cloud.inputs["Detail"].default_value = 14
    cloud.inputs["Roughness"].default_value = 0.62
    cloud.inputs["Distortion"].default_value = 0.35
    links.new(offset.outputs[0], cloud.inputs["Vector"])
    cover = nodes.new("ShaderNodeValToRGB")
    cover.color_ramp.elements[0].position = 0.5
    cover.color_ramp.elements[0].color = (0, 0, 0, 1)
    cover.color_ramp.elements[1].position = 0.66
    cover.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(cloud.outputs["Fac"], cover.inputs["Fac"])
    diffuse = nodes.new("ShaderNodeBsdfDiffuse")
    diffuse.inputs["Color"].default_value = (0.92, 0.93, 0.95, 1)
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(cover.outputs["Color"], mix.inputs["Fac"])
    links.new(clear.outputs[0], mix.inputs[1])
    links.new(diffuse.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs["Surface"])
    mat.blend_method = "BLEND"
    return mat


def air_material():
    """The atmosphere seen edge on: a glow that thickens toward the limb, blue on the day side and
    reddening at the line between day and night, nothing on the night side."""
    mat = bpy.data.materials.new("Air")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    output = nodes["Material Output"]
    nodes.remove(nodes["Principled BSDF"])
    weight = nodes.new("ShaderNodeLayerWeight")
    weight.inputs["Blend"].default_value = 0.5
    edge = nodes.new("ShaderNodeMath")
    edge.operation = "POWER"
    edge.inputs[1].default_value = 4.0
    links.new(weight.outputs["Facing"], edge.inputs[0])
    day = sunlit(nodes, links, -0.25, 0.2)
    amount = nodes.new("ShaderNodeMath")
    amount.operation = "MULTIPLY"
    links.new(edge.outputs[0], amount.inputs[0])
    links.new(day.outputs["Result"], amount.inputs[1])
    tint = nodes.new("ShaderNodeValToRGB")
    tint.color_ramp.elements[0].position = 0.0
    tint.color_ramp.elements[0].color = (0.9, 0.35, 0.12, 1)
    tint.color_ramp.elements[1].position = 0.6
    tint.color_ramp.elements[1].color = (0.22, 0.48, 1.0, 1)
    links.new(day.outputs["Result"], tint.inputs["Fac"])
    glow = nodes.new("ShaderNodeEmission")
    links.new(tint.outputs["Color"], glow.inputs["Color"])
    scale = nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = 2.4
    links.new(amount.outputs[0], scale.inputs[0])
    links.new(scale.outputs[0], glow.inputs["Strength"])
    clear = nodes.new("ShaderNodeBsdfTransparent")
    add = nodes.new("ShaderNodeAddShader")
    links.new(clear.outputs[0], add.inputs[0])
    links.new(glow.outputs[0], add.inputs[1])
    links.new(add.outputs[0], output.inputs["Surface"])
    mat.blend_method = "BLEND"
    return mat


def orientation():
    """Turns the globe so the nadir point faces the viewer and north runs the way NORTH says."""
    lat, lon = math.radians(NADIR_LATITUDE), math.radians(NADIR_LONGITUDE)
    up0 = Vector((math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)))
    north0 = Vector((-math.sin(lat) * math.cos(lon), -math.sin(lat) * math.sin(lon), math.cos(lat)))
    east0 = north0.cross(up0)
    up = -earth_direction()
    north = (NORTH - NORTH.dot(up) * up).normalized()
    east = north.cross(up)
    local = Matrix((east0, north0, up0)).transposed()
    world = Matrix((east, north, up)).transposed()
    return world @ local.inverted()


def build():
    center = earth_direction() * (EARTH_RADIUS + ALTITUDE)
    turn = orientation().to_4x4()
    for name, radius, mat in (
        ("Ground", EARTH_RADIUS, ground_material()),
        ("Clouds", EARTH_RADIUS + CLOUD_HEIGHT, cloud_material()),
        ("Air", EARTH_RADIUS + AIR_HEIGHT, air_material()),
    ):
        obj = earth_sphere(name, radius, mat)
        obj.matrix_world = Matrix.Translation(center) @ turn

    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.5
    sun.angle = math.radians(0.53)
    obj = bpy.data.objects.new("Sun", sun)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = sun_direction().to_track_quat("Z", "Y")
    link(obj)
    # The sun's disk, far out past Earth, and the glare round it.
    disk = bpy.data.materials.new("SunDisk")
    disk.use_nodes = True
    bsdf = disk.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    bsdf.inputs["Emission Color"].default_value = (1, 0.97, 0.92, 1)
    bsdf.inputs["Emission Strength"].default_value = 60
    distance = 60_000.0
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=distance * math.tan(math.radians(0.6)), location=sun_direction() * distance)
    bpy.context.active_object.data.materials.append(disk)


options = arguments()
bpy.ops.wm.read_factory_settings(use_empty=True)
build()
world = bpy.data.worlds.new("Space")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
bpy.context.scene.world = world
camera = build_camera()
camera.location = (0, 0, 0)
camera.data.clip_start = 0.01
camera.data.clip_end = 100_000
configure_render(options)
if os.path.exists(options["out"]):
    os.remove(options["out"])
if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
    raise SystemExit("render failed: " + options["out"])
print("rendered", options["out"])

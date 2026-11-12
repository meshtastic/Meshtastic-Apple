#
#  sea_view.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  Renders the view from the lighthouse's lantern when the app has no terrain to draw: open sea on
#  every side but one, with the headland the tower stands on reaching back to a coast of low hills
#  behind, at sunset. It is the sky the lighthouse's cutout image shows behind its glass. Run with
#  build.sh, not by hand:
#
#    Blender -b -P sea_view.py -- --hdri kloppenheim_06_puresky_4k.hdr --rotation 131.5 --out out/x.png --width 4096
#
#  The sky is the clear sunset the app shows behind real terrain, at the same rotation, so the sun
#  sits where the lantern's own light says it is, low over the sea on the left.

import math
import os
import sys

import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_base import arguments, build_camera, build_world, configure_render, hazed, horizon_color, link  # noqa: E402

# The lantern's floor stands this far above the headland (LookoutSiteKind.coast's stand height in
# the app), and the headland's top this far above the sea.
TOWER = 24.0
CLIFF = 30.0
SEA = -TOWER - CLIFF
REACH = 80_000.0
RINGS = 240
SPOKES = 1440
# Earth's radius with the usual allowance for refraction, as in the app.
EARTH = 7_450_000.0


def inland(x, y):
    """How far inside the coast a point is, in meters, roughly: positive on land. The headland is a
    blunt point reaching forward past the tower, joining a coast that runs across behind it."""
    # The headland's sides, a ragged edge on each.
    edge = 6 * noise.noise(Vector((x / 60, y / 60, 1.3))) + 14 * noise.noise(Vector((x / 400, y / 400, 4.1)))
    headland = (60 - y) * 0.75 - abs(x) + edge
    # The coast behind, its bays and points a few hundred meters deep.
    shore = -1_400 - y + 300 * noise.noise(Vector((x / 2_500, 0.5, 7.7))) + 60 * noise.noise(Vector((x / 300, y / 300, 2.2)))
    return max(headland, shore)


def height(x, y):
    """Ground height relative to the lantern's floor: the sea, or land rising from cliffs at the
    water's edge to hills inland."""
    d = inland(x, y)
    drop = -(x * x + y * y) / (2 * EARTH)
    if d < 0:
        return SEA - 6 + drop
    # Cliffs: the headland's top within twenty meters of the edge.
    cliff = min(1.0, d / 20) ** 0.6
    # Inland, the land rises to rolling hills a kilometer or more back.
    r = math.hypot(x, y)
    hills = 240 * max(0.0, noise.fractal(Vector((x / 3_000, y / 3_000, 0.9)), 0.8, 2.0, 5) + 0.6) * min(1, max(0, (d - 300) / 2_500))
    rolling = 8 * noise.noise(Vector((x / 200, y / 200, 3.3))) * min(1, r / 200)
    return SEA + (CLIFF + hills + rolling) * cliff + drop


def build_ground():
    verts, faces = [], []
    distances = [0.0] + [10 * (REACH / 10) ** (i / (RINGS - 1)) for i in range(RINGS)]
    for ring, r in enumerate(distances):
        count = 1 if ring == 0 else SPOKES
        for spoke in range(count):
            angle = 2 * math.pi * spoke / SPOKES
            x, y = r * math.sin(angle), r * math.cos(angle)
            verts.append((x, y, height(x, y)))
    for spoke in range(SPOKES):
        faces.append((0, 1 + spoke, 1 + (spoke + 1) % SPOKES))
    for ring in range(1, len(distances) - 1):
        inner, outer = 1 + (ring - 1) * SPOKES, 1 + ring * SPOKES
        for spoke in range(SPOKES):
            nxt = (spoke + 1) % SPOKES
            faces.append((inner + spoke, outer + spoke, outer + nxt, inner + nxt))
    mesh = bpy.data.meshes.new("Land")
    mesh.from_pydata(verts, [], faces)
    mesh.shade_smooth()
    land = bpy.data.objects.new("Land", mesh)
    link(land)
    return land


def build_sea():
    """The sea as a curved disc, dropping away with the Earth to the horizon."""
    verts, faces = [], []
    distances = [0.0] + [10 * (REACH / 10) ** (i / 119) for i in range(120)]
    spokes = 360
    for ring, r in enumerate(distances):
        count = 1 if ring == 0 else spokes
        for spoke in range(count):
            angle = 2 * math.pi * spoke / spokes
            verts.append((r * math.sin(angle), r * math.cos(angle), SEA - r * r / (2 * EARTH)))
    for spoke in range(spokes):
        faces.append((0, 1 + spoke, 1 + (spoke + 1) % spokes))
    for ring in range(1, len(distances) - 1):
        inner, outer = 1 + (ring - 1) * spokes, 1 + ring * spokes
        for spoke in range(spokes):
            nxt = (spoke + 1) % spokes
            faces.append((inner + spoke, outer + spoke, outer + nxt, inner + nxt))
    mesh = bpy.data.meshes.new("Sea")
    mesh.from_pydata(verts, [], faces)
    mesh.shade_smooth()
    sea = bpy.data.objects.new("Sea", mesh)
    link(sea)
    return sea


def sea_surface(nodes, links):
    """Deep water, glossy, with swell and chop that calm with distance so the far sea reads as a
    smooth sheet catching the sunset."""
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.006, 0.025, 0.04, 1)
    # Rougher with distance: past what the waves can show, the roughness stands in for them and
    # spreads the sun's reflection into a path across the water.
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["From Min"].default_value = 300
    rough.inputs["From Max"].default_value = 20_000
    rough.inputs["To Min"].default_value = 0.12
    rough.inputs["To Max"].default_value = 0.3
    bsdf.inputs["IOR"].default_value = 1.33
    coords = nodes.new("ShaderNodeTexCoord")
    camera = nodes.new("ShaderNodeCameraData")
    calm = nodes.new("ShaderNodeMapRange")
    calm.inputs["From Min"].default_value = 500
    calm.inputs["From Max"].default_value = 8_000
    calm.inputs["To Min"].default_value = 1.0
    calm.inputs["To Max"].default_value = 0.25
    links.new(camera.outputs["View Distance"], calm.inputs["Value"])
    links.new(camera.outputs["View Distance"], rough.inputs["Value"])
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    normal = None
    for scale, strength in ((0.02, 0.6), (0.15, 0.8), (1.2, 0.7), (5.0, 0.5)):
        waves = nodes.new("ShaderNodeTexNoise")
        waves.inputs["Scale"].default_value = scale
        waves.inputs["Detail"].default_value = 4
        mapping = nodes.new("ShaderNodeMapping")
        # Swell runs in long crests, not round lumps.
        mapping.inputs["Scale"].default_value = (1, 3, 1)
        links.new(coords.outputs["Object"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], waves.inputs["Vector"])
        bump = nodes.new("ShaderNodeBump")
        # Bumped in proportion to each layer's size, so long swell tilts the water as much as chop.
        bump.inputs["Distance"].default_value = 0.3 / scale
        weight = nodes.new("ShaderNodeMath")
        weight.operation = "MULTIPLY"
        weight.inputs[1].default_value = strength
        links.new(calm.outputs["Result"], weight.inputs[0])
        links.new(weight.outputs[0], bump.inputs["Strength"])
        links.new(waves.outputs["Fac"], bump.inputs["Height"])
        if normal:
            links.new(normal, bump.inputs["Normal"])
        normal = bump.outputs["Normal"]
    links.new(normal, bsdf.inputs["Normal"])
    return bsdf


def land_surface(nodes, links):
    """Coastal grass gone gold at the end of summer, with rock on the cliffs and steep ground."""
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0
    patches = nodes.new("ShaderNodeTexNoise")
    patches.inputs["Scale"].default_value = 0.004
    patches.inputs["Detail"].default_value = 8
    coords = nodes.new("ShaderNodeTexCoord")
    links.new(coords.outputs["Object"], patches.inputs["Vector"])
    grass = nodes.new("ShaderNodeValToRGB")
    # Dark scrub and wind-bent trees in the hollows, gold grass on the rises.
    grass.color_ramp.elements[0].position = 0.42
    grass.color_ramp.elements[0].color = (0.025, 0.04, 0.018, 1)
    grass.color_ramp.elements[1].position = 0.58
    grass.color_ramp.elements[1].color = (0.24, 0.18, 0.07, 1)
    links.new(patches.outputs["Fac"], grass.inputs["Fac"])
    geometry = nodes.new("ShaderNodeNewGeometry")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Normal"], split.inputs[0])
    steep = nodes.new("ShaderNodeMapRange")
    steep.inputs["From Min"].default_value = 0.8
    steep.inputs["From Max"].default_value = 0.6
    links.new(split.outputs["Z"], steep.inputs["Value"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(steep.outputs["Result"], mix.inputs["Factor"])
    links.new(grass.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (0.16, 0.13, 0.1, 1)
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return bsdf


options = arguments()
bpy.ops.wm.read_factory_settings(use_empty=True)
rotation = float(options.get("rotation", 0))
build_world(options["hdri"], rotation, float(options.get("strength", 1)))
camera = build_camera()
camera.data.clip_end = 2 * REACH
haze = horizon_color(options["hdri"], rotation)
build_sea().data.materials.append(hazed("Sea", sea_surface, haze, 30_000))
build_ground().data.materials.append(hazed("Land", land_surface, haze, 20_000))
configure_render(options)
if os.path.exists(options["out"]):
    os.remove(options["out"])
if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
    raise SystemExit("render failed: " + options["out"])
print("rendered", options["out"])

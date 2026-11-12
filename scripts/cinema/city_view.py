#
#  city_view.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  Renders the view from the city rooftop when the app has no buildings to draw: a downtown of
#  towers falling away into lower blocks, the streets lit and the windows coming on, at sunset. It
#  is the sky the rooftop's cutout image shows past its railing. Run with build.sh, not by hand:
#
#    Blender -b -P city_view.py -- --hdri kloppenheim_06_puresky_4k.hdr --rotation 5.5 --out out/x.png --width 4096
#
#  The sky is the clear sunset the app shows behind real terrain, at the same rotation, so the sun
#  sits where the rooftop's own light says it is. The city is made up: blocks on a grid, a tower
#  here and there downtown and lower and lower buildings outward, so no real skyline is copied.

import math
import os
import random
import sys

import bmesh
import bpy
import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_base import CACHE, EYE_HEIGHT, arguments, build_camera, build_world, configure_render, link  # noqa: E402

# The rooftop deck stands this far above the street: the tallest building downtown.
ROOF = 150.0
# A city block, and the street round it, on a grid turned a little off the view.
BLOCK = 110.0
STREET = 22.0
GRID_TURN = math.radians(17)
# Buildings out to here; past it the lit street grid carries on to the horizon.
CITY = 5_000.0
REACH = 60_000.0
# Earth's radius with the usual allowance for refraction, as in the app.
EARTH = 7_450_000.0


def drop(r):
    return r * r / (2 * EARTH)


def base_height(r):
    """How tall buildings run at distance r: towers downtown, mid-rise round them, low beyond."""
    downtown = 110 * math.exp(-(r / 900) ** 2)
    midrise = 28 * math.exp(-r / 2_200)
    return 9 + downtown + midrise


def build_city(rng):
    """The buildings as one mesh: each block split into lots, each lot a box of its own height,
    with a setback upper part on the taller ones."""
    bm = bmesh.new()
    pitch = BLOCK + STREET
    cos_t, sin_t = math.cos(GRID_TURN), math.sin(GRID_TURN)
    reach = int(CITY / pitch) + 1
    ground = -ROOF - EYE_HEIGHT

    def add_box(cx, cy, w, d, bottom, top, yaw):
        c, s = math.cos(yaw), math.sin(yaw)
        corners = []
        for dx, dy in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)):
            corners.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
        r = math.hypot(cx, cy)
        z0, z1 = bottom - drop(r), top - drop(r)
        low = [bm.verts.new((x, y, z0)) for x, y in corners]
        high = [bm.verts.new((x, y, z1)) for x, y in corners]
        bm.faces.new(high)
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((low[i], low[j], high[j], high[i]))

    for i in range(-reach, reach + 1):
        for j in range(-reach, reach + 1):
            bx, by = i * pitch, j * pitch
            cx, cy = bx * cos_t - by * sin_t, bx * sin_t + by * cos_t
            r = math.hypot(cx, cy)
            # The viewer's own block is the building they stand on.
            if r > CITY or r < pitch * 0.6:
                continue
            lots = rng.choice((1, 2, 2, 3, 4))
            for k in range(lots):
                # Lots side by side along the block.
                share = BLOCK / lots
                ox = -BLOCK / 2 + share * (k + 0.5)
                w = share * rng.uniform(0.7, 0.95)
                d = BLOCK * rng.uniform(0.55, 0.95)
                lx = cx + ox * cos_t
                ly = cy + ox * sin_t
                height = base_height(r) * rng.uniform(0.35, 1.25)
                # Now and then a tower well above its neighbors, downtown.
                if r < 1_600 and rng.random() < 0.12:
                    height *= rng.uniform(1.4, 1.9)
                height = min(height, ROOF - 12)
                add_box(lx, ly, w, d, ground, ground + height, GRID_TURN)
                if height > 45 and rng.random() < 0.6:
                    add_box(lx, ly, w * 0.7, d * 0.7, ground + height, ground + height * rng.uniform(1.05, 1.18), GRID_TURN)
    mesh = bpy.data.meshes.new("City")
    bm.to_mesh(mesh)
    bm.free()
    city = bpy.data.objects.new("City", mesh)
    link(city)
    return city


def build_ground():
    """The ground out to the horizon, its streets on the same grid as the blocks."""
    ground = -ROOF - EYE_HEIGHT
    verts, faces = [], []
    rings, spokes = 120, 720
    distances = [0.0] + [40 * (REACH / 40) ** (i / (rings - 1)) for i in range(rings)]
    for ring, r in enumerate(distances):
        count = 1 if ring == 0 else spokes
        for spoke in range(count):
            angle = 2 * math.pi * spoke / spokes
            verts.append((r * math.sin(angle), r * math.cos(angle), ground - drop(r)))
    for spoke in range(spokes):
        faces.append((0, 1 + spoke, 1 + (spoke + 1) % spokes))
    for ring in range(1, len(distances) - 1):
        inner, outer = 1 + (ring - 1) * spokes, 1 + ring * spokes
        for spoke in range(spokes):
            nxt = (spoke + 1) % spokes
            faces.append((inner + spoke, outer + spoke, outer + nxt, inner + nxt))
    mesh = bpy.data.meshes.new("Ground")
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("Ground", mesh)
    link(obj)
    return obj


def horizon_color(hdri):
    """The sky's average color just above the horizon, for the haze over the far city."""
    image = bpy.data.images.load(os.path.join(CACHE, hdri), check_existing=True)
    width, rows = image.size
    pixels = numpy.empty(width * rows * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(rows, width, 4)
    row = int(rows / 2 + rows / 180)
    color = pixels[row, :, :3].mean(axis=0)
    luminance = float(color @ numpy.array([0.2126, 0.7152, 0.0722]))
    cool = numpy.array([0.85, 0.95, 1.15]) * luminance
    return tuple(float(c) for c in (color + cool) / 2)


def grid_vector(nodes, links):
    """The shading point's position on the street grid's own axes, in meters."""
    geometry = nodes.new("ShaderNodeNewGeometry")
    turn = nodes.new("ShaderNodeVectorRotate")
    turn.rotation_type = "Z_AXIS"
    turn.inputs["Angle"].default_value = -GRID_TURN
    links.new(geometry.outputs["Position"], turn.inputs["Vector"])
    return geometry, turn


def hazed_output(nodes, links, shader, haze, distance):
    """Fades `shader` into the haze color with distance from the camera."""
    output = nodes.new("ShaderNodeOutputMaterial")
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
    links.new(shader, mix.inputs[1])
    links.new(glow.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs["Surface"])


def building_material(haze):
    """Concrete and glass walls with a window every 1.6 m on each 3.6 m floor, about a fifth of
    them lit, and plain dark roofs."""
    mat = bpy.data.materials.new("Buildings")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    geometry, turned = grid_vector(nodes, links)
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(turned.outputs[0], split.inputs[0])
    along = nodes.new("ShaderNodeMath")
    along.operation = "ADD"
    links.new(split.outputs["X"], along.inputs[0])
    links.new(split.outputs["Y"], along.inputs[1])
    uv = nodes.new("ShaderNodeCombineXYZ")
    links.new(along.outputs[0], uv.inputs["X"])
    links.new(split.outputs["Z"], uv.inputs["Y"])
    windows = nodes.new("ShaderNodeTexBrick")
    windows.offset = 0
    windows.inputs["Scale"].default_value = 1
    windows.inputs["Brick Width"].default_value = 1.6
    windows.inputs["Row Height"].default_value = 3.6
    windows.inputs["Mortar Size"].default_value = 0.6
    windows.inputs["Bias"].default_value = 0
    windows.inputs["Color1"].default_value = (0, 0, 0, 1)
    windows.inputs["Color2"].default_value = (1, 1, 1, 1)
    links.new(uv.outputs[0], windows.inputs["Vector"])
    # Each window's own random shade picks whether it's lit.
    lit = nodes.new("ShaderNodeMath")
    lit.operation = "GREATER_THAN"
    lit.inputs[1].default_value = 0.8
    to_bw = nodes.new("ShaderNodeRGBToBW")
    links.new(windows.outputs["Color"], to_bw.inputs[0])
    links.new(to_bw.outputs[0], lit.inputs[0])
    glass = nodes.new("ShaderNodeMath")
    glass.operation = "SUBTRACT"
    glass.inputs[0].default_value = 1
    links.new(windows.outputs["Fac"], glass.inputs[1])
    # Only on walls, never on the roofs.
    normal = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Normal"], normal.inputs[0])
    upright = nodes.new("ShaderNodeMath")
    upright.operation = "LESS_THAN"
    upright.inputs[1].default_value = 0.5
    absolute = nodes.new("ShaderNodeMath")
    absolute.operation = "ABSOLUTE"
    links.new(normal.outputs["Z"], absolute.inputs[0])
    links.new(absolute.outputs[0], upright.inputs[0])
    window = nodes.new("ShaderNodeMath")
    window.operation = "MULTIPLY"
    links.new(glass.outputs[0], window.inputs[0])
    links.new(upright.outputs[0], window.inputs[1])
    glow = nodes.new("ShaderNodeMath")
    glow.operation = "MULTIPLY"
    links.new(window.outputs[0], glow.inputs[0])
    links.new(lit.outputs[0], glow.inputs[1])
    # Each building a slightly different stone, by where it stands.
    tint = nodes.new("ShaderNodeTexNoise")
    tint.inputs["Scale"].default_value = 0.02
    links.new(turned.outputs[0], tint.inputs["Vector"])
    stone = nodes.new("ShaderNodeValToRGB")
    stone.color_ramp.elements[0].color = (0.18, 0.17, 0.16, 1)
    stone.color_ramp.elements[1].color = (0.34, 0.31, 0.28, 1)
    links.new(tint.outputs["Fac"], stone.inputs["Fac"])
    color = nodes.new("ShaderNodeMix")
    color.data_type = "RGBA"
    links.new(window.outputs[0], color.inputs["Factor"])
    links.new(stone.outputs["Color"], color.inputs["A"])
    color.inputs["B"].default_value = (0.05, 0.07, 0.09, 1)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(color.outputs["Result"], bsdf.inputs["Base Color"])
    links.new(window.outputs[0], bsdf.inputs["Metallic"])
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.85
    rough.inputs["To Max"].default_value = 0.15
    links.new(window.outputs[0], rough.inputs["Value"])
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Emission Color"].default_value = (1, 0.72, 0.42, 1)
    strength = nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    strength.inputs[1].default_value = 0.9
    links.new(glow.outputs[0], strength.inputs[0])
    links.new(strength.outputs[0], bsdf.inputs["Emission Strength"])
    hazed_output(nodes, links, bsdf.outputs[0], haze, 9_000)
    return mat


def ground_material(haze):
    """Dark ground with the streets lit amber on the blocks' grid, fading into the haze."""
    mat = bpy.data.materials.new("Streets")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    _, turned = grid_vector(nodes, links)
    shift = nodes.new("ShaderNodeVectorMath")
    shift.operation = "ADD"
    shift.inputs[1].default_value = ((BLOCK + STREET) / 2, (BLOCK + STREET) / 2, 0)
    links.new(turned.outputs[0], shift.inputs[0])
    grid = nodes.new("ShaderNodeTexBrick")
    grid.offset = 0
    grid.inputs["Scale"].default_value = 1
    grid.inputs["Brick Width"].default_value = BLOCK + STREET
    grid.inputs["Row Height"].default_value = BLOCK + STREET
    grid.inputs["Mortar Size"].default_value = STREET / 2
    grid.inputs["Mortar Smooth"].default_value = 0.2
    links.new(shift.outputs[0], grid.inputs["Vector"])
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.04, 0.04, 0.045, 1)
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0
    bsdf.inputs["Emission Color"].default_value = (1, 0.6, 0.25, 1)
    strength = nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    strength.inputs[1].default_value = 0.35
    links.new(grid.outputs["Fac"], strength.inputs[0])
    links.new(strength.outputs[0], bsdf.inputs["Emission Strength"])
    hazed_output(nodes, links, bsdf.outputs[0], haze, 12_000)
    return mat


options = arguments()
bpy.ops.wm.read_factory_settings(use_empty=True)
build_world(options["hdri"], float(options.get("rotation", 0)), float(options.get("strength", 1)))
camera = build_camera()
camera.data.clip_end = 2 * REACH
haze = horizon_color(options["hdri"])
city = build_city(random.Random(11))
city.data.materials.append(building_material(haze))
ground = build_ground()
ground.data.materials.append(ground_material(haze))
configure_render(options)
if os.path.exists(options["out"]):
    os.remove(options["out"])
if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
    raise SystemExit("render failed: " + options["out"])
print("rendered", options["out"])

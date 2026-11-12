#
#  lighthouse.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  A lighthouse for the visionOS cinema: the lantern room at the top of a white tower on a headland
#  at sunset, built on room_base.py. Run with build.sh, not by hand:
#
#    Blender -b -P lighthouse.py -- --out out/lighthouse.png --width 4096 --samples 160
#
#  The lantern is a twelve-sided room glazed all round above a low iron parapet, with a wide sill
#  shelf under the glass, under a dome whose red cornice shows along the top of every pane. Outside
#  is the gallery and its railing, low enough that the sill hides it from the seat. The screen hangs
#  in the two front bays, the whiteboards the app draws the team roster and the nodes' status
#  messages on hang in two bays on the left, and the print it draws the latest trace route on in one
#  on the right, all with the view round them. Behind the seat the Fresnel lens stands on its iron
#  pedestal, lit; beside it are the hatch down to the watch room and the door out to the gallery.
#  The sunset lights the room but isn't painted: the app puts the sea, or real terrain, behind the
#  glass.

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
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
    torus,
)

# MARK: - The lantern (meters)

# Twelve sides, a corner straight ahead, so the two front panes meet behind the screen.
SIDES = 12
STEP = 2 * math.pi / SIDES
# The glass's inner face is APOTHEM from the seat across the middle of each pane.
APOTHEM = 2.4
WALL = 0.1
# The iron parapet, low, then the glass up to the head, then the cornice ring and the dome.
KNEE = 0.62
HEAD = 2.45
RING_TOP = 2.7
DOME_TOP = 3.55
SILL_DEPTH = 0.3
DOOR_RAIL = 1.0
MULLION = 0.07
# The gallery outside and its railing. The parapet is low, so the sea below shows over the sill
# down to about 14° below level, and the railing is kept under that line (a real one is waist
# high), so it never runs across the water in front of the nodes the app marks out there.
GALLERY = 1.0
RAIL = 0.3

DEVICE_MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Meshtastic", "Resources", "DeviceModels")

# The bays by their middles' angles, clockwise from straight ahead. The two front bays, at ±15°,
# are behind the screen.
ROSTER = -45
STATUS = -75
TRACE = 75
DOOR = 135
# The Fresnel lens stands behind the seat, a little off the middle so the hatch beside it clears.
LENS = (0.0, -1.55)
HATCH = (-1.25, -1.05)


def polar(angle, radius, z=0.0):
    """The point `radius` from the seat at `angle` degrees clockwise from straight ahead."""
    a = math.radians(angle)
    return Vector((radius * math.sin(a), radius * math.cos(a), z))


def corner_radius(apothem):
    return apothem / math.cos(STEP / 2)


def bay_angles():
    return [15 + 30 * i for i in range(SIDES)]


def wrap(angle):
    return (angle + 180) % 360 - 180


def facing(angle):
    """The rotation that stands a plane() up at `angle`, its face toward the seat and its +X to the
    viewer's right as they face it."""
    return (math.pi / 2, 0, -math.radians(angle))


def yaw(angle):
    """Turns a box built with its length along X and its thickness along Y so its length runs along
    the bay at `angle` and its thickness points out."""
    return (0, 0, -math.radians(angle))


# MARK: - Materials

def painted_iron(name, color, roughness=0.45):
    """Painted cast iron: a little orange peel in the paint."""
    mat = material(name, color, roughness)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 140
    noise.inputs["Detail"].default_value = 3
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def floor_plates(name):
    """The floor: cast iron plates in a radial pattern, painted red oxide and worn paler where the
    keepers walk round the lens."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.55
    coords = nodes.new("ShaderNodeTexCoord")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coords.outputs["Object"], split.inputs[0])
    # Rings 0.6 m apart and twelve spokes: the plates' seams.
    radius = nodes.new("ShaderNodeVectorMath")
    radius.operation = "LENGTH"
    flat = nodes.new("ShaderNodeCombineXYZ")
    links.new(split.outputs["X"], flat.inputs["X"])
    links.new(split.outputs["Y"], flat.inputs["Y"])
    links.new(flat.outputs[0], radius.inputs[0])
    ring = nodes.new("ShaderNodeMath")
    ring.operation = "PINGPONG"
    ring.inputs[1].default_value = 0.3
    links.new(radius.outputs["Value"], ring.inputs[0])
    seam = nodes.new("ShaderNodeMath")
    seam.operation = "LESS_THAN"
    seam.inputs[1].default_value = 0.006
    links.new(ring.outputs[0], seam.inputs[0])
    angle = nodes.new("ShaderNodeMath")
    angle.operation = "ARCTAN2"
    links.new(split.outputs["X"], angle.inputs[0])
    links.new(split.outputs["Y"], angle.inputs[1])
    spoke = nodes.new("ShaderNodeMath")
    spoke.operation = "MULTIPLY"
    spoke.inputs[1].default_value = SIDES / (2 * math.pi)
    links.new(angle.outputs[0], spoke.inputs[0])
    frac = nodes.new("ShaderNodeMath")
    frac.operation = "PINGPONG"
    frac.inputs[1].default_value = 0.5
    links.new(spoke.outputs[0], frac.inputs[0])
    # Scaled by the radius so the spoke seams stay the same width all the way out.
    across = nodes.new("ShaderNodeMath")
    across.operation = "MULTIPLY"
    links.new(frac.outputs[0], across.inputs[0])
    links.new(radius.outputs["Value"], across.inputs[1])
    spoke_seam = nodes.new("ShaderNodeMath")
    spoke_seam.operation = "LESS_THAN"
    spoke_seam.inputs[1].default_value = 0.004
    links.new(across.outputs[0], spoke_seam.inputs[0])
    seams = nodes.new("ShaderNodeMath")
    seams.operation = "MAXIMUM"
    links.new(seam.outputs[0], seams.inputs[0])
    links.new(spoke_seam.outputs[0], seams.inputs[1])
    # Worn paler in a band round the lens and toward the hatch.
    wear = nodes.new("ShaderNodeTexNoise")
    wear.inputs["Scale"].default_value = 3
    wear.inputs["Detail"].default_value = 6
    links.new(coords.outputs["Object"], wear.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.4
    ramp.color_ramp.elements[0].color = (0.11, 0.045, 0.035, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.19, 0.09, 0.07, 1)
    links.new(wear.outputs["Fac"], ramp.inputs["Fac"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(seams.outputs[0], mix.inputs["Factor"])
    links.new(ramp.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (0.04, 0.015, 0.01, 1)
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def glass_material():
    mat = bpy.data.materials.new("Glass")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.03
    return mat


def lens_glass():
    """The lens's prisms: real crown glass, a little green at the edges."""
    mat = bpy.data.materials.new("LensGlass")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.86, 0.95, 0.9, 1)
    bsdf.inputs["Transmission Weight"].default_value = 1
    bsdf.inputs["Roughness"].default_value = 0.02
    bsdf.inputs["IOR"].default_value = 1.52
    return mat


def glowing(name, path, strength):
    mat = image_material(name, path, 0.3)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    links.new(nodes["Image Texture"].outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


# MARK: - The lantern

def ring(name, inner, outer, bottom, top, mat, bays=None):
    """A twelve-sided band between the apothems `inner` and `outer`, from `bottom` to `top`, one
    segment per bay. `bays` lists the bays' middle angles to build; all of them by default."""
    wanted = set(bays if bays is not None else bay_angles())

    def build(bm):
        for angle in bay_angles():
            if angle not in wanted:
                continue
            left, right = angle - 15, angle + 15
            corners = [polar(left, corner_radius(inner)), polar(right, corner_radius(inner)),
                       polar(right, corner_radius(outer)), polar(left, corner_radius(outer))]
            low = [bm.verts.new((c.x, c.y, bottom)) for c in corners]
            high = [bm.verts.new((c.x, c.y, top)) for c in corners]
            bm.faces.new(low)
            bm.faces.new(high)
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((low[i], low[j], high[j], high[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, build, mat)


def polygon_disc(name, apothem, z, mat):
    def build(bm):
        verts = [bm.verts.new(polar(15 + 30 * i - 15, corner_radius(apothem), z)) for i in range(SIDES)]
        bm.faces.new(verts)
    return mesh_object(name, build, mat)


def build_lantern():
    cream = painted_iron("Parapet", (0.82, 0.8, 0.72))
    frame = painted_iron("Frame", (0.035, 0.05, 0.045), 0.35)
    sill = material("Sill", (0.48, 0.34, 0.19), 0.45)
    glass = glass_material()
    red = painted_iron("DomeRed", (0.42, 0.035, 0.025), 0.4)
    dome_inside = painted_iron("DomeInside", (0.62, 0.6, 0.55), 0.6)
    gallery = painted_iron("Gallery", (0.18, 0.18, 0.17), 0.6)

    polygon_disc("Floor", APOTHEM + 0.05, 0.0, floor_plates("FloorPlates"))
    # The gallery deck outside, and its railing.
    ring("GalleryDeck", APOTHEM + WALL, APOTHEM + WALL + GALLERY, -0.08, -0.02, gallery)
    build_railing(frame)

    others = [a for a in bay_angles() if a != DOOR]
    # The parapet up to the sill, with the sill shelf inside it and a drip ledge outside. The door's
    # bay has none; the door stands in it from the floor.
    ring("Parapet", APOTHEM, APOTHEM + WALL, 0.0, KNEE, cream, others)
    ring("Sill", APOTHEM - SILL_DEPTH, APOTHEM + 0.02, KNEE, KNEE + 0.035, sill, others)
    ring("Drip", APOTHEM + WALL, APOTHEM + WALL + 0.05, KNEE - 0.04, KNEE, frame, others)
    # A dark plinth along the floor, and a raised panel on each bay's parapet.
    ring("Plinth", APOTHEM - 0.02, APOTHEM, 0.0, 0.12, frame, others)
    for angle in others:
        width = 2 * (APOTHEM - 0.01) * math.tan(STEP / 2) - 0.24
        box("ParapetPanel", (width, 0.018, KNEE - 0.36), polar(angle, APOTHEM - 0.009, 0.12 + (KNEE - 0.12) / 2 + 0.02), cream, rotation=yaw(angle), bevel=0.006)
    # The cornice ring over the glass, and the dome over it.
    ring("Header", APOTHEM, APOTHEM + WALL, HEAD, RING_TOP, cream)
    ring("Cornice", APOTHEM + WALL, APOTHEM + 0.42, RING_TOP - 0.02, RING_TOP + 0.06, red)
    # The cornice's deep lip, hanging over the glass outside: it shows as a red band along the top
    # of every pane from the seat.
    ring("CorniceLip", APOTHEM + 0.36, APOTHEM + 0.42, HEAD - 0.12, RING_TOP, red)
    build_dome(dome_inside, red, frame)

    for angle in bay_angles():
        if angle == DOOR:
            build_door(angle, frame, glass)
            continue
        # The pane, on the middle of the glazing.
        center = polar(angle, APOTHEM + WALL / 2, (KNEE + HEAD) / 2)
        width = 2 * (APOTHEM + WALL / 2) * math.tan(STEP / 2) - MULLION
        plane("Pane", width, HEAD - KNEE, center, facing(angle), glass)
        # A horizontal astragal across it, a little above the middle.
        box("Astragal", (width, 0.03, 0.025), polar(angle, APOTHEM + WALL / 2, KNEE + (HEAD - KNEE) * 0.6), frame, rotation=yaw(angle))
    # The mullions at the corners, from the sill to the head.
    for i in range(SIDES):
        corner = 30 * i
        box("Mullion", (MULLION, MULLION, HEAD - KNEE + 0.02), polar(corner, corner_radius(APOTHEM + WALL / 2), (KNEE + HEAD) / 2), frame, rotation=yaw(corner))
    # The door's bay has its mullions down to the floor.
    for corner in (DOOR - 15, DOOR + 15):
        box("DoorJamb", (MULLION, MULLION, KNEE), polar(corner, corner_radius(APOTHEM + WALL / 2), KNEE / 2), frame, rotation=yaw(corner))


def build_dome(inside, red, frame):
    """The dome over the lantern: a shallow cone of iron plates inside, cream with dark ribs, rising
    to the ventilator, and red outside."""
    segments = SIDES * 4

    def build(bm):
        base = [bm.verts.new(polar(360 * i / segments, corner_radius(APOTHEM), RING_TOP)) for i in range(segments)]
        rings = [base]
        for step in range(1, 7):
            t = step / 7
            r = corner_radius(APOTHEM) * (1 - t) + 0.18 * t
            z = RING_TOP + (DOME_TOP - RING_TOP) * math.sin(t * math.pi / 2)
            rings.append([bm.verts.new(polar(360 * i / segments, r, z)) for i in range(segments)])
        for low, high in zip(rings, rings[1:]):
            for i in range(segments):
                j = (i + 1) % segments
                bm.faces.new((low[i], low[j], high[j], high[i]))
        bm.faces.new(list(reversed(rings[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    dome = mesh_object("Dome", build, inside)
    smooth(dome)
    # Ribs under the dome from each corner to the ventilator.
    for i in range(SIDES):
        start = polar(30 * i, corner_radius(APOTHEM) - 0.02, RING_TOP)
        end = polar(30 * i, 0.2, DOME_TOP - 0.05)
        cylinder("DomeRib", 0.016, start, end, frame, segments=8)
    cylinder("Ventilator", 0.2, (0, 0, DOME_TOP - 0.06), (0, 0, DOME_TOP + 0.1), frame, segments=32)
    torus("VentRing", 0.2, 0.02, (0, 0, DOME_TOP - 0.06), frame)


def build_railing(rail):
    """The gallery railing: a stanchion at every corner, a top rail and a middle rail."""
    out = APOTHEM + WALL + GALLERY - 0.06
    for i in range(SIDES):
        corner = 30 * i
        box("Stanchion", (0.05, 0.05, RAIL), polar(corner, corner_radius(out), RAIL / 2), rail, rotation=yaw(corner))
    for angle in bay_angles():
        length = 2 * out * math.tan(STEP / 2)
        box("TopRail", (length, 0.06, 0.035), polar(angle, out, RAIL), rail, rotation=yaw(angle))
        box("MidRail", (length, 0.03, 0.03), polar(angle, out, RAIL * 0.5), rail, rotation=yaw(angle))


def build_door(angle, frame, glass):
    """The door out to the gallery: iron, with a glazed upper half and Chirpy's poster on the inside
    of its lower panel."""
    # The door's solid lower panel is taller than the parapet, as a door's is.
    width = 2 * (APOTHEM + WALL / 2) * math.tan(STEP / 2) - MULLION
    paint = painted_iron("Door", (0.82, 0.8, 0.72))
    r = APOTHEM + WALL / 2
    box("DoorLower", (width, 0.035, DOOR_RAIL), polar(angle, r, DOOR_RAIL / 2), paint, rotation=yaw(angle))
    plane("DoorGlass", width - 0.1, HEAD - DOOR_RAIL - 0.08, polar(angle, r, (DOOR_RAIL + HEAD) / 2), facing(angle), glass)
    for du in (-width / 2 + 0.03, width / 2 - 0.03):
        offset = polar(angle + 90, du)
        box("DoorStile", (0.06, 0.05, HEAD - DOOR_RAIL), polar(angle, r, (DOOR_RAIL + HEAD) / 2) + offset, paint, rotation=yaw(angle))
    box("DoorRail", (width, 0.045, 0.06), polar(angle, r, DOOR_RAIL + 0.03), paint, rotation=yaw(angle))
    box("DoorTop", (width, 0.045, 0.05), polar(angle, r, HEAD - 0.025), paint, rotation=yaw(angle))
    brass = material("Brass", (0.78, 0.6, 0.3), 0.3, metallic=1.0)
    inward = -polar(angle, 1.0)
    knob = polar(angle, r - 0.02, DOOR_RAIL - 0.08) + polar(angle + 90, -width / 2 + 0.1)
    cylinder("DoorKnobRose", 0.034, knob, knob + inward * 0.01, brass, segments=32)
    cylinder("DoorKnobNeck", 0.012, knob, knob + inward * 0.075, brass, segments=16)
    sphere("DoorKnob", 0.04, knob + inward * 0.075, brass, segments=24)
    poster = image_material("ChirpyPoster", os.path.join(CACHE, "chirpy_poster.png"), 0.7)
    plane("Poster", 0.38, 0.53, polar(angle, r - 0.02, 0.62), facing(angle), poster)


# MARK: - The lens

def lens():
    """A third-order Fresnel lens on its cast iron pedestal behind the seat: a belt of refracting
    prisms round the middle, with rings of reflecting prisms above and below in a beehive, held in a
    brass frame, the lamp lit inside."""
    x, y = LENS
    iron = painted_iron("Pedestal", (0.07, 0.08, 0.075), 0.4)
    brass = material("LensBrass", (0.74, 0.56, 0.26), 0.25, metallic=1.0)
    glass = lens_glass()
    # The pedestal: a stepped octagonal base, a fluted column and a turned capital carrying the
    # lens table.
    cylinder("PedestalBase", 0.42, (x, y, 0), (x, y, 0.08), iron, segments=8)
    cylinder("PedestalStep", 0.34, (x, y, 0.08), (x, y, 0.16), iron, segments=8)
    cylinder("PedestalColumn", 0.17, (x, y, 0.16), (x, y, 0.92), iron, segments=24)
    for k in range(12):
        a = 2 * math.pi * k / 12
        cylinder("Flute", 0.018, (x + 0.17 * math.cos(a), y + 0.17 * math.sin(a), 0.22), (x + 0.17 * math.cos(a), y + 0.17 * math.sin(a), 0.86), iron, segments=8)
    cylinder("Capital", 0.3, (x, y, 0.92), (x, y, 1.0), iron, segments=32)
    cylinder("LensTable", 0.46, (x, y, 1.0), (x, y, 1.04), brass, segments=48)

    base = 1.04
    middle = base + 0.62
    # The belt: refracting prisms as stacked rings bulging round the middle.
    belt = 0.42
    for k in range(9):
        z = middle - belt / 2 + belt * (k + 0.5) / 9
        r = 0.42 + 0.02 * math.cos((k - 4) / 4 * math.pi / 2)
        torus("BeltPrism", r, 0.024, (x, y, z), glass)
    # The reflecting prisms in rings narrowing above and below.
    for sign in (1, -1):
        for k in range(7):
            t = (k + 0.5) / 7
            z = middle + sign * (belt / 2 + 0.03 + 0.34 * t)
            r = 0.42 * (1 - 0.62 * t ** 1.3)
            torus("CatadioptricPrism", r, 0.02, (x, y, z), glass)
    # The brass frame: bands at the belt's edges and the ends, and twelve ribs following the profile.
    for z, r in ((middle - belt / 2 - 0.015, 0.45), (middle + belt / 2 + 0.015, 0.45), (middle + 0.4, 0.16), (middle - 0.4, 0.16)):
        torus("LensBand", r, 0.012, (x, y, z), brass)
    for k in range(12):
        a = 2 * math.pi * k / 12
        profile = []
        for s in range(13):
            t = s / 12
            z = middle - 0.4 + 0.8 * t
            u = abs(z - middle)
            r = 0.455 if u < belt / 2 + 0.02 else 0.455 * (1 - 0.62 * ((u - belt / 2) / 0.37) ** 1.3)
            profile.append(Vector((x + r * math.cos(a), y + r * math.sin(a), z)))
        for p, q in zip(profile, profile[1:]):
            cylinder("LensRib", 0.008, p, q, brass, segments=6)
    # The crown on top and the lamp chimney through it.
    cylinder("LensCrown", 0.16, (x, y, middle + 0.4), (x, y, middle + 0.46), brass, segments=32)
    cylinder("LampChimney", 0.045, (x, y, middle + 0.46), (x, y, middle + 0.8), brass, segments=20)
    torus("ChimneyRing", 0.05, 0.008, (x, y, middle + 0.8), brass)
    cylinder("LensFoot", 0.16, (x, y, base), (x, y, middle - 0.4), brass, segments=32)
    # The lamp inside: a bright mantle, and its light.
    mantle = sphere("LampMantle", 0.05, (x, y, middle), material("LampMantle", (1, 0.95, 0.85), emission=(1, 0.86, 0.6), strength=60), segments=16)
    mantle.visible_shadow = False
    light = bpy.data.lights.new("Lamp", "POINT")
    light.energy = 140
    light.color = (1, 0.82, 0.55)
    light.shadow_soft_size = 0.05
    obj = bpy.data.objects.new("Lamp", light)
    obj.location = (x, y, middle)
    link(obj)
    # The lens's light on the floor and the dome round it, as its prisms throw it.
    for height, energy in ((0.25, 30), (DOME_TOP - 0.4, 25)):
        fill = bpy.data.lights.new("LensFill", "POINT")
        fill.energy = energy
        fill.color = (1, 0.8, 0.5)
        fill.shadow_soft_size = 0.4
        obj = bpy.data.objects.new("LensFill", fill)
        obj.location = (x, y + 0.6, height)
        link(obj)


# MARK: - Furniture

def hatch():
    """The hatch down to the watch room behind the seat on the left, open, with the ladder's rails
    coming up through it."""
    x, y = HATCH
    iron = painted_iron("Hatch", (0.07, 0.08, 0.075), 0.45)
    dark = material("HatchHole", (0.01, 0.008, 0.006), 0.9)
    plane("HatchHole", 0.7, 0.7, (x, y, 0.002), (0, 0, 0), dark)
    for dx, dy, sx, sy in ((0, 0.37, 0.78, 0.04), (0, -0.37, 0.78, 0.04), (0.37, 0, 0.04, 0.7), (-0.37, 0, 0.04, 0.7)):
        box("HatchCoaming", (sx, sy, 0.05), (x + dx, y + dy, 0.025), iron)
    # The cover, thrown open on its hinge and lying on the floor behind the hole, its two hinges
    # on the coaming.
    box("HatchCover", (0.72, 0.72, 0.03), (x, y - 0.78, 0.015), iron, bevel=0.004)
    for dx in (-0.22, 0.22):
        cylinder("HatchHinge", 0.018, (x + dx - 0.05, y - 0.41, 0.03), (x + dx + 0.05, y - 0.41, 0.03), iron, segments=12)
    ring_handle = material("HatchRing", (0.6, 0.45, 0.2), 0.3, metallic=1.0)
    torus("HatchRing", 0.05, 0.007, (x, y - 1.05, 0.034), ring_handle)
    # The ladder's rails and a guard rail round two sides.
    for dx in (-0.22, 0.22):
        cylinder("LadderRail", 0.02, (x + dx, y + 0.2, -0.3), (x + dx, y + 0.28, 0.9), iron, segments=12)
    cylinder("LadderTop", 0.02, (x - 0.22, y + 0.28, 0.9), (x + 0.22, y + 0.28, 0.9), iron, segments=12)


def stool():
    wood = material("Stool", (0.45, 0.31, 0.17), 0.5)
    x, y = 1.05, -0.95
    cylinder("StoolSeat", 0.17, (x, y, 0.43), (x, y, 0.46), wood, segments=32)
    for a in (0.5, 2.6, 4.7):
        foot = (x + 0.14 * math.cos(a), y + 0.14 * math.sin(a), 0)
        cylinder("StoolLeg", 0.015, foot, (x + 0.1 * math.cos(a), y + 0.1 * math.sin(a), 0.43), wood)


def oil_can(x, y, z):
    """A brass keeper's oil can with a long spout."""
    brass = material("OilCan", (0.7, 0.52, 0.24), 0.3, metallic=1.0)
    cylinder("OilCanBody", 0.07, (x, y, z), (x, y, z + 0.09), brass, segments=24)
    cylinder("OilCanTop", 0.03, (x, y, z + 0.09), (x, y, z + 0.13), brass, segments=16)
    cylinder("OilCanSpout", 0.006, (x, y, z + 0.11), (x + 0.16, y + 0.05, z + 0.2), brass, segments=8)


def sill_things():
    """On the right sill: the VHF radio, a Meshtastic radio and the logbook. Binoculars on the front
    sill beside the screen, and the oil can by the lens."""
    body = material("RadioBody", (0.06, 0.06, 0.065), 0.4, metallic=0.3)
    knob = material("Knob", (0.02, 0.02, 0.02), 0.35)
    shelf = KNEE + 0.035
    angle = 105
    r = APOTHEM - 0.16
    center = polar(angle, r, shelf)
    box("VHFRadio", (0.26, 0.22, 0.09), center + Vector((0, 0, 0.045)), body, rotation=yaw(angle), bevel=0.004)
    inward = -polar(angle, 1.0)
    side = polar(angle + 90, 1.0)
    plane("VHFDisplay", 0.1, 0.03, center + inward * 0.111 + side * 0.04 + Vector((0, 0, 0.06)), facing(angle + 180), glowing("VHFDisplay", os.path.join(CACHE, "lookout_radio.png"), 2.5))
    cylinder("VHFKnob", 0.018, center + inward * 0.11 - side * 0.08 + Vector((0, 0, 0.05)), center + inward * 0.13 - side * 0.08 + Vector((0, 0, 0.05)), knob, segments=20)
    t = polar(angle - 9, r)
    place_model("t-echo.usdz", (t.x, t.y), math.radians(-angle - 20), flat=False)
    # The logbook, closed, on the sill past the radio.
    book = polar(angle + 14, r)
    box("Logbook", (0.24, 0.3, 0.035), (book.x, book.y, shelf + 0.018), material("LogbookCover", (0.08, 0.16, 0.12), 0.6), rotation=yaw(angle + 5), bevel=0.004)
    box("LogbookPages", (0.23, 0.29, 0.028), (book.x, book.y, shelf + 0.018), material("Pages", (0.85, 0.82, 0.72), 0.8), rotation=yaw(angle + 5))
    b = polar(40, APOTHEM - 0.17)
    binoculars((b.x, b.y), math.radians(-60), shelf)
    oil_can(LENS[0] + 0.55, LENS[1] + 0.1, 0.0)


def tube(name, radius, start, end, mat, segments=48):
    obj = cylinder(name, radius, start, end, mat, segments=segments)
    bevel = obj.modifiers.new("Bevel", "BEVEL")
    bevel.width = min(radius * 0.15, 0.003)
    bevel.segments = 3
    bevel.harden_normals = True
    return obj


def binoculars(center, turn_angle, shelf):
    """Porro prism binoculars lying on the sill, as in the fire lookout."""
    armor = material("BinocularArmor", (0.035, 0.04, 0.035), 0.8)
    metal = material("BinocularMetal", (0.07, 0.07, 0.075), 0.3, metallic=0.85)
    glass = material("BinocularLens", (0.12, 0.08, 0.22), 0.04, metallic=0.7)
    turn = Matrix.Rotation(turn_angle, 3, "Z")

    def at_local(x, y, z):
        return Vector(center + (0,)) + turn @ Vector((x, y, 0)) + Vector((0, 0, shelf + z))

    r = 0.029
    for side in (-1, 1):
        x = side * 0.05
        tube("BinocularBarrel", r, at_local(x, 0.0, r), at_local(x, 0.085, r), armor)
        tube("BinocularRim", r + 0.002, at_local(x, 0.082, r), at_local(x, 0.092, r), metal)
        tube("BinocularLens", r - 0.005, at_local(x, 0.088, r), at_local(x, 0.0925, r), glass, segments=32)
        box("BinocularPrism", (0.058, 0.07, 0.05), at_local(side * 0.044, -0.03, r + 0.002), armor, rotation=(0, 0, turn_angle), bevel=0.01)
        ex = side * 0.032
        tube("BinocularEyepiece", 0.014, at_local(ex, -0.06, r + 0.006), at_local(ex, -0.09, r + 0.006), metal)
        tube("BinocularEyecup", 0.019, at_local(ex, -0.09, r + 0.006), at_local(ex, -0.108, r + 0.006), armor)
    tube("BinocularHinge", 0.011, at_local(0, -0.075, r + 0.012), at_local(0, 0.05, r + 0.012), metal)
    tube("BinocularFocus", 0.017, at_local(0, -0.058, r + 0.012), at_local(0, -0.036, r + 0.012), armor)


def place_model(file_name, at_xy, turn, flat):
    """Puts one of the app's device models on the sill shelf at real size."""
    path = os.path.abspath(os.path.join(DEVICE_MODELS, file_name))
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [obj for obj in bpy.data.objects if obj not in before]
    root = next(obj for obj in new if obj.parent is None)
    tip = Matrix.Rotation(-math.pi / 2, 4, "X") if flat else Matrix.Rotation(math.pi / 2, 4, "Z")
    root.matrix_world = Matrix.Rotation(turn, 4, "Z") @ tip @ root.matrix_world
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(corner) for obj in new if obj.type == "MESH" for corner in obj.bound_box]
    low = min(c.z for c in corners)
    cx = (min(c.x for c in corners) + max(c.x for c in corners)) / 2
    cy = (min(c.y for c in corners) + max(c.y for c in corners)) / 2
    root.matrix_world = Matrix.Translation((at_xy[0] - cx, at_xy[1] - cy, KNEE + 0.035 - low)) @ root.matrix_world


# MARK: - Boards

def board_light(name, location, target, width, energy):
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = width, 0.3
    light.energy = energy
    light.color = (1, 0.75, 0.5)
    light.spread = math.radians(70)
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector(target) - obj.location).to_track_quat("-Z", "Y")
    obj.visible_camera = False
    obj.visible_glossy = False
    link(obj)


def hang_board(board_id, angle, width, height, surface_mat, frame):
    """A board in a thin dark frame inside the glass of the bay at `angle`, clipped to the mullions
    either side, with a hidden light on it."""
    z = (KNEE + HEAD) / 2
    r = APOTHEM - 0.02
    box(board_id + "Frame", (width + 0.05, 0.02, height + 0.05), polar(angle, r + 0.01, z), frame, rotation=yaw(angle), bevel=0.003)
    surface = plane(board_id, width, height, polar(angle, r, z), facing(angle), surface_mat)
    anchor(board_id, surface, width, height)
    center = polar(angle, r, z)
    board_light(board_id + "Light", center - polar(angle, 0.9) + Vector((0, 0, 0.75)), center + Vector((0, 0, 0.05)), width - 0.2, 2.6)


def build_boards():
    frame = material("BoardFrame", (0.03, 0.03, 0.032), 0.5)
    board = image_material("Whiteboard", os.path.join(CACHE, "whiteboard.png"), 0.25)
    hang_board("teamStatus", ROSTER, 0.95, 0.633, board, frame)
    hang_board("nodeStatus", STATUS, 0.95, 0.633, board, frame)
    hang_board("traceRoute", TRACE, 0.9, 0.74, material("PrintMat", (0.86, 0.85, 0.82), 0.85), frame)


def build():
    build_lantern()
    lens()
    hatch()
    stool()
    sill_things()
    build_boards()
    # Across the two front panes, in front of the corner mullion between them.
    screen_anchor((0, 2.08, EYE_HEIGHT + 0.36), (math.pi / 2, 0, 0), width=2.0)


# Kiara 8 at sunset, turned so the sun is on the viewer's left, a little behind, low over the sea:
# it lights the room through the left panes and leaves the screen out of its glare. The same sky
# turned to match puts the sun there in the sea view and behind real terrain (sky.py).
render_room(build, "kiara_8_sunset_8k.hdr", hdri_rotation=129, hdri_strength=1.0, cutout=True)

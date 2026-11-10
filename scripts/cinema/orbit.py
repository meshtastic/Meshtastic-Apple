#
#  orbit.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/9/26.
#
#  Where things are outside the space station, shared by the cupola (space_cupola.py) and the view
#  out of it (space_earth.py), so the light in the cupola comes from where the painted sun is.
#  Directions are from the viewer, in Blender's axes: +Y the image's center, +X right, Z up.

import math

from mathutils import Vector

# The station's height above the ground, and Earth's radius, in kilometers.
ALTITUDE = 420.0
EARTH_RADIUS = 6371.0

# Earth fills the view up and behind the seat: its center is this far round from the front,
# clockwise, and this far up. From 420 km it spans about 140°, so its edge crosses the cupola's
# front windows, with black space below it.
EARTH_AZIMUTH = 180.0
EARTH_ELEVATION = 64.0

# The sun, on the left in front and a little below level, behind the edge of the cupola's floor,
# so the ground under the station is in daylight with night coming over Earth's edge on the right.
SUN_AZIMUTH = -50.0
SUN_ELEVATION = -10.0

# The point on the ground straight under the station, and the way north runs from it as seen
# from the seat: the Bahamas and Florida, with north toward the front.
NADIR_LATITUDE = 25.0
NADIR_LONGITUDE = -78.0
NORTH = Vector((0.35, 1.0, 0.0))


def direction(azimuth, elevation):
    """A unit vector `azimuth` degrees clockwise from the front and `elevation` degrees up."""
    a, e = math.radians(azimuth), math.radians(elevation)
    return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))


def sun_direction():
    return direction(SUN_AZIMUTH, SUN_ELEVATION)


def earth_direction():
    return direction(EARTH_AZIMUTH, EARTH_ELEVATION)

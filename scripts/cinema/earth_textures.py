#
#  earth_textures.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 11/10/26.
#
#  Makes the textures of the globe the app turns behind the space station's cupola, from NASA's
#  public domain imagery in cache/: the ground (the Blue Marble Next Generation for July, with
#  topography and bathymetry), the city lights for its night side (the Black Marble 2016), and the
#  clouds over it (the Blue Marble 2002 cloud layer). Each is equirectangular, longitude -180 at
#  the left and north at the top, written to out/ as PNG for build.sh to turn into HEIC. Run with
#  build.sh, not by hand.

import os
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
OUT = os.path.join(HERE, "out")
WIDTH = 4096


def load(name, mode):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        raise SystemExit(f"missing {path}: build.sh downloads it")
    return Image.open(path).convert(mode)


def ground():
    """The Blue Marble, lifted a little: as a texture lit by one sun it reads dark and flat."""
    image = load("world.topo.bathy.200407.3x21600x10800.jpg", "RGB").resize((WIDTH, WIDTH // 2), Image.LANCZOS)
    pixels = np.asarray(image).astype(np.float32) / 255
    pixels = np.clip((pixels - 0.5) * 1.12 + 0.5 + 0.04, 0, 1)
    Image.fromarray((pixels * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "space_earth_ground.png"))


def lights():
    """The Black Marble's lights in a sodium orange, the dim glow of the countryside pushed down so
    only towns and cities shine."""
    image = load("BlackMarble_2016_3km_gray.jpg", "L").resize((WIDTH, WIDTH // 2), Image.LANCZOS)
    value = (np.asarray(image).astype(np.float32) / 255) ** 2.2
    tint = np.array([1.0, 0.68, 0.36], dtype=np.float32)
    pixels = np.clip(value[..., None] * tint * 1.6, 0, 1)
    Image.fromarray((pixels * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "space_earth_lights.png"))


def clouds():
    """The cloud layer as gray, how much cloud there is at each point; the app uses it as the
    cloud shell's opacity. NASA publishes it at 2048 wide, which is plenty for soft cloud."""
    image = load("cloud_combined_2048.jpg", "L")
    value = np.asarray(image).astype(np.float32) / 255
    # Thin haze to nothing, so the ground shows clear between the clouds.
    value = np.clip((value - 0.12) / 0.88, 0, 1) ** 1.2
    Image.fromarray((value * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, "space_earth_clouds.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for make in (ground, lights, clouds):
        make()
        print("made", make.__name__)
    sys.exit(0)

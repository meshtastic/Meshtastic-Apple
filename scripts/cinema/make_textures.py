#!/usr/bin/env python3
#
#  make_textures.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  Draws the flat textures the SAR tent scene uses: a topo map, the team status whiteboard and a
#  laptop showing a mesh map. Everything is generated here, so the tent image has no third-party
#  artwork in it. Writes PNGs into cache/.

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "cache")
FONT_DIR = "/System/Library/Fonts/Supplemental"


def font(name, size):
    try:
        return ImageFont.truetype(os.path.join(FONT_DIR, name), size)
    except OSError:
        return ImageFont.load_default()


def fractal_noise(w, h, seed, octaves=6):
    rng = np.random.default_rng(seed)
    result = np.zeros((h, w))
    amplitude = 1.0
    for octave in range(octaves):
        cells = 2 ** (octave + 2)
        grid = rng.random((cells + 1, cells + 1))
        small = Image.fromarray((grid * 255).astype(np.uint8))
        layer = np.asarray(small.resize((w, h), Image.BICUBIC), dtype=float) / 255
        result += layer * amplitude
        amplitude *= 0.5
    result -= result.min()
    return result / result.max()


def topo_map(path, w=2048, h=1536):
    height = fractal_noise(w, h, seed=7)
    paper = np.zeros((h, w, 3))
    # Green for forest, paler for open ground above the tree line.
    forest = np.array([0.80, 0.88, 0.72])
    open_ground = np.array([0.95, 0.93, 0.85])
    mix = np.clip((height - 0.55) * 4, 0, 1)[..., None]
    paper[:] = forest * (1 - mix) + open_ground * mix
    contour = np.abs((height * 40) % 1 - 0.5) > 0.47
    index = np.abs((height * 8) % 1 - 0.5) > 0.485
    brown = np.array([0.62, 0.42, 0.25])
    paper[contour] = paper[contour] * 0.35 + brown * 0.65
    paper[index] = brown * 0.8
    image = Image.fromarray((paper * 255).astype(np.uint8))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3)
    # A creek down the valley floor.
    x, y = 0, h * 0.62
    points = []
    while x < w:
        points.append((x, y))
        x += 40
        y += rng.uniform(-18, 18)
    draw.line(points, fill=(70, 120, 200), width=6)
    # A trail.
    trail = [(w * 0.1, h * 0.9), (w * 0.3, h * 0.7), (w * 0.45, h * 0.55), (w * 0.62, h * 0.4), (w * 0.85, h * 0.18)]
    for a, b in zip(trail, trail[1:]):
        steps = 30
        for i in range(0, steps, 2):
            t0, t1 = i / steps, (i + 1) / steps
            draw.line([(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0), (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)], fill=(160, 30, 30), width=5)
    # Search grid.
    for gx in range(0, w, 256):
        draw.line([(gx, 0), (gx, h)], fill=(40, 40, 40), width=3)
    for gy in range(0, h, 256):
        draw.line([(0, gy), (w, gy)], fill=(40, 40, 40), width=3)
    label = font("Arial Bold.ttf", 48)
    for i, gx in enumerate(range(0, w, 256)):
        for j, gy in enumerate(range(0, h, 256)):
            draw.text((gx + 10, gy + 8), f"{chr(65 + j)}{i + 1}", fill=(30, 30, 30), font=label)
    # Shaded search segments, in the highlighter colors teams use.
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([256, 512, 768, 1024], fill=(255, 220, 0, 70))
    od.rectangle([1024, 256, 1536, 768], fill=(255, 120, 0, 70))
    od.rectangle([1280, 1024, 1792, 1280], fill=(0, 200, 120, 70))
    image = Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")
    image.save(path)


def status_board(path, w=2400, h=1600):
    image = Image.new("RGB", (w, h), (246, 247, 244))
    draw = ImageDraw.Draw(image)
    pen = font("Chalkboard.ttc", 64)
    small = font("Chalkboard.ttc", 52)
    title = font("Chalkboard.ttc", 96)
    blue, black, red, green = (30, 60, 160), (25, 25, 25), (190, 30, 30), (20, 130, 60)
    draw.text((80, 50), "TEAM STATUS", fill=blue, font=title)
    draw.text((1500, 70), "OP PERIOD 2  1800–0600", fill=black, font=small)
    columns = [80, 520, 1240, 1760]
    headers = ["TEAM", "ASSIGNMENT", "STATUS", "LAST CHECK-IN"]
    for x, text in zip(columns, headers):
        draw.text((x, 230), text, fill=black, font=pen)
    draw.line([(60, 320), (w - 60, 320)], fill=black, width=6)
    rows = [
        ("Alpha", "Seg B2 – ridge", "In field", "1742", black),
        ("Bravo", "Seg C5 – creek", "In field", "1738", black),
        ("Charlie", "Seg D3 – trail", "Returning", "1729", green),
        ("K9-1", "Seg B6 – hasty", "In field", "1745", black),
        ("Medic", "ICP standby", "Available", "—", green),
        ("Relay", "Ridge repeater", "Up", "1750", blue),
    ]
    for i, (team, assignment, status, checkin, color) in enumerate(rows):
        y = 360 + i * 150
        draw.text((columns[0], y), team, fill=blue, font=pen)
        draw.text((columns[1], y), assignment, fill=black, font=pen)
        draw.text((columns[2], y), status, fill=color, font=pen)
        draw.text((columns[3], y), checkin, fill=black, font=pen)
        draw.line([(60, y + 120), (w - 60, y + 120)], fill=(170, 170, 170), width=3)
    draw.text((80, h - 160), "Comms: mesh ch. SAR-OPS  ·  Backup: VHF 155.160", fill=red, font=small)
    # Marker smudges, so it reads as a used board.
    smudge = Image.new("L", image.size, 0)
    sd = ImageDraw.Draw(smudge)
    rng = random.Random(11)
    for _ in range(14):
        x, y = rng.randint(0, w), rng.randint(0, h)
        sd.ellipse([x, y, x + rng.randint(120, 420), y + rng.randint(40, 120)], fill=rng.randint(8, 22))
    smudge = smudge.filter(ImageFilter.GaussianBlur(30))
    gray = Image.new("RGB", image.size, (150, 150, 160))
    image = Image.composite(gray, image, smudge)
    image.save(path)


def laptop_screen(path, w=1600, h=1000, seed=5):
    rng = random.Random(seed)
    image = Image.new("RGB", (w, h), (24, 30, 36))
    draw = ImageDraw.Draw(image)
    # Faint terrain behind the mesh.
    height = fractal_noise(w, h, seed=seed + 20, octaves=5)
    contour = np.abs((height * 24) % 1 - 0.5) > 0.46
    base = np.asarray(image, dtype=float)
    base[contour] = base[contour] * 0.5 + np.array([70, 90, 80]) * 0.5
    image = Image.fromarray(base.astype(np.uint8))
    draw = ImageDraw.Draw(image)
    nodes = [(rng.randint(120, w - 120), rng.randint(140, h - 120)) for _ in range(18)]
    for i, a in enumerate(nodes):
        for b in nodes[i + 1:]:
            if math.dist(a, b) < 360:
                draw.line([a, b], fill=(103, 234, 148), width=3)
    for x, y in nodes:
        draw.ellipse([x - 16, y - 16, x + 16, y + 16], fill=(103, 234, 148), outline=(230, 255, 240), width=3)
    draw.rectangle([0, 0, w, 70], fill=(36, 44, 52))
    draw.text((24, 14), "Mesh  ·  18 nodes", fill=(220, 230, 225), font=font("Arial Bold.ttf", 38))
    image.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    topo_map(os.path.join(OUT, "topo.png"))
    status_board(os.path.join(OUT, "status_board.png"))
    laptop_screen(os.path.join(OUT, "laptop_a.png"), seed=5)
    laptop_screen(os.path.join(OUT, "laptop_b.png"), seed=9)
    print("textures written to", OUT)


if __name__ == "__main__":
    main()

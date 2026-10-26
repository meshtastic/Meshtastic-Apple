#!/usr/bin/env python3
#
#  make_textures.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  Draws the flat textures the tent scenes use: a topo map, a blank whiteboard, and the Meshtastic
#  banner, Chirpy poster and Meshtastic Solutions plaque. The map and board are generated here.
#  The branding uses the app's own artwork, rasterized from its SVGs with resvg (the resvg-py
#  package), so it is never redrawn. Writes PNGs into cache/.
#  build.sh runs it with uv, which supplies Pillow, numpy and resvg-py.

import io
import math
import os
import random

import numpy as np
import resvg_py
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "cache")
FONT_DIR = "/System/Library/Fonts/Supplemental"

# The app's artwork, used as is.
MARK_SVG = os.path.join(ROOT, "Meshtastic/Resources/AppIcon.icon/Assets/Meshtastic Logo.svg")
WORDMARK_SVG = os.path.join(ROOT, "Meshtastic/Assets.xcassets/meshtastic-wordmark-white.imageset/meshtastic-wordmark-white.svg")
CHIRPY_SVG = os.path.join(ROOT, "Meshtastic/Assets.xcassets/Chirpy.imageset/chirpy.svg")
SOLUTIONS_SVG = os.path.join(ROOT, "Meshtastic/Assets.xcassets/MeshtasticSolutionsMark.imageset/meshtastic-solutions-mark.svg")
# Meshtastic's charcoal, the color of the banner and the plaque.
CHARCOAL = (44, 45, 60)


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


def whiteboard(path, w=2400, h=1600):
    """A blank whiteboard with a few marker smudges, so it reads as a used board. The app draws
    the live team roster over it."""
    image = Image.new("RGB", (w, h), (246, 247, 244))
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


def svg(path, width):
    """An SVG from the repo rasterized at `width` pixels, keeping its aspect and transparency."""
    data = resvg_py.svg_to_bytes(svg_path=path, width=width)
    return Image.open(io.BytesIO(bytes(data))).convert("RGBA")


def system_font(size, weight):
    """San Francisco at a named weight, like the app's system font."""
    face = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    face.set_variation_by_name(weight)
    return face


def weave(size, seed, strength):
    """A faint canvas weave to multiply over printed fabric, so the print sits in the cloth."""
    w, h = size
    rng = np.random.default_rng(seed)
    grain = rng.normal(0, 1, (h, w))
    rows = np.sin(np.arange(h) * math.pi / 2)[:, None] * 0.5
    cols = np.sin(np.arange(w) * math.pi / 2)[None, :] * 0.5
    shade = 1 + strength * (grain * 0.6 + rows + cols) / 2
    blotch = fractal_noise(w // 8, h // 8, seed=seed, octaves=4)
    blotch = np.asarray(Image.fromarray((blotch * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=float) / 255
    return np.clip(shade * (1 - strength * 0.8 * (blotch - 0.5)), 0, 2)


def banner(path, w=2200, h=1100):
    """A printed canvas banner, 2.0 by 1.0 m: the Meshtastic mark over the wordmark, in their own
    colors on Meshtastic charcoal, with a stitched hem."""
    image = Image.new("RGBA", (w, h), (*CHARCOAL, 255))
    mark = svg(MARK_SVG, int(w * 0.40))
    wordmark = svg(WORDMARK_SVG, int(w * 0.74))
    gap = int(h * 0.09)
    top = (h - mark.height - gap - wordmark.height) // 2
    image.alpha_composite(mark, ((w - mark.width) // 2, top))
    image.alpha_composite(wordmark, ((w - wordmark.width) // 2, top + mark.height + gap))
    draw = ImageDraw.Draw(image)
    # Hem: the folded edge and a line of stitches inside it.
    hem = int(h * 0.035)
    draw.rectangle([0, 0, w - 1, h - 1], outline=(30, 31, 42), width=hem)
    stitch = (88, 89, 100)
    for x in range(hem + 10, w - hem - 10, 26):
        for y in (hem + 8, h - hem - 10):
            draw.line([(x, y), (x + 14, y)], fill=stitch, width=3)
    for y in range(hem + 10, h - hem - 10, 26):
        for x in (hem + 8, w - hem - 10):
            draw.line([(x, y), (x, y + 14)], fill=stitch, width=3)
    pixels = np.asarray(image.convert("RGB"), dtype=float) * weave((w, h), 21, 0.12)[..., None]
    Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8)).save(path)


def chirpy_poster(path, w=1200, h=1680):
    """Chirpy on white paper, as on the showcase's wall."""
    image = Image.new("RGBA", (w, h), (246, 246, 242, 255))
    margin = int(w * 0.09)
    chirpy = svg(CHIRPY_SVG, w - 2 * margin)
    if chirpy.height > h - 2 * margin:
        chirpy = svg(CHIRPY_SVG, int((w - 2 * margin) * (h - 2 * margin) / chirpy.height))
    image.alpha_composite(chirpy, ((w - chirpy.width) // 2, (h - chirpy.height) // 2))
    image.convert("RGB").save(path)


def solutions_plaque(path, w=2016, h=992):
    """The showcase's plaque, laid out as ShowcaseWallArt.solutionsPlaque() draws it: a small line
    over the Meshtastic Solutions mark and name, in white on charcoal. Drawn for a 1.26 by 0.62 m
    plaque (1600 px a meter), with the small line's capitals about 56 mm tall so it reads from
    the seat."""
    image = Image.new("RGBA", (w, h), (43, 46, 61, 255))
    draw = ImageDraw.Draw(image)
    inset = 36
    draw.rounded_rectangle([inset, inset, w - inset, h - inset], radius=26, outline=(130, 132, 142), width=6)
    small = system_font(128, b"Medium")
    by_line = "Comms equipment provided by"
    left, _, right, _ = draw.textbbox((0, 0), by_line, font=small)
    draw.text(((w - (right - left)) / 2, h * 0.34), by_line, fill=(214, 215, 220), font=small, anchor="ls")
    # The mark tinted white, as the showcase does.
    mark = svg(SOLUTIONS_SVG, 800)
    white = Image.new("RGBA", mark.size, (255, 255, 255, 255))
    white.putalpha(mark.getchannel("A"))
    name = "Meshtastic Solutions"
    gap = 40
    size = 176
    while True:
        large = system_font(size, b"Semibold")
        left, top, right, bottom = draw.textbbox((0, 0), name, font=large)
        mark_height = size * 1.2
        mark_width = mark_height * white.width / white.height
        if mark_width + gap + (right - left) <= w - 200 or size <= 64:
            break
        size -= 4
    start = (w - (mark_width + gap + (right - left))) / 2
    row = h * 0.65
    tinted = white.resize((int(mark_width), int(mark_height)), Image.LANCZOS)
    image.alpha_composite(tinted, (int(start), int(row - mark_height / 2)))
    draw.text((start + mark_width + gap, row), name, fill=(255, 255, 255), font=large, anchor="lm")
    image.convert("RGB").save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    topo_map(os.path.join(OUT, "topo.png"))
    whiteboard(os.path.join(OUT, "whiteboard.png"))
    banner(os.path.join(OUT, "banner.png"))
    chirpy_poster(os.path.join(OUT, "chirpy_poster.png"))
    solutions_plaque(os.path.join(OUT, "solutions_plaque.png"))
    print("textures written to", OUT)


if __name__ == "__main__":
    main()

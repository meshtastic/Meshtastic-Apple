#!/usr/bin/env python3
#
#  make_textures.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/23/26.
#
#  Draws the flat textures the scenes use: a topo map, a blank whiteboard, and the Meshtastic
#  banner, Chirpy poster and Meshtastic Solutions plaque; and for the ham shack, a wall of QSL
#  cards, two clock faces, a radio's display, two meter faces, an FT8 screen, a band plan chart, and its books' spines and covers. All but the branding are
#  generated here.
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

from ham_books import COVERS, SPINES

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


# MARK: - Ham shack

def qsl_wall(path, w=1800, h=1200):
    """A corkboard of QSL cards, 0.9 by 0.6 m (2000 px a meter): postcards hams trade to confirm a
    contact. Drawn without call signs, so none belongs to a real station; each says QSL and 73
    ("best regards") over a simple scene."""
    rng = random.Random(73)
    cork = fractal_noise(w, h, seed=5, octaves=5)
    base = np.stack([150 + 50 * cork, 108 + 38 * cork, 66 + 26 * cork], axis=-1)
    speckle = np.random.default_rng(3).random((h, w)) < 0.06
    base[speckle] *= 0.78
    image = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")
    big = font("Arial Bold.ttf", 64)
    small = font("Arial.ttf", 30)
    palettes = [
        ((30, 70, 140), (240, 200, 60)), ((170, 40, 40), (250, 240, 220)), ((20, 110, 80), (250, 250, 245)),
        ((240, 240, 235), (30, 30, 40)), ((250, 200, 60), (40, 40, 60)), ((60, 40, 110), (250, 170, 60)),
        ((235, 120, 40), (255, 255, 255)), ((40, 140, 200), (255, 255, 255)),
    ]
    card_w, card_h = 280, 180
    for row in range(4):
        for col in range(6):
            if rng.random() < 0.12:
                continue
            ground, ink = rng.choice(palettes)
            card = Image.new("RGBA", (card_w, card_h), (*ground, 255))
            draw = ImageDraw.Draw(card)
            scene = rng.randrange(3)
            if scene == 0:  # mountains
                peaks = [(0, card_h)] + [(x, card_h - rng.randint(40, 110)) for x in range(0, card_w + 40, 40)] + [(card_w, card_h)]
                draw.polygon(peaks, fill=tuple(int(c * 0.7) for c in ground))
            elif scene == 1:  # a tower with waves
                cx = rng.randint(50, card_w - 50)
                draw.line([(cx, card_h - 10), (cx - 18, card_h - 10), (cx, 40), (cx + 18, card_h - 10)], fill=ink, width=4)
                for r in (30, 50, 70):
                    draw.arc([cx - r, 40 - r, cx + r, 40 + r], -60, 60, fill=ink, width=3)
            else:  # a stripe
                draw.rectangle([0, card_h * 0.55, card_w, card_h * 0.75], fill=ink)
            draw.text((16, 12), "QSL", fill=ink, font=big)
            draw.text((card_w - 70, card_h - 44), "73", fill=ink, font=small)
            card = card.rotate(rng.uniform(-6, 6), expand=True, resample=Image.BICUBIC)
            x = 60 + col * 285 + rng.randint(-12, 12)
            y = 60 + row * 270 + rng.randint(-12, 12)
            shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
            shadow.paste((0, 0, 0, 90), mask=card.getchannel("A"))
            image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6)), (x + 6, y + 8))
            image.alpha_composite(card, (x, y))
            pin = ImageDraw.Draw(image)
            px, py = x + card.width // 2, y + 14
            pin.ellipse([px - 9, py - 9, px + 9, py + 9], fill=rng.choice([(200, 30, 30), (30, 90, 200), (240, 200, 30)]))
    image.convert("RGB").save(path)


def clock_face(path, label, w=800):
    """A wall clock's round dial, with `label` under the center. Hams keep one clock on UTC, for the
    log, beside one on local time. The hands are modeled in the scene, not drawn here."""
    image = Image.new("RGB", (w, w), (245, 243, 236))
    draw = ImageDraw.Draw(image)
    c = w / 2
    for tick in range(60):
        angle = math.radians(tick * 6)
        outer, inner = c * 0.92, c * (0.80 if tick % 5 == 0 else 0.87)
        width = 10 if tick % 5 == 0 else 4
        draw.line([(c + outer * math.sin(angle), c - outer * math.cos(angle)), (c + inner * math.sin(angle), c - inner * math.cos(angle))], fill=(25, 25, 30), width=width)
    numerals = font("Arial Bold.ttf", int(w * 0.09))
    for hour in range(1, 13):
        angle = math.radians(hour * 30)
        draw.text((c + c * 0.66 * math.sin(angle), c - c * 0.66 * math.cos(angle)), str(hour), fill=(25, 25, 30), font=numerals, anchor="mm")
    draw.text((c, c * 1.38), label, fill=(170, 30, 30), font=font("Arial Bold.ttf", int(w * 0.07)), anchor="mm")
    image.save(path)


def radio_display(path, frequency, mode, w=900, h=300):
    """A radio's amber display: the frequency, the mode, and an S-meter."""
    image = Image.new("RGB", (w, h), (24, 14, 4))
    draw = ImageDraw.Draw(image)
    amber = (255, 168, 40)
    dim = (90, 55, 12)
    draw.text((w - 40, 185), frequency, fill=amber, font=font("Arial Bold.ttf", 120), anchor="rs")
    small = font("Arial Bold.ttf", 44)
    draw.text((40, 60), mode, fill=amber, font=small, anchor="ls")
    draw.text((160, 60), "VFO-A", fill=dim, font=small, anchor="ls")
    lit = sum(map(ord, frequency)) % 18 + 4
    for i in range(30):
        x = 40 + i * 27
        draw.rectangle([x, 220, x + 18, 262], fill=amber if i < lit else dim)
    draw.text((40, 290), "S 1  3  5  7  9  +20  +40", fill=dim, font=font("Arial.ttf", 26), anchor="ls")
    image.save(path)


def meter_face(path, label, needle, w=600, h=400):
    """An analog panel meter: a cream face with an arc scale, `label` under it, and its needle at
    `needle` (0 to 1 of full scale)."""
    image = Image.new("RGB", (w, h), (238, 230, 205))
    draw = ImageDraw.Draw(image)
    cx, cy, r = w / 2, h * 0.95, h * 0.75
    draw.arc([cx - r, cy - r, cx + r, cy + r], 215, 325, fill=(30, 30, 30), width=5)
    draw.arc([cx - r, cy - r, cx + r, cy + r], 300, 325, fill=(190, 30, 30), width=9)
    for i in range(11):
        angle = math.radians(215 + i * 11)
        inner = r * (0.88 if i % 5 == 0 else 0.93)
        draw.line([(cx + inner * math.cos(angle), cy + inner * math.sin(angle)), (cx + r * math.cos(angle), cy + r * math.sin(angle))], fill=(30, 30, 30), width=4)
    draw.text((cx, h * 0.62), label, fill=(30, 30, 30), font=font("Arial Bold.ttf", 46), anchor="mm")
    angle = math.radians(215 + 110 * needle)
    draw.line([(cx, cy), (cx + r * 1.02 * math.cos(angle), cy + r * 1.02 * math.sin(angle))], fill=(20, 20, 20), width=5)
    image.save(path)


def waterfall(path, w=1600, h=960):
    """A computer screen running an FT8 program: a band of decoded messages over the blue
    waterfall, with the yellow streaks of signals in it. The decodes use no call signs."""
    rng = np.random.default_rng(8)
    image = Image.new("RGB", (w, h), (236, 236, 238))
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, w, 54], fill=(52, 54, 70))
    draw.text((24, 27), "FT8  14.074 MHz  20m", fill=(240, 240, 245), font=font("Arial Bold.ttf", 30), anchor="lm")
    mono = font("Courier New Bold.ttf", 30)
    lines = ["CQ  DX", "73", "RR73", "-12", "R-08", "CQ  POTA", "+03", "73  GL"]
    for i in range(9):
        y = 80 + i * 38
        fill = (255, 250, 200) if i % 3 == 0 else (236, 236, 238)
        draw.rectangle([16, y - 4, w - 16, y + 30], fill=fill)
        text = f"{(i * 15) % 60:02d}{(i * 7) % 60:02d}00  {rng.integers(-20, 10):+3d}  {rng.uniform(-0.5, 0.9):+.1f}  {rng.integers(300, 2800):4d}  ~  {lines[i % len(lines)]}"
        draw.text((28, y), text, fill=(20, 20, 30), font=mono)
    top = 440
    field = rng.random((h - top, w)) * 0.35
    for _ in range(26):
        x = int(rng.integers(40, w - 80))
        y0 = int(rng.integers(0, h - top - 80))
        length = int(rng.integers(60, h - top - y0))
        field[y0:y0 + length, x:x + 22] += rng.uniform(0.6, 1.2)
    field = np.clip(field, 0, 1.4)
    r = np.clip(field * 255 - 140, 0, 255)
    g = np.clip(field * 230 - 40, 0, 255)
    b = np.clip(110 + field * 120, 0, 255)
    fall = Image.fromarray(np.stack([r, g, b], axis=-1).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
    image.paste(fall, (0, top))
    image.save(path)


def band_plan(path, w=1800, h=1200):
    """A wall chart of the amateur bands from 160 meters to 70 centimeters: one bar per band,
    split into CW, data and phone, the way the printed band plans hams pin up are laid out."""
    image = Image.new("RGB", (w, h), (248, 246, 238))
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, w, 130], fill=CHARCOAL)
    draw.text((w / 2, 65), "AMATEUR RADIO BANDS", fill=(255, 255, 255), font=font("Arial Bold.ttf", 72), anchor="mm")
    bands = ["160 m", "80 m", "40 m", "30 m", "20 m", "17 m", "15 m", "12 m", "10 m", "6 m", "2 m", "70 cm"]
    label = font("Arial Bold.ttf", 48)
    legend = font("Arial.ttf", 38)
    rng = random.Random(4)
    row = (h - 260) / len(bands)
    colors = [(70, 110, 190), (240, 170, 50), (200, 70, 60)]
    for i, band in enumerate(bands):
        y = 160 + i * row
        draw.text((40, y + row / 2), band, fill=(30, 30, 40), font=label, anchor="lm")
        x0, x1 = 260, w - 60
        cw, data = rng.uniform(0.15, 0.3), rng.uniform(0.1, 0.2)
        stops = [x0, x0 + (x1 - x0) * cw, x0 + (x1 - x0) * (cw + data), x1]
        for color, a, b in zip(colors, stops, stops[1:]):
            draw.rectangle([a, y + 10, b, y + row - 10], fill=color)
    for j, (color, name) in enumerate(zip(colors, ("CW", "DATA", "PHONE"))):
        x = 260 + j * 420
        draw.rectangle([x, h - 80, x + 50, h - 40], fill=color)
        draw.text((x + 70, h - 60), name, fill=(30, 30, 40), font=legend, anchor="lm")
    image.save(path)


def book_spine(path, title, author, color, thickness, height, scale=3000):
    """A clothbound book's spine at `scale` pixels a meter: gold bands at the head and foot, the
    title running down it and the author across the foot, the way American spines read."""
    w, h = max(int(thickness * scale), 40), int(height * scale)
    image = Image.new("RGB", (w, h), color)
    draw = ImageDraw.Draw(image)
    gold = (226, 190, 110)
    light = sum(color) > 450
    ink = (30, 26, 22) if light else gold
    for y in (int(h * 0.05), int(h * 0.93)):
        draw.rectangle([0, y, w, y + max(4, h // 120)], fill=ink)
    # The title, set along the spine and turned to read top to bottom.
    length = int(h * 0.7)
    size = int(w * 0.62)
    face = font("Georgia Bold.ttf", size)
    while draw.textlength(title, font=face) > length and size > 10:
        size -= 2
        face = font("Georgia Bold.ttf", size)
    strip = Image.new("RGBA", (length, w), (0, 0, 0, 0))
    ImageDraw.Draw(strip).text((length / 2, w / 2), title, fill=ink, font=face, anchor="mm")
    strip = strip.rotate(-90, expand=True)
    image.paste(strip, (0, int(h * 0.1)), strip)
    small = font("Georgia.ttf", max(10, int(w * 0.2)))
    surname = author.split()[-1]
    draw.text((w / 2, h * 0.88), surname, fill=ink, font=small, anchor="mm")
    cloth = np.asarray(image, dtype=float) * weave((w, h), len(title), 0.1)[..., None]
    Image.fromarray(np.clip(cloth, 0, 255).astype(np.uint8)).save(path)


def book_cover(path, title, line, color, ink, w=880, h=1120):
    """A book's front cover, for the books stood face out: a big title over a line of small type."""
    image = Image.new("RGB", (w, h), color)
    draw = ImageDraw.Draw(image)
    draw.rectangle([40, 40, w - 40, h - 40], outline=ink, width=8)
    # As big as fits: the widest line stays clear of the border.
    size = 170
    big = font("Georgia Bold.ttf", size)
    while max(draw.textlength(row, font=big) for row in title.split("\n")) > w - 180 and size > 60:
        size -= 4
        big = font("Georgia Bold.ttf", size)
    draw.multiline_text((w / 2, h * 0.42), title, fill=ink, font=big, anchor="mm", align="center", spacing=10)
    small = font("Georgia Italic.ttf", 44)
    words, rows, row = line.split(), [], ""
    for word in words:
        if draw.textlength(row + " " + word, font=small) > w - 160:
            rows.append(row)
            row = word
        else:
            row = (row + " " + word).strip()
    rows.append(row)
    draw.multiline_text((w / 2, h * 0.84), "\n".join(rows), fill=ink, font=small, anchor="mm", align="center")
    image.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    topo_map(os.path.join(OUT, "topo.png"))
    whiteboard(os.path.join(OUT, "whiteboard.png"))
    banner(os.path.join(OUT, "banner.png"))
    chirpy_poster(os.path.join(OUT, "chirpy_poster.png"))
    solutions_plaque(os.path.join(OUT, "solutions_plaque.png"))
    qsl_wall(os.path.join(OUT, "qsl_wall.png"))
    clock_face(os.path.join(OUT, "clock_utc.png"), "UTC")
    clock_face(os.path.join(OUT, "clock_local.png"), "LOCAL")
    # 20 meter FT8; the 2 meter and 70 centimeter FM calling frequencies; 40 meter CW.
    radio_display(os.path.join(OUT, "radio_display.png"), "14.074.00", "USB")
    radio_display(os.path.join(OUT, "radio_display_2m.png"), "146.520", "FM")
    radio_display(os.path.join(OUT, "radio_display_70cm.png"), "446.000", "FM")
    radio_display(os.path.join(OUT, "radio_display_40m.png"), "7.030.00", "CW")
    meter_face(os.path.join(OUT, "meter_power.png"), "WATTS", 0.4)
    meter_face(os.path.join(OUT, "meter_swr.png"), "SWR", 0.12)
    meter_face(os.path.join(OUT, "meter_volts.png"), "VOLTS", 0.69)
    waterfall(os.path.join(OUT, "waterfall.png"))
    band_plan(os.path.join(OUT, "band_plan.png"))
    for i, (title, author, color, thickness, height) in enumerate(SPINES):
        book_spine(os.path.join(OUT, f"spine_{i:02d}.png"), title, author, color, thickness, height)
    for i, (title, line, color, ink) in enumerate(COVERS):
        book_cover(os.path.join(OUT, f"cover_{i}.png"), title, line, color, ink)
    print("textures written to", OUT)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generates each map's thumbnail into content/maps/<id>/thumbnail.png. Pure stdlib; rerun to tweak.

The rock, floor and glow colours below are the source of truth: content/maps/<id>/map.tres uses the same values for
`rock`, `floor_plain[0]` and `glow_color` (tests/maps/map_themes.gd checks they stay close). Each map also gets a
signature drawn from those colours (moss, crystal, embers, frost, spores, bones, water, steam; spec 0.6 section 10)."""
import os
import random
import struct
import zlib

W, H = 64, 40
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "content", "maps")

# map id, rock colour, floor colour, glow colour (crystals, lava, water ...)
THEMES = [
    ("mossy_hollow", (40, 52, 40), (62, 92, 58), (120, 200, 90)),
    ("crystal_vault", (38, 40, 60), (58, 64, 96), (110, 230, 240)),
    ("ember_depths", (56, 36, 32), (96, 56, 40), (255, 140, 50)),
    ("frostbite_grotto", (46, 58, 72), (110, 130, 150), (200, 235, 255)),
    ("spore_cavern", (52, 38, 62), (84, 60, 96), (210, 120, 240)),
    ("bone_warren", (66, 58, 48), (120, 108, 88), (235, 225, 200)),
    ("flooded_gallery", (34, 44, 58), (40, 72, 110), (90, 160, 255)),
    ("sulfur_pits", (62, 58, 34), (104, 96, 46), (250, 230, 70)),
]


def write_png(path, pixels):
    raw = b"".join(b"\x00" + b"".join(bytes(p) + b"\xff" for p in row) for row in pixels)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def put(px, x, y, c, a=1.0):
    """Blend colour c over the pixel at (x, y) with opacity a; off-image pixels are ignored."""
    if 0 <= x < W and 0 <= y < H:
        px[y][x] = tuple(int(o * (1 - a) + v * a) for o, v in zip(px[y][x], c))


def blob(px, rng, cx, cy, rx, ry, c, a=1.0):
    """A ragged filled ellipse."""
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            d = ((x - cx) / (rx + 0.5)) ** 2 + ((y - cy) / (ry + 0.5)) ** 2
            if d < 0.85 + rng.uniform(-0.2, 0.2):
                put(px, x, y, c, a)


def crystal(px, cx, cy, hgt, c):
    """An upward crystal: a lit right half, a dark left half, a bright tip."""
    for dy in range(hgt):
        half = 2 if dy < hgt - 3 else (1 if dy < hgt - 1 else 0)
        for dx in range(-half, half + 1):
            put(px, cx + dx, cy - dy, shade(c, 0.6) if dx < 0 else (c if dx > 0 else shade(c, 1.25)))
    put(px, cx, cy - hgt, (255, 255, 255), 0.7)


def sig_moss(px, rng, rock, floor, glow, horizon):
    # moss patches on the floor and the ceiling rock, vines hanging from the ceiling
    for _ in range(7):
        blob(px, rng, rng.randint(2, W - 3), rng.randint(horizon + 1, H - 3), rng.randint(3, 6), rng.randint(1, 3), shade(glow, 0.62), 0.85)
    for _ in range(4):
        blob(px, rng, rng.randint(2, W - 3), rng.randint(2, 9), rng.randint(3, 6), rng.randint(1, 3), shade(glow, 0.5), 0.8)
    for _ in range(9):
        x, length = rng.randint(1, W - 2), rng.randint(5, 14)
        for dy in range(length):
            put(px, x + (dy // 4) % 2, 1 + dy, shade(glow, 0.7 + 0.3 * dy / length))
    for _ in range(10):
        put(px, rng.randint(1, W - 2), rng.randint(horizon, H - 2), shade(glow, 1.2))


def sig_crystal(px, rng, rock, floor, glow, horizon):
    # big faceted clusters standing on the floor and a few small ones on the ceiling
    for cx, hgt in ((rng.randint(8, 18), rng.randint(9, 13)), (rng.randint(24, 40), rng.randint(12, 17)), (rng.randint(46, 56), rng.randint(8, 12))):
        base = horizon + rng.randint(3, 7)
        crystal(px, cx, base, hgt, glow)
        crystal(px, cx - 4, base + 1, hgt // 2, shade(glow, 0.85))
        crystal(px, cx + 4, base + 1, hgt // 2 - 1, shade(glow, 0.8))
    for _ in range(5):
        x, hgt = rng.randint(2, W - 3), rng.randint(3, 6)
        for dy in range(hgt):
            put(px, x, 1 + dy, shade(glow, 0.9 - 0.3 * dy / hgt))
            if dy < hgt - 2:
                put(px, x + 1, 1 + dy, shade(glow, 0.5))


def sig_embers(px, rng, rock, floor, glow, horizon):
    # glowing lava cracks across the floor and rock, and drifting embers
    for _ in range(5):
        x, y = rng.randint(2, W - 3), rng.randint(horizon + 1, H - 3)
        for _ in range(rng.randint(8, 16)):
            put(px, x, y, shade(glow, 1.0), 0.95)
            put(px, x, y + 1, glow, 0.25)
            x += rng.choice((-1, 1, 1)) if rng.random() < 0.7 else 0
            y += rng.choice((-1, 0, 1))
    for _ in range(2):
        x, y = rng.randint(4, W - 5), rng.randint(3, horizon - 2)
        for _ in range(rng.randint(5, 10)):
            put(px, x, y, shade(glow, 0.9), 0.9)
            x += rng.choice((-1, 0, 1))
            y += 1
    for _ in range(14):
        put(px, rng.randint(1, W - 2), rng.randint(2, H - 3), (255, 210, 120), rng.uniform(0.5, 1.0))


def sig_frost(px, rng, rock, floor, glow, horizon):
    # long white icicles from the ceiling, a frosted floor with sparkles
    for _ in range(11):
        x0, wid, length = rng.randint(1, W - 2), rng.randint(2, 4), rng.randint(6, 20)
        for dy in range(length):
            half = int(wid / 2 * (1 - dy / length) + 0.5)
            for dx in range(-half, half + 1):
                put(px, x0 + dx, 1 + dy, shade(glow, 1.0 - 0.3 * dy / length) if dx >= 0 else shade(glow, 0.72))
    for y in range(horizon, H):
        for x in range(W):
            if rng.random() < 0.12:
                put(px, x, y, (255, 255, 255), 0.55)
    for _ in range(6):
        x, y = rng.randint(3, W - 4), rng.randint(horizon, H - 3)
        for d in (-1, 0, 1):
            put(px, x + d, y, (255, 255, 255), 0.9)
            put(px, x, y + d, (255, 255, 255), 0.9)


def sig_spores(px, rng, rock, floor, glow, horizon):
    # glowing mushrooms with domed caps and floating spores
    for _ in range(6):
        cx, base = rng.randint(4, W - 5), rng.randint(horizon + 2, H - 4)
        stem, rx = rng.randint(3, 8), rng.randint(3, 6)
        for dy in range(stem):
            put(px, cx, base - dy, shade(glow, 0.45))
        for y in range(-rx // 2 - 1, 1):
            for x in range(-rx, rx + 1):
                if (x / (rx + 0.5)) ** 2 + (y / (rx / 2 + 1.2)) ** 2 <= 1:
                    put(px, cx + x, base - stem + y, glow if y < 0 else shade(glow, 0.65))
        put(px, cx - 1, base - stem - 1, (255, 255, 255), 0.5)
    for _ in range(26):
        put(px, rng.randint(1, W - 2), rng.randint(2, H - 3), shade(glow, 1.15), rng.uniform(0.5, 1.0))


def sig_bones(px, rng, rock, floor, glow, horizon):
    # a ribcage rising from the floor, a skull, and scattered bones
    cx = rng.randint(20, 40)
    for i in range(-3, 4):
        x = cx + i * 3
        top = horizon - 8 + abs(i) * 2
        for y in range(top, horizon + 6):
            put(px, x + (1 if y > horizon else 0), y, shade(glow, 0.95 if y % 2 else 0.8))
    for x in range(cx - 10, cx + 11):
        put(px, x, horizon + 6, shade(glow, 0.7))
    sx, sy = rng.randint(6, 14), H - 8
    blob(px, rng, sx, sy, 4, 3, glow)
    for dx in (-2, 1):
        for dy in (-1, 0):
            put(px, sx + dx, sy + dy, shade(rock, 0.35))
    for dx in (-2, -1, 0, 1):
        put(px, sx + dx, sy + 4, shade(glow, 0.8))
    for _ in range(5):
        x, y, length = rng.randint(30, W - 10), rng.randint(horizon + 3, H - 3), rng.randint(4, 8)
        for d in range(length):
            put(px, x + d, y + (d // 3) % 2, shade(glow, 0.9))
        put(px, x - 1, y - 1, glow), put(px, x - 1, y + 1, glow)
        put(px, x + length, y - 1, glow), put(px, x + length, y + 1, glow)


def sig_water(px, rng, rock, floor, glow, horizon):
    # the floor is a pool: blue water with light ripple lines, drips falling from the ceiling
    top = horizon + 1
    for y in range(top, H - 1):
        for x in range(1, W - 1):
            put(px, x, y, shade(glow, 0.5 + 0.2 * (y - top) / (H - top)), 0.55)
    for _ in range(14):
        x, y, length = rng.randint(2, W - 12), rng.randint(top + 1, H - 3), rng.randint(4, 9)
        for d in range(length):
            put(px, x + d, y, (220, 240, 255), 0.7)
    for _ in range(4):
        x = rng.randint(4, W - 5)
        for y in range(4, horizon - 1):
            if y % 3 != 0:
                put(px, x, y, glow, 0.6)
        for d in (-3, -2, 2, 3):
            put(px, x + d, top + 1, (220, 240, 255), 0.8)


def sig_steam(px, rng, rock, floor, glow, horizon):
    # yellow sulfur crust around vents, pale steam wisps rising and curling
    vents = [rng.randint(6, 20), rng.randint(26, 40), rng.randint(46, 58)]
    for vx in vents:
        vy = rng.randint(horizon + 4, H - 5)
        blob(px, rng, vx, vy, rng.randint(4, 6), 2, shade(glow, 0.85))
        blob(px, rng, vx, vy, 2, 1, shade(rock, 0.3))
        x = vx
        for dy in range(vy - 2, 1, -1):
            drift = int(2 * ((vy - dy) / 6.0) ** 0.5 * (1 if vx % 2 else -1) * (1 if (vy - dy) % 8 < 4 else 0.4))
            for dx in (-1, 0, 1):
                put(px, vx + drift + dx, dy, (235, 235, 225), 0.38 - 0.25 * (vy - dy) / vy * (1 if dx == 0 else 0.6))
    for _ in range(10):
        put(px, rng.randint(1, W - 2), rng.randint(horizon, H - 2), glow, 0.8)


SIGNATURES = {
    "mossy_hollow": sig_moss, "crystal_vault": sig_crystal, "ember_depths": sig_embers,
    "frostbite_grotto": sig_frost, "spore_cavern": sig_spores, "bone_warren": sig_bones,
    "flooded_gallery": sig_water, "sulfur_pits": sig_steam,
}


def draw(index, theme):
    _, rock, floor, glow = theme
    rng = random.Random(100 + index)
    px = [[shade(rock, 0.55 + 0.25 * y / H) for _ in range(W)] for y in range(H)]
    horizon = int(H * 0.68)
    for y in range(horizon, H):
        for x in range(W):
            px[y][x] = shade(floor, 0.8 + 0.3 * (y - horizon) / (H - horizon) + rng.uniform(-0.05, 0.05))
    # stalactites from the ceiling
    for _ in range(rng.randint(5, 8)):
        x0, wid, length = rng.randint(0, W - 1), rng.randint(3, 7), rng.randint(6, 16)
        for dy in range(length):
            half = max(0, int(wid / 2 * (1 - dy / length)))
            for dx in range(-half, half + 1):
                if 0 <= x0 + dx < W:
                    px[dy][x0 + dx] = shade(rock, 0.9 - 0.25 * dy / length)
    # rocks on the floor
    for _ in range(rng.randint(2, 4)):
        x0, wid, hgt = rng.randint(2, W - 8), rng.randint(5, 10), rng.randint(3, 6)
        for dy in range(hgt):
            for dx in range(wid - dy):
                x, y = x0 + dx + dy // 2, horizon + 2 - dy + rng.randint(0, 1)
                if 0 <= x < W and 0 <= y < H:
                    px[y][x] = shade(rock, 1.0 + 0.1 * dy)
    # a glow: a few crystals plus a soft halo
    gx, gy = rng.randint(14, W - 14), rng.randint(horizon - 6, horizon + 4)
    for y in range(H):
        for x in range(W):
            d = ((x - gx) ** 2 + (y - gy) ** 2) ** 0.5
            if d < 16:
                k = (1 - d / 16) * 0.35
                px[y][x] = tuple(int(a * (1 - k) + g * k) for a, g in zip(px[y][x], glow))
    SIGNATURES[theme[0]](px, rng, rock, floor, glow, horizon)
    # one-pixel frame
    for x in range(W):
        px[0][x] = px[H - 1][x] = shade(rock, 0.4)
    for y in range(H):
        px[y][0] = px[y][W - 1] = shade(rock, 0.4)
    return px


for i, theme in enumerate(THEMES):
    folder = os.path.join(OUT, theme[0])
    os.makedirs(folder, exist_ok=True)
    write_png(os.path.join(folder, "thumbnail.png"), draw(i, theme))
# _template is a copy of the first map's look (its map.tres has the same palette), so a new map starts valid.
write_png(os.path.join(OUT, "_template", "thumbnail.png"), draw(0, THEMES[0]))
print("wrote", len(THEMES), "thumbnails under", os.path.abspath(OUT))

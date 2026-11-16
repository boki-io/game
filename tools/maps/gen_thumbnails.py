#!/usr/bin/env python3
"""Generates each map's thumbnail into content/maps/<id>/thumbnail.png. Pure stdlib; rerun to tweak.

The rock, floor and glow colours below are the source of truth: content/maps/<id>/map.tres uses the same values for
`rock`, `floor_plain[0]` and `glow_color` (tests/maps/map_themes.gd checks they stay close)."""
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
    for _ in range(rng.randint(3, 5)):
        cx, cy, hgt = gx + rng.randint(-6, 6), gy + rng.randint(-1, 3), rng.randint(3, 7)
        for dy in range(hgt):
            for dx in range(-1, 2 if dy < hgt - 2 else 1):
                x, y = cx + dx, cy - dy
                if 0 <= x < W and 0 <= y < H:
                    px[y][x] = glow if dx >= 0 else shade(glow, 0.7)
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
print("wrote", len(THEMES), "thumbnails under", os.path.abspath(OUT))

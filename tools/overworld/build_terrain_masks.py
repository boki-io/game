#!/usr/bin/env python3
"""Writes the two terrain masks of the overworld (spec 1.6 section 4) from the guide's layers, as 8-bit grey 2000 x 2000 PNGs:
  content/overworld/data/path_mask.png        255 where the guide's paths layer (04_paths.png) marks a dirt path, on walkable
                                              tiles of collision.png only; 0 elsewhere.
  content/overworld/data/blocker_material.png on blocked tiles, 1 forest and 2 rock, decided from the colour of the guide's
                                              blockers layer (02_blockers.png): green-dominant is forest (the map's dark
                                              canopy), low-chroma grey is rock; 0 on walkable tiles and for other hues
                                              (lava, ice, bone ... the other zones, which draw no rock tiles).
Pure Python (stdlib only). The layers live outside the repo: pass their folder as the first argument, or set LAYERS_DIR.
usage: python3 tools/overworld/build_terrain_masks.py [layers_dir] [--check]
"""
import os
import struct
import sys
import zlib

COLLISION = "content/overworld/data/collision.png"
OUT_PATH = "content/overworld/data/path_mask.png"
OUT_MATERIAL = "content/overworld/data/blocker_material.png"
DEFAULT_LAYERS = "/Users/bok/Documents/game-characters/map/layers_v3"
FOREST, ROCK = 1, 2


def read_png(path):
    """(w, h, channels, rows) of an 8-bit PNG (grey, RGB or RGBA); rows are bytearrays of w * channels."""
    d = open(path, "rb").read()
    p, idat = 8, b""
    while p < len(d):
        n, = struct.unpack(">I", d[p:p + 4])
        t = d[p + 4:p + 8]
        if t == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", d[p + 8:p + 18])
        if t == b"IDAT":
            idat += d[p + 8:p + 8 + n]
        p += 12 + n
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    assert depth == 8, "needs an 8-bit PNG"
    raw = zlib.decompress(idat)
    stride = w * ch
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, ch, rows


def write_png_gray(w, h, rows):
    def chunk(t, b):
        c = struct.pack(">I", len(b)) + t + b
        return c + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
    body = b"".join(b"\x00" + bytes(r) for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(body, 9)) + chunk(b"IEND", b""))


def material(r, g, b):
    """1 forest, 2 rock, 0 other hue, from the colour of a blockers-layer pixel."""
    if g - r >= 8 and g >= b:
        return FOREST
    if max(r, g, b) - min(r, g, b) <= 12:
        return ROCK
    return 0


def build(layers):
    w, h, _, coll = read_png(COLLISION)
    _, _, pch, paths = read_png(os.path.join(layers, "04_paths.png"))
    _, _, bch, blockers = read_png(os.path.join(layers, "02_blockers.png"))
    assert pch == 4 and bch == 4, "the paths and blockers layers need an alpha channel"
    path_rows, mat_rows = [], []
    for y in range(h):
        c, p, b = coll[y], paths[y], blockers[y]
        pr, mr = bytearray(w), bytearray(w)
        for x in range(w):
            if c[x] > 127:
                if p[x * 4 + 3] > 0:
                    pr[x] = 255
            elif b[x * 4 + 3] > 0:
                mr[x] = material(b[x * 4], b[x * 4 + 1], b[x * 4 + 2])
        path_rows.append(pr)
        mat_rows.append(mr)
    return {OUT_PATH: write_png_gray(w, h, path_rows), OUT_MATERIAL: write_png_gray(w, h, mat_rows)}


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    layers = args[0] if args else os.environ.get("LAYERS_DIR", DEFAULT_LAYERS)
    out = build(layers)
    if "--check" in sys.argv:
        same = True
        for path, data in out.items():
            try:
                ok = open(path, "rb").read() == data
            except FileNotFoundError:
                ok = False
            print(path, "same" if ok else "DIFFERENT")
            same = same and ok
        sys.exit(0 if same else 1)
    for path, data in out.items():
        open(path, "wb").write(data)
        print(f"wrote {path}")


main()

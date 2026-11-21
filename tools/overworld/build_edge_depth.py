#!/usr/bin/env python3
"""Writes content/overworld/data/edge_depth.png from collision.png: for every blocked tile the distance in tiles (Chebyshev,
8-neighbour steps) to the nearest walkable tile, capped at CAP; 0 for walkable tiles and for blocked tiles farther than CAP
(they are never drawn or given colliders). Pure Python, no Pillow: each row is a big integer bitmask and the dilation is
shifts and ORs, so the whole 2000 x 2000 map takes a few seconds. `--check` compares with the committed file.
usage: python3 tools/overworld/build_edge_depth.py [--check]
"""
import struct
import sys
import zlib

SRC = "content/overworld/data/collision.png"
OUT = "content/overworld/data/edge_depth.png"
CAP = 15


def read_png_gray(path):
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
    assert depth == 8 and ctype == 0, "needs an 8-bit grey PNG"
    raw = zlib.decompress(idat)
    rows, prev = [], bytearray(w)
    for y in range(h):
        f = raw[y * (w + 1)]
        line = bytearray(raw[y * (w + 1) + 1:(y + 1) * (w + 1)])
        for i in range(w):
            a = line[i - 1] if i >= 1 else 0
            b = prev[i]
            c = prev[i - 1] if i >= 1 else 0
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
    return w, h, rows


def write_png_gray(path, w, h, rows):
    def chunk(t, b):
        c = struct.pack(">I", len(b)) + t + b
        return c + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
    body = b"".join(b"\x00" + bytes(r) for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(body, 9)) + chunk(b"IEND", b""))


def build() -> bytes:
    w, h, rows = read_png_gray(SRC)
    mask = (1 << w) - 1
    # bit x of row y is set when tile (x, y) is walkable (white)
    cur = []
    for y in range(h):
        v = 0
        for x, px in enumerate(rows[y]):
            if px > 127:
                v |= 1 << x
        cur.append(v)
    depth = [bytearray(w) for _ in range(h)]
    covered = list(cur)
    for step in range(1, CAP + 1):
        # 3 x 3 dilation: horizontal spread of every row, then OR of the three rows around it
        spread = [(r | (r << 1) | (r >> 1)) & mask for r in covered]
        nxt = []
        for y in range(h):
            v = spread[y]
            if y > 0:
                v |= spread[y - 1]
            if y < h - 1:
                v |= spread[y + 1]
            nxt.append(v)
        for y in range(h):
            new = nxt[y] & ~covered[y]
            while new:
                low = new & -new
                depth[y][low.bit_length() - 1] = step
                new ^= low
        covered = nxt
    return write_png_gray(OUT, w, h, depth)


def main() -> None:
    data = build()
    if "--check" in sys.argv:
        try:
            same = open(OUT, "rb").read() == data
        except FileNotFoundError:
            same = False
        print("same" if same else "DIFFERENT")
        sys.exit(0 if same else 1)
    open(OUT, "wb").write(data)
    print(f"wrote {OUT}")


main()

#!/usr/bin/env python3
"""Slices the Nature pack into three atlases and a manifest (spec 1.7 section 2):
  assets/nature/trees.png, rocks.png, shrubs.png   each sprite trimmed to its opaque bounds, pre-scaled with a box filter
                                                    (scales in the manifest), packed with 1 px transparent padding.
  content/overworld/nature/sprites.json            {"scales": {...}, "trees": [...], "rocks": [...], "shrubs": [...]}; each
                                                    entry {id, region [x, y, w, h], anchor [x, y], tags}. Regions and anchors are
                                                    in the pre-scaled atlas pixels.
It also writes a contact sheet (every sprite, anchor marked) to --contact (default: nature_contact.png in the current folder);
its path is printed. Look at it after changing the tables below.
Python 3 with numpy only; Pillow is not installed here, so there is a small PNG reader and writer. Deterministic output.
usage: python3 tools/overworld/build_nature_atlas.py [source_dir] [--check] [--contact path]
  --check  rebuilds in memory and exits 1 if the decoded pixels of the committed atlases or the manifest JSON differ.
"""
import json
import os
import struct
import sys
import zlib

import numpy as np

DEFAULT_SOURCE = "/Users/bok/Documents/game-characters/Nature"
OUT_DIR = "assets/nature"
MANIFEST = "content/overworld/nature/sprites.json"
SCALES = {"trees": 0.4, "rocks": 0.7, "shrubs": 0.7}

TREE_SHEET = "treeeeeee.png"
ROCK_SHEET = "Rock Pile - Spritesheet.png"
ROCK_CELL = 85
# 1-based columns of the rock sheet: grey, warm grey, olive (blue grey, dark blue and brown belong to later zones).
ROCK_COLUMNS = (1, 4, 6)
ROCK_COLUMN_NAMES = {1: "grey", 4: "warm", 6: "olive"}
# 1-based rows of the rock sheet whose shape is a flat scatter of pebbles (tag pile_pebbles); the same in every column.
PILE_PEBBLE_ROWS = [3, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 30]
BUSH_COUNT = 15
BUSH_COLOURS = ("GREEN", "YELLOWISH GREEN", "YELLOW")
BUSH_COLOUR_TAG = {"GREEN": "green", "YELLOWISH GREEN": "yellowish", "YELLOW": "yellow"}

PEBBLE_W, BIG_W = 40, 55  # trimmed source widths: pebbles under 40, small under 55, big from 55
TREE_GROW = 4
# Source rects (x, y, w, h) that replace the detected component containing their centre (overlapping pairs).
TREE_SPLITS: list = [
    (622, 1, 181, 220), (803, 1, 166, 220),        # two greens joined at the top row
    (0, 231, 167, 215), (0, 446, 142, 160),      # yellow aspen above a small green tree
    (391, 238, 140, 176), (391, 414, 140, 176),  # yellow above orange
    (531, 436, 138, 155), (670, 440, 105, 150), (718, 595, 88, 170),  # small green, yellow, thin red
]
# Tree index (sorted order, after splits and exclusions) -> (x, y) trunk foot in source sheet pixels.
TREE_ANCHOR_FIX: dict = {12: (1021, 362), 23: (381, 730), 25: (990, 715), 26: (1149, 714), 28: (205, 763)}  # the firs: drooping needles hang below the trunk
# Tree indices (sorted order after splits) left out of the atlas.
EXCLUDE: list = []
TALL_PX = 160  # source height


# ---------------------------------------------------------------- PNG

def read_png(path):
    """RGBA uint8 array (h, w, 4) of an 8-bit RGB or RGBA PNG."""
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
    assert depth == 8 and ctype in (2, 6), "needs an 8-bit RGB or RGBA PNG: " + path
    ch = 3 if ctype == 2 else 4
    raw = np.frombuffer(zlib.decompress(idat), dtype=np.uint8)
    stride = w * ch
    raw = raw.reshape(h, stride + 1)
    out = np.zeros((h, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.int32)
    for y in range(h):
        f = raw[y, 0]
        line = raw[y, 1:].astype(np.int32)
        if f == 0:
            cur = line
        elif f == 2:
            cur = (line + prev) & 255
        elif f == 1:
            cur = line.copy()
            for i in range(ch, stride):
                cur[i] = (cur[i] + cur[i - ch]) & 255
        elif f == 3:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - ch] if i >= ch else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        else:
            raise ValueError("bad filter")
        out[y] = cur
        prev = cur
    img = out.reshape(h, w, ch)
    if ch == 3:
        img = np.concatenate([img, np.full((h, w, 1), 255, np.uint8)], axis=2)
    return img


def png_bytes(img):
    """RGBA PNG bytes, filter 0 on every row (deterministic)."""
    h, w, _ = img.shape
    raw = np.concatenate([np.zeros((h, 1), np.uint8), img.reshape(h, w * 4)], axis=1).tobytes()

    def chunk(t, data):
        c = struct.pack(">I", len(data)) + t + data
        return c + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# ---------------------------------------------------------------- image helpers

def trim(img):
    """(cropped image, x, y of the crop in img), or None when fully transparent."""
    a = img[:, :, 3] > 0
    ys, xs = np.nonzero(a)
    if len(ys) == 0:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    return img[y0:y1, x0:x1], int(x0), int(y0)


def scale_box(img, scale):
    """Box-filter downscale of an RGBA image to round(size * scale) (alpha-weighted colour, so edges do not darken)."""
    h, w, _ = img.shape
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    f = img.astype(np.float64)
    a = f[:, :, 3:4] / 255.0
    pm = np.concatenate([f[:, :, :3] * a, f[:, :, 3:4]], axis=2)
    xe = np.linspace(0, w, nw + 1)
    ye = np.linspace(0, h, nh + 1)

    def axis_weights(edges, n):
        m = np.zeros((len(edges) - 1, n))
        for i in range(len(edges) - 1):
            lo, hi = edges[i], edges[i + 1]
            for j in range(int(np.floor(lo)), min(n, int(np.ceil(hi)))):
                m[i, j] = min(hi, j + 1) - max(lo, j)
            m[i] /= hi - lo
        return m
    wy, wx = axis_weights(ye, h), axis_weights(xe, w)
    out = np.einsum("ij,jkc->ikc", wy, pm)
    out = np.einsum("kl,ilc->ikc", wx, out)
    al = out[:, :, 3:4]
    col = np.where(al > 1e-6, out[:, :, :3] / np.maximum(al / 255.0, 1e-6) / 1.0, 0)
    col = np.where(al > 1e-6, out[:, :, :3] * 255.0 / np.maximum(al, 1e-6), 0)
    res = np.concatenate([col, al], axis=2)
    return np.clip(np.rint(res), 0, 255).astype(np.uint8)


def label_components(mask):
    """Connected components (8-neighbour) of a bool mask: (labels int32 array, count). Pure numpy union-find free flood."""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    flat = mask.ravel()
    lab = labels.ravel()
    n = 0
    idx = np.flatnonzero(flat)
    for s in idx:
        if lab[s]:
            continue
        n += 1
        lab[s] = n
        stack = [s]
        while stack:
            p = stack.pop()
            y, x = divmod(p, w)
            for dy in (-1, 0, 1):
                yy = y + dy
                if yy < 0 or yy >= h:
                    continue
                for dx in (-1, 0, 1):
                    xx = x + dx
                    if 0 <= xx < w:
                        q = yy * w + xx
                        if flat[q] and not lab[q]:
                            lab[q] = n
                            stack.append(q)
    return labels, n


def grow(mask, r):
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            sh = np.zeros_like(mask)
            ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
            xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
            sh[yd, xd] = mask[ys, xs]
            out |= sh
    return out


# ---------------------------------------------------------------- sprite lists
# A sprite is a dict: id, img (RGBA, source size, trimmed), anchor (x, y in the trimmed source image), tags.

def foot_of(img):
    """Trunk foot: mean x of the opaque pixels in the lowest 6 rows, the lowest opaque row."""
    h, w, _ = img.shape
    a = img[:, :, 3] > 0
    ys, xs = np.nonzero(a[max(0, h - 6):, :])
    return int(round(float(xs.mean()))), h - 1


def tree_tags(img):
    """green / fir / autumn (and red, so a zone can leave the reds out) from the mean colour, tall / short from the height."""
    h, w, _ = img.shape
    m = img[:, :, 3] > 0
    r, g, b = (float(img[:, :, c][m].mean()) for c in range(3))
    tags = []
    if g > r * 1.08 and g > b:
        tags.append("fir" if (w > h or g < 110) else "green")
    else:
        tags.append("autumn")
        tags.append("red" if r > g * 1.8 else ("orange" if r > g * 1.2 else "yellow"))
    tags.append("tall" if h > TALL_PX else "short")
    return tags


def tree_sprites(src):
    sheet = read_png(os.path.join(src, TREE_SHEET))
    alpha = sheet[:, :, 3] > 0
    labels, n = label_components(grow(alpha, TREE_GROW))
    rects = []
    for k in range(1, n + 1):
        ys, xs = np.nonzero((labels == k) & alpha)
        if len(ys) < 50:
            continue
        rects.append([int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)])
    # a split rect replaces the components whose bounds hold its centre
    parents = set()
    for (sx, sy, sw, sh) in TREE_SPLITS:
        cx, cy = sx + sw // 2, sy + sh // 2
        for r in rects:
            if r[0] <= cx < r[2] and r[1] <= cy < r[3]:
                parents.add(tuple(r))
    out = [r for r in rects if tuple(r) not in parents]
    for (sx, sy, sw, sh) in TREE_SPLITS:
        out.append([sx, sy, sx + sw, sy + sh])
    res = []
    for x0, y0, x1, y1 in out:
        t = trim(sheet[y0:y1, x0:x1])
        if t:
            res.append((x0 + t[1], y0 + t[2], t[0]))
    res.sort(key=lambda r: (r[1] + r[2].shape[0]) // 150 * 10000 + r[0])
    sprites = []
    for i, (x, y, img) in enumerate(res):
        if i in EXCLUDE:
            continue
        ax, ay = foot_of(img)
        if i in TREE_ANCHOR_FIX:
            ax, ay = TREE_ANCHOR_FIX[i][0] - x, TREE_ANCHOR_FIX[i][1] - y
        sprites.append({"id": "tree_%02d" % i, "img": img, "anchor": (ax, ay), "tags": tree_tags(img), "src": (x, y)})
    return sprites


def rock_sprites(src):
    sheet = read_png(os.path.join(src, ROCK_SHEET))
    rows = sheet.shape[0] // ROCK_CELL
    sprites = []
    for col in ROCK_COLUMNS:
        for row in range(1, rows + 1):
            cell = sheet[(row - 1) * ROCK_CELL:row * ROCK_CELL, (col - 1) * ROCK_CELL:col * ROCK_CELL]
            t = trim(cell)
            if not t:
                continue
            img = t[0]
            w = img.shape[1]
            tags = ["pebbles" if w < PEBBLE_W else ("small" if w < BIG_W else "big")]
            if row in PILE_PEBBLE_ROWS:
                tags.append("pile_pebbles")
            sprites.append({"id": "rock_%s_r%02d" % (ROCK_COLUMN_NAMES[col], row), "img": img,
                            "anchor": (w // 2, img.shape[0] - 1), "tags": tags})
    return sprites


def shrub_sprites(src):
    sprites = []
    for colour in BUSH_COLOURS:
        for n in range(1, BUSH_COUNT + 1):
            img = read_png(os.path.join(src, "Bush %d" % n, "Bush %d_%s.png" % (n, colour)))
            t = trim(img)
            img = t[0]
            w = img.shape[1]
            sprites.append({"id": "shrub_%s_%02d" % (BUSH_COLOUR_TAG[colour], n), "img": img,
                            "anchor": (w // 2, img.shape[0] - 1),
                            "tags": ["small" if w < 30 else "wide", BUSH_COLOUR_TAG[colour]]})
    return sprites


# ---------------------------------------------------------------- packing

def scaled(sprite, scale):
    img = scale_box(sprite["img"], scale) if scale != 1.0 else sprite["img"]
    h, w, _ = img.shape
    ax = min(w - 1, max(0, int(round(sprite["anchor"][0] * scale))))
    ay = min(h - 1, max(0, int(round(sprite["anchor"][1] * scale))))
    return img, (ax, ay)


def pack(sprites, scale, max_w=512):
    """Shelf-packs the pre-scaled sprites in list order with 1 px padding: (atlas image, manifest entries)."""
    items = [(s,) + scaled(s, scale) for s in sprites]
    x, y, row_h, placed = 1, 1, 0, []
    for s, img, anchor in items:
        h, w, _ = img.shape
        if x + w + 1 > max_w:
            x, y, row_h = 1, y + row_h + 1, 0
        placed.append((x, y))
        x += w + 1
        row_h = max(row_h, h)
    atlas = np.zeros((y + row_h + 1, max_w, 4), np.uint8)
    entries = []
    for (s, img, anchor), (px, py) in zip(items, placed):
        h, w, _ = img.shape
        atlas[py:py + h, px:px + w] = img
        entries.append({"id": s["id"], "region": [px, py, w, h], "anchor": list(anchor), "tags": s["tags"]})
    return atlas, entries


# ---------------------------------------------------------------- contact sheet

FONT = {"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
        "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
        "8": "111101111101111", "9": "111101111001111"}


def draw_text(img, x, y, text, colour=(255, 255, 255, 255)):
    for ch in text:
        g = FONT.get(ch)
        if g:
            for i, c in enumerate(g):
                if c == "1" and 0 <= y + i // 3 < img.shape[0] and 0 <= x + i % 3 < img.shape[1]:
                    img[y + i // 3, x + i % 3] = colour
        x += 4


def contact_sheet(atlases, width=1500, zoom=(("trees", 3), ("rocks", 3), ("shrubs", 4))):
    """Every sprite on a green ground, enlarged with nearest sampling, its anchor a red cross and its index below."""
    tiles = []
    for kind, z in zoom:
        atlas, entries = atlases[kind]
        for i, e in enumerate(entries):
            x, y, w, h = e["region"]
            tiles.append((kind, i, atlas[y:y + h, x:x + w].repeat(z, 0).repeat(z, 1), [c * z + z // 2 for c in e["anchor"]]))
    x, y, row_h, pos = 4, 4, 0, []
    for kind, i, img, a in tiles:
        h, w, _ = img.shape
        w = max(w, 14)
        if x + w + 4 > width:
            x, y, row_h = 4, y + row_h + 4, 0
        pos.append((x, y))
        x += w + 4
        row_h = max(row_h, h + 8)
    sheet = np.zeros((y + row_h + 4, width, 4), np.uint8)
    sheet[:, :] = (96, 140, 84, 255)
    for (kind, i, img, a), (px, py) in zip(tiles, pos):
        h, w, _ = img.shape
        al = img[:, :, 3:4] / 255.0
        dst = sheet[py:py + h, px:px + w]
        dst[:, :, :3] = (img[:, :, :3] * al + dst[:, :, :3] * (1 - al)).astype(np.uint8)
        ax, ay = px + a[0], py + a[1]
        for d in range(-3, 4):
            for (yy, xx) in ((ay + d, ax), (ay, ax + d)):
                if 0 <= yy < sheet.shape[0] and 0 <= xx < sheet.shape[1]:
                    sheet[yy, xx] = (255, 0, 0, 255)
        draw_text(sheet, px, py + h + 1, str(i), (255, 255, 255, 255) if kind != "shrubs" else (255, 255, 0, 255))
    return sheet


# ---------------------------------------------------------------- build

def build(src):
    kinds = {"trees": tree_sprites(src), "rocks": rock_sprites(src), "shrubs": shrub_sprites(src)}
    atlases = {k: pack(v, SCALES[k]) for k, v in kinds.items()}
    manifest = {"scales": SCALES}
    for k in kinds:
        manifest[k] = atlases[k][1]
    return atlases, manifest


def manifest_text(manifest):
    lines = ["{", '"scales": ' + json.dumps(manifest["scales"]) + ","]
    for k in ("trees", "rocks", "shrubs"):
        lines.append('"%s": [' % k)
        lines.append(",\n".join(json.dumps(e) for e in manifest[k]))
        lines.append("]" + ("," if k != "shrubs" else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    contact = "nature_contact.png"
    if "--contact" in sys.argv:
        contact = sys.argv[sys.argv.index("--contact") + 1]
        args = [a for a in args if a != contact]
    src = args[0] if args else DEFAULT_SOURCE
    atlases, manifest = build(src)
    if "--check" in sys.argv:
        bad = []
        for k in atlases:
            path = os.path.join(OUT_DIR, k + ".png")
            if not os.path.exists(path) or not np.array_equal(read_png(path), atlases[k][0]):
                bad.append(path)
        if not os.path.exists(MANIFEST) or json.load(open(MANIFEST)) != json.loads(manifest_text(manifest)):
            bad.append(MANIFEST)
        if bad:
            print("DIFFERS:", ", ".join(bad))
            sys.exit(1)
        print("OK")
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    for k in atlases:
        open(os.path.join(OUT_DIR, k + ".png"), "wb").write(png_bytes(atlases[k][0]))
    open(MANIFEST, "w").write(manifest_text(manifest))
    open(contact, "wb").write(png_bytes(contact_sheet(atlases)))
    for k in atlases:
        print(k, len(atlases[k][1]), "sprites, atlas", atlases[k][0].shape[1], "x", atlases[k][0].shape[0])
    print("contact sheet:", os.path.abspath(contact))


if __name__ == "__main__":
    main()

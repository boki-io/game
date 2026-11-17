#!/usr/bin/env python3
"""Writes content/props/catalog.tres from assets/tilesets/props.png (no Pillow needed).

The sheet is cut by connected pixels: cyan annotation pixels and stray 1 px specks are ignored. Each prop's base point
(its anchor) is the bottom centre of its fully opaque body, so the baked shadow hangs below and right of the origin.
NAMES maps a prop's top-left corner on the sheet to (id, group, blocks): blocks is the footprint width and depth in px
(0 = walk-through). Run from the repo root: python3 tools/props/build_catalog.py
"""
import struct
import zlib

SHEET = "assets/tilesets/props.png"
OUT = "content/props/catalog.tres"
GAP = 3  # pixels apart that still count as one prop

# (x, y) of the top-left of the prop's bounding box -> (id, group, block width, block depth)
NAMES = {
    (160, 18): ("crate_large", "storage", 30, 12),
    (163, 86): ("crate_small", "storage", 24, 10),
    (162, 153): ("barrel", "storage", 22, 10),
    (165, 217): ("vase_tall", "storage", 0, 0),
    (164, 288): ("pot_wide", "storage", 0, 0),
    (165, 348): ("vase_round", "storage", 0, 0),
    (227, 9): ("slab_tall", "grave", 22, 10),
    (227, 91): ("slab_huge", "grave", 24, 10),
    (227, 183): ("grave_round", "grave", 22, 10),
    (225, 239): ("grave_carved", "grave", 24, 10),
    (227, 303): ("grave_cross", "grave", 22, 10),
    (289, 251): ("grave_small", "grave", 22, 8),
    (288, 87): ("sarcophagus", "grave", 48, 14),
    (288, 158): ("coffin_upright", "grave", 24, 10),
    (292, 19): ("bench_front", "furniture", 44, 10),
    (387, 2): ("bench_side_left", "furniture", 22, 30),
    (387, 98): ("bench_side_right", "furniture", 22, 30),
    (288, 306): ("stone_block", "monument", 30, 12),
    (352, 174): ("pillar_stack", "monument", 26, 12),
    (416, 194): ("pillar_broken", "monument", 22, 10),
    (445, 20): ("statue", "monument", 28, 12),
    (453, 118): ("plinth_small", "monument", 18, 8),
    (353, 269): ("fountain", "monument", 80, 22),
    (420, 359): ("ring_ruin", "monument", 0, 0),
    (3, 430): ("rock_big", "rock", 40, 16),
    (10, 492): ("pebble_1", "rock", 0, 0),
    (40, 490): ("pebble_2", "rock", 0, 0),
    (68, 487): ("pebble_3", "rock", 0, 0),
    (100, 487): ("pebble_4", "rock", 0, 0),
    (130, 484): ("rock_small", "rock", 0, 0),
    (162, 482): ("rock_medium", "rock", 0, 0),
    (231, 489): ("shard_1", "rock", 0, 0),
    (263, 488): ("shard_2", "rock", 0, 0),
    (289, 486): ("rubble", "rock", 0, 0),
}


SETS_DIR = "content/props/sets"
GRAVES = ["grave_round", "grave_carved", "grave_small", "grave_cross"]
POTS = ["vase_tall", "pot_wide", "vase_round"]
CRATES = ["crate_large", "crate_small"]
ROCKS = ["pebble_1", "pebble_2", "pebble_3", "pebble_4", "rock_small", "rock_medium", "shard_1", "shard_2", "rubble"]


def M(props=None, group="", off=(0, 0), step=(0, 0), n=(1, 1), spread=0.0, chance=1.0):
    """One PropSetMember: `props` is a list of prop ids to pick from (or `group`), `n` the (min, max) copies."""
    return dict(props=props or [], group=group, off=off, step=step, n=n, spread=spread, chance=chance)


# id -> (display name, place, mirror, members). place: OPEN, BAND or WALL (a wall nook: x runs along the wall, y away from it).
SETS = {
    "graveyard_small": ("Small graveyard", "OPEN", True, [
        M(GRAVES, off=(-40, 0), step=(40, 0), n=(3, 3)),
        M(["grave_cross"], off=(0, -38)),
        M(ROCKS, off=(0, 6), n=(1, 2), spread=60, chance=0.8),
    ]),
    "graveyard_medium": ("Medium graveyard", "OPEN", True, [
        M(GRAVES, off=(-66, -44), step=(44, 0), n=(4, 4)),
        M(GRAVES, off=(-66, 4), step=(44, 0), n=(3, 4)),
        M(["sarcophagus"], off=(118, -20)),
        M(["coffin_upright"], off=(-118, -18), chance=0.8),
        M(ROCKS, off=(0, 0), n=(2, 4), spread=95),
    ]),
    "graveyard_large": ("Large graveyard", "OPEN", True, [
        M(GRAVES, off=(-92, -84), step=(46, 0), n=(5, 5)),
        M(GRAVES, off=(-92, -40), step=(46, 0), n=(4, 5)),
        M(GRAVES, off=(-92, 4), step=(46, 0), n=(4, 5)),
        M(["slab_huge"], off=(-64, -128)),
        M(["slab_tall"], off=(64, -128)),
        M(["statue"], off=(0, -146), chance=0.6),
        M(["sarcophagus"], off=(150, -40)),
        M(["sarcophagus"], off=(-150, -40), chance=0.7),
        M(["coffin_upright"], off=(150, 24), chance=0.8),
        M(["coffin_upright"], off=(-150, 24), chance=0.8),
        M(ROCKS, off=(0, -30), n=(3, 6), spread=140),
    ]),
    "camp_small": ("Small camp", "OPEN", True, [
        M(["crate_large"], off=(0, 0)),
        M(["crate_small"], off=(34, 8)),
        M(["barrel"], off=(-32, 6)),
        M(POTS, off=(12, 30), chance=0.8),
        M(ROCKS, n=(0, 2), spread=55, chance=0.6),
    ]),
    "camp_supply": ("Supply camp", "OPEN", True, [
        M(CRATES, off=(-50, 0), step=(36, 2), n=(3, 3)),
        M(["barrel"], off=(-42, 36), step=(30, 0), n=(1, 3)),
        M(POTS, off=(0, 64), n=(1, 3), spread=45),
        M(ROCKS, n=(1, 2), spread=80, chance=0.7),
    ]),
    "camp_cache": ("Barrel cache", "OPEN", True, [
        M(["vase_tall"], off=(0, 0)),
        M(["barrel"], off=(-30, 8)),
        M(["barrel"], off=(30, 8), chance=0.85),
        M(["barrel"], off=(0, -24), chance=0.85),
        M(["crate_small"], off=(2, 38), chance=0.6),
        M(ROCKS, n=(1, 2), spread=60, chance=0.6),
    ]),
    "nook_crates": ("Crates along a wall", "WALL", False, [
        M(CRATES, off=(10, 0), step=(38, 0), n=(3, 4)),
        M(["crate_small"], off=(30, 24), chance=0.6),
        M(POTS, off=(0, 10), n=(0, 1), spread=0, chance=0.4),
    ]),
    "nook_barrels": ("Barrels along a wall", "WALL", False, [
        M(["barrel"], off=(10, 0), step=(30, 0), n=(2, 3)),
        M(["crate_large"], off=(100, 0), chance=0.7),
        M(POTS, off=(40, 26), chance=0.6),
    ]),
    "nook_pots": ("Pots along a wall", "WALL", False, [
        M(POTS, off=(8, 0), step=(26, 0), n=(3, 5)),
        M(["crate_small"], off=(150, 0), chance=0.5),
        M(ROCKS, off=(60, 30), n=(0, 2), spread=40, chance=0.7),
    ]),
}


def load(path):
    d = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        c = d[pos + 8:pos + 8 + n]
        pos += 12 + n
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", c[:10])
        if t == b"IDAT":
            idat += c
    assert bd == 8 and ct == 6, "expects an 8-bit RGBA PNG"
    raw, stride, rows, prev, p = zlib.decompress(idat), w * 4, [], bytearray(w * 4), 0
    for _ in range(h):
        f, line, p = raw[p], bytearray(raw[p + 1:p + 1 + stride]), p + 1 + stride
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(line)
        prev = line
    return w, h, rows


def main():
    w, h, rows = load(SHEET)
    solid = set()
    for y in range(h):
        for x in range(w):
            r, g, b, a = rows[y][x * 4:x * 4 + 4]
            if a > 0 and not (b > 180 and g > 150 and r < 120):
                solid.add((x, y))
    seen, comps = set(), {}
    for s in sorted(solid):
        if s in seen:
            continue
        stack, pts = [s], []
        seen.add(s)
        while stack:
            x, y = stack.pop()
            pts.append((x, y))
            for dy in range(-GAP, GAP + 1):
                for dx in range(-GAP, GAP + 1):
                    q = (x + dx, y + dy)
                    if q in solid and q not in seen:
                        seen.add(q)
                        stack.append(q)
        x0, y0 = min(p[0] for p in pts), min(p[1] for p in pts)
        x1, y1 = max(p[0] for p in pts) + 1, max(p[1] for p in pts) + 1
        if x1 - x0 < 4 or y1 - y0 < 4:
            continue  # a stray speck or hairline
        body = [p for p in pts if rows[p[1]][p[0] * 4 + 3] >= 240]
        bx0, bx1 = min(p[0] for p in body), max(p[0] for p in body) + 1
        by1 = max(p[1] for p in body) + 1
        comps[(x0, y0)] = (x0, y0, x1 - x0, y1 - y0, (bx0 + bx1) // 2 - x0, by1 - y0)
    missing = [k for k in NAMES if k not in comps]
    extra = [k for k in comps if k not in NAMES]
    assert not missing and not extra, f"sheet changed: missing {missing}, unnamed {extra}"
    lines = ['[gd_resource type="Resource" script_class="PropCatalog" format=3]', "",
             '[ext_resource type="Script" path="res://scripts/maps/prop_catalog.gd" id="1"]',
             '[ext_resource type="Script" path="res://scripts/maps/prop_data.gd" id="2"]',
             '[ext_resource type="Texture2D" path="res://assets/tilesets/props.png" id="3"]',
             '[ext_resource type="Script" path="res://scripts/maps/prop_set.gd" id="4"]']
    for k, sid in enumerate(SETS):
        lines.append(f'[ext_resource type="Resource" path="res://{SETS_DIR}/{sid}.tres" id="set_{k}"]')
    lines.append("")
    order = sorted(NAMES, key=lambda k: (NAMES[k][1], k[1], k[0]))
    for i, key in enumerate(order):
        pid, group, bw, bd = NAMES[key]
        x, y, rw, rh, ax, ay = comps[key]
        lines += [f'[sub_resource type="Resource" id="prop_{i}"]', 'script = ExtResource("2")',
                  f'id = &"{pid}"', f'group = &"{group}"', f"region = Rect2i({x}, {y}, {rw}, {rh})",
                  f"anchor = Vector2({ax}, {ay})", f"block_size = Vector2({bw}, {bd})", ""]
    refs = ", ".join(f'SubResource("prop_{i}")' for i in range(len(order)))
    lines += ["[resource]", 'script = ExtResource("1")', 'sheet = ExtResource("3")',
              f'props = Array[ExtResource("2")]([{refs}])',
              'sets = Array[ExtResource("4")]([' + ", ".join(f'ExtResource("set_{k}")' for k in range(len(SETS))) + "])", ""]
    open(OUT, "w").write("\n".join(lines))
    write_sets({NAMES[k][0] for k in NAMES})
    print(f"wrote {OUT}: {len(order)} props")
    for key in order:
        print(NAMES[key][0], comps[key])


def write_sets(known):
    import os
    os.makedirs(SETS_DIR, exist_ok=True)
    for sid, (title, place, mirror, members) in SETS.items():
        out = ['[gd_resource type="Resource" script_class="PropSet" format=3]', "",
               '[ext_resource type="Script" path="res://scripts/maps/prop_set.gd" id="1"]',
               '[ext_resource type="Script" path="res://scripts/maps/prop_set_member.gd" id="2"]', ""]
        for i, m in enumerate(members):
            for pid in m["props"]:
                assert pid in known, f"{sid}: unknown prop {pid}"
            lo, hi = m["n"]
            names = ", ".join(f'&"{x}"' for x in m["props"])
            out += [f'[sub_resource type="Resource" id="m{i}"]', 'script = ExtResource("2")',
                    f"props = Array[StringName]([{names}])"]
            if m["group"]:
                out.append(f'group = &"{m["group"]}"')
            out += [f'offset = Vector2({m["off"][0]}, {m["off"][1]})', f'step = Vector2({m["step"][0]}, {m["step"][1]})',
                    f"count_min = {lo}", f"count_max = {hi}", f'spread = {float(m["spread"])}', f'chance = {float(m["chance"])}', ""]
        refs = ", ".join(f'SubResource("m{i}")' for i in range(len(members)))
        out += ["[resource]", 'script = ExtResource("1")', f'id = &"{sid}"', f'display_name = "{title}"',
                f"place = {['OPEN', 'BAND', 'WALL'].index(place)}", f'mirror = {"true" if mirror else "false"}',
                f'members = Array[ExtResource("2")]([{refs}])', ""]
        open(f"{SETS_DIR}/{sid}.tres", "w").write("\n".join(out))
    print(f"wrote {len(SETS)} sets to {SETS_DIR}")


main()

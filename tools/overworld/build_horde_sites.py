#!/usr/bin/env python3
"""Writes content/overworld/data/horde_sites.json (spec 1.8): where hordes can be. Route sites every ROUTE_STRIDE points of
main_path; trail sites along the side trails that lead from the route to every camp, cache, cave, dungeon and special more
than 20 tiles from it. A multi-source BFS from the route over walkable tiles (collision.png > 127) gives every tile its
distance to the route; a trail walks that field down from its marker, at each step taking the neighbour with the greatest
distance to a wall (edge_depth.png is 0 on walkable tiles, so the wall distance is computed here), so it follows the middle
of the corridor. A trail is cut where it meets an earlier marker's trail. Deterministic; `--check` compares with the file.
usage: python3 tools/overworld/build_horde_sites.py [--check]
"""
import json
import struct
import sys
import zlib

import numpy as np

COLLISION = "content/overworld/data/collision.png"
ZONES = "content/overworld/data/zones.png"
MARKERS = "content/overworld/data/markers.json"
OUT = "content/overworld/data/horde_sites.json"
SAFE_KINDS = ("start_camp", "checkpoint", "gate")
TRAIL_KINDS = ("camp", "cache", "cave", "dungeon", "special")
SAFE_RADIUS = 14
ROUTE_STRIDE = 8
POINT_SPACING = 8  # tiles between main_path points
MIN_TRAIL_DIST = 20
TRAIL_STRIDE = 40
TRAIL_SKIP = 30
WALL_CAP = 15


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
    raw = np.frombuffer(zlib.decompress(idat), dtype=np.uint8).reshape(h, w + 1)
    out = np.zeros((h, w), dtype=np.int32)
    prev = np.zeros(w, dtype=np.int32)
    for y in range(h):
        f = raw[y, 0]
        line = raw[y, 1:].astype(np.int32)
        if f == 1:
            line = np.cumsum(line) & 255
        elif f == 2:
            line = (line + prev) & 255
        elif f == 3:
            a = 0
            for i in range(w):
                line[i] = (line[i] + (a + prev[i]) // 2) & 255
                a = line[i]
        elif f == 4:
            a = c = 0
            for i in range(w):
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
                a, c = line[i], b
        out[y] = line
        prev = out[y]
    return out


def bfs_from_route(walk, sources):
    """Steps (4 neighbours) from the nearest source over walkable tiles; -1 where unreachable."""
    h, w = walk.shape
    dist = np.full((h, w), -1, dtype=np.int32)
    front = np.zeros((h, w), dtype=bool)
    for x, y in sources:
        front[y, x] = True
    dist[front] = 0
    d = 0
    while front.any():
        d += 1
        nxt = np.zeros_like(front)
        nxt[1:] |= front[:-1]
        nxt[:-1] |= front[1:]
        nxt[:, 1:] |= front[:, :-1]
        nxt[:, :-1] |= front[:, 1:]
        nxt &= walk & (dist < 0)
        dist[nxt] = d
        front = nxt
    return dist


def wall_distance(walk):
    """Chebyshev distance of walkable tiles to the nearest blocked tile, capped at WALL_CAP (the map edge counts as wall)."""
    h, w = walk.shape
    wd = np.zeros((h, w), dtype=np.int32)
    alive = walk.copy()
    for d in range(1, WALL_CAP + 1):
        pad = np.pad(alive, 1, constant_values=False)
        eroded = alive.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                eroded &= pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        wd[eroded] = d
        alive = eroded
    return wd


def nearest_walkable(walk, x, y):
    if walk[y, x]:
        return x, y
    for r in range(1, 40):
        best = None
        for yy in range(max(0, y - r), min(walk.shape[0], y + r + 1)):
            for xx in range(max(0, x - r), min(walk.shape[1], x + r + 1)):
                if walk[yy, xx]:
                    k = ((xx - x) ** 2 + (yy - y) ** 2, yy, xx)
                    if best is None or k < best:
                        best = k
        if best:
            return best[2], best[1]
    raise SystemExit("marker with no walkable tile near it: %d,%d" % (x, y))


def build() -> str:
    walk = read_png_gray(COLLISION) > 127
    zone_img = read_png_gray(ZONES)
    data = json.load(open(MARKERS))
    markers, zones, main_path = data["markers"], data["zones"], data["main_path"]
    dist = bfs_from_route(walk, [tuple(p) for p in main_path])
    wd = wall_distance(walk)
    safe = [(m["x"], m["y"]) for m in markers if m["kind"] in SAFE_KINDS]

    def near_safe(x, y):
        return any((x - sx) ** 2 + (y - sy) ** 2 <= SAFE_RADIUS ** 2 for sx, sy in safe)

    route = []
    for i in range(0, len(main_path), ROUTE_STRIDE):
        x, y = main_path[i]
        if near_safe(x, y):
            continue
        arc = i * POINT_SPACING
        zi = min(int(zone_img[y, x]) // 30, len(zones) - 1)  # the zone mask decides; t is clamped at a border
        z = zones[zi]
        t = (arc - z["route_start_tile"]) / float(z["route_end_tile"] - z["route_start_tile"])
        route.append({"x": x, "y": y, "zone": zi, "t": round(min(max(t, 0.0), 1.0), 4)})

    owned = set()
    trails = []
    for mi, m in enumerate(markers):
        if m["kind"] not in TRAIL_KINDS:
            continue
        x, y = nearest_walkable(walk, m["x"], m["y"])
        total = int(dist[y, x])
        if total <= MIN_TRAIL_DIST:
            continue
        # walk down the distance field, listed from the marker to the road, stopping where an earlier trail is joined
        tiles = [(x, y)]
        while dist[y, x] > 0:
            if (x, y) in owned and len(tiles) > 1:
                tiles.pop()  # the joining tile belongs to the earlier trail
                break
            best = None
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < walk.shape[1] and 0 <= ny < walk.shape[0] and dist[ny, nx] == dist[y, x] - 1:
                    k = (-int(wd[ny, nx]), ny, nx)
                    if best is None or k < best:
                        best = k
            x, y = best[2], best[1]
            tiles.append((x, y))
        for t in tiles:
            owned.add(t)
        points = []
        for tx, ty in reversed(tiles):  # road to dead end
            d = int(dist[ty, tx])
            if d >= TRAIL_SKIP and d % TRAIL_STRIDE == 0 and not near_safe(tx, ty):
                points.append({"x": tx, "y": ty, "t": round(d / float(total), 4)})
        trails.append({"marker": mi, "kind": m["kind"], "points": points})
    return json.dumps({"version": 1, "route": route, "trails": trails}, separators=(",", ":")) + "\n"


def main():
    text = build()
    if "--check" in sys.argv:
        if open(OUT).read() != text:
            print("horde_sites.json differs from a rebuild")
            sys.exit(1)
        print("horde_sites.json is up to date")
        return
    open(OUT, "w").write(text)
    d = json.loads(text)
    print("route sites", len(d["route"]), "trails", len(d["trails"]), "trail points", sum(len(t["points"]) for t in d["trails"]))


if __name__ == "__main__":
    main()

"""Procedural overworld map generator for the game (1 map pixel = 1 Godot tile = 16 px).

Run:  python generate_map.py          (needs numpy, pillow, scipy)
Writes layer PNGs to ./layers, plus map-v2.png, collision.png, zones.png, map_data.json.
"""
import json, math, os, sys
import numpy as np
from scipy import ndimage as ndi
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = HERE
VER = "v3"
LAY = os.path.join(OUT, "layers_" + VER)
os.makedirs(LAY, exist_ok=True)
N = 2000
TILE = 16
SEED = 4242
rng = np.random.default_rng(SEED)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ----------------------------------------------------------------- noise helpers
_cache = {}


def vnoise(scale, seed):
    key = (scale, seed)
    if key in _cache:
        return _cache[key]
    r = np.random.default_rng(seed)
    n = int(N / scale) + 4
    g = r.random((n, n))
    z = ndi.zoom(g, scale, order=3)[:N, :N]
    z = (z - z.mean()) / (z.std() + 1e-9) * 0.2 + 0.5
    z = np.clip(z, 0, 1).astype(np.float32)
    _cache[key] = z
    return z


def fbm(seed, scales=(120, 50, 20, 8), weights=(0.4, 0.3, 0.2, 0.1)):
    a = sum(w * vnoise(s, seed + i * 17) for i, (s, w) in enumerate(zip(scales, weights)))
    a = (a - a.mean()) / (a.std() + 1e-9) * 0.2 + 0.5
    return np.clip(a, 0, 1).astype(np.float32)


def smooth1d(n, scale, seed):
    r = np.random.default_rng(seed)
    a = ndi.gaussian_filter1d(r.standard_normal(n + int(scale * 6)), scale)[:n]
    return a / (a.std() + 1e-9)


# ----------------------------------------------------------------- zones
ZONES = [
    dict(id="mossy_hollow", name="Mossveil Wilds", dungeon="Mossy Hollow",
         ground=["#27341f", "#2f3f25", "#384a2c", "#445a33"],
         road=["#4a3b29", "#5a4833", "#6b573d", "#7d6849"],
         A=("canopy", ["#0f1a10", "#16261a", "#1f3623", "#2c4a2f"]),
         B=("rock", ["#1f221d", "#2e322b", "#41463b", "#5a604f"]),
         spark=None, sparkp=0, detail="flowers"),
    dict(id="flooded_gallery", name="Drownmire Fens", dungeon="Flooded Gallery",
         ground=["#1f2f2c", "#283a36", "#324640", "#3e544c"],
         road=["#3d3a2c", "#4c4835", "#5d5840", "#6f694b"],
         A=("water", ["#0b1a22", "#102631", "#17364a", "#2f6a80"]),
         B=("canopy", ["#0e1c16", "#15291f", "#1e3a2b", "#2b4f3a"]),
         spark=None, sparkp=0, detail="pools"),
    dict(id="spore_cavern", name="Sporefall Thicket", dungeon="Spore Cavern",
         ground=["#2a2536", "#342e45", "#3f3855", "#4c4466"],
         road=["#4a3d4a", "#5a4a58", "#6b5868", "#7d6a7a"],
         A=("canopy", ["#1d1030", "#2e1a4a", "#47286a", "#6a3d96"]),
         B=("rock", ["#1f1d2a", "#2d2a3c", "#403c55", "#58536f"]),
         spark="#8fe07a", sparkp=0.012, detail="spores"),
    dict(id="bone_warren", name="Ossuary Moors", dungeon="Bone Warren",
         ground=["#3c3935", "#48443e", "#575148", "#69625a"],
         road=["#5a5042", "#6a5f4e", "#7c705c", "#8f826c"],
         A=("rock", ["#2c2a27", "#46423b", "#6b655a", "#9a927f"]),
         B=("canopy", ["#141312", "#201e1c", "#2e2b28", "#403c37"]),
         spark="#c9c1a8", sparkp=0.012, detail="bones"),
    dict(id="sulfur_pits", name="Yellowreek Flats", dungeon="Sulfur Pits",
         ground=["#463f1f", "#554d26", "#675d2e", "#7b7036"],
         road=["#5e4a2a", "#6f5934", "#826a40", "#967d4d"],
         A=("chasm", ["#0d0b03", "#1a1507", "#2e260d", "#8a7a2c"]),
         B=("rock", ["#2d2813", "#403a1c", "#5a5229", "#7a7035"]),
         spark="#d8d040", sparkp=0.004, detail="sulfur"),
    dict(id="ember_depths", name="Cinderreach", dungeon="Ember Depths",
         ground=["#262020", "#312929", "#3d3231", "#4b3e3a"],
         road=["#403028", "#503c30", "#624b3a", "#765a45"],
         A=("lava", ["#6a1408", "#a8300c", "#e0651a", "#ffb84a"]),
         B=("rock", ["#121011", "#1e1a1b", "#2e282a", "#443b3e"]),
         spark="#ff9a3c", sparkp=0.006, detail="embers"),
    dict(id="frostbite_grotto", name="Frostbite Reach", dungeon="Frostbite Grotto",
         ground=["#5d6d7c", "#6c7d8c", "#7f909f", "#95a6b4"],
         road=["#4c4f54", "#5f6369", "#767b82", "#8e939a"],
         A=("ice", ["#2e4559", "#456680", "#6b92ac", "#a4c8dc"]),
         B=("canopy", ["#10211f", "#18302c", "#224239", "#2f574b"]),
         spark="#e8f1f7", sparkp=0.02, detail="snow"),
    dict(id="crystal_vault", name="Shardlands", dungeon="Crystal Vault",
         ground=["#241f33", "#2d2741", "#38314f", "#453d61"],
         road=["#4a4560", "#5a5574", "#6c678a", "#8079a0"],
         A=("crystal", ["#1a1640", "#2d2a78", "#4e48c0", "#8f86f0"]),
         B=("rock", ["#17142a", "#221e3a", "#312c52", "#453f6e"]),
         spark="#7ee8f0", sparkp=0.012, detail="glints"),
]
NZ = len(ZONES)
GATE_NAMES = ["Mossgate Pass", "Drowned Causeway", "Sporegate Gorge", "Boneyard Gate",
              "Sulfur Gap", "Ashen Rift", "Frostbite Pass"]

# ----------------------------------------------------------------- main path
CTRL = [(60, 1930), (150, 1895), (300, 1840), (480, 1800), (650, 1850), (850, 1790),
        (1050, 1840), (1250, 1780), (1450, 1830), (1650, 1790), (1800, 1760),
        (1880, 1680), (1900, 1560), (1880, 1440), (1900, 1320), (1860, 1190), (1790, 1090),
        (1650, 1020), (1480, 1060), (1300, 990), (1120, 1040), (950, 980), (780, 1030),
        (600, 985), (430, 1040), (290, 1000), (180, 940),
        (110, 850), (100, 730), (120, 610), (110, 490), (150, 380),
        (230, 300), (380, 220), (560, 170), (760, 230), (950, 180), (1150, 235),
        (1350, 170), (1550, 230), (1730, 180), (1880, 150)]

BANDS = {1: (1500, 2000), 2: (580, 1420), 3: (0, 500)}


def band_of(y):
    for k, (lo, hi) in BANDS.items():
        if lo <= y <= hi:
            return k
    return None


def catmull(pts):
    P = np.array(pts, float)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = int(np.linalg.norm(p2 - p1) / 2) + 2
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return np.array(out)


def resample(poly):
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(poly, axis=0).T))]
    s = np.arange(0, d[-1], 1.0)
    return np.c_[np.interp(s, d, poly[:, 0]), np.interp(s, d, poly[:, 1])], s


main_xy, main_s = resample(catmull(CTRL))
L = len(main_xy)
tang = np.gradient(main_xy, axis=0)
tang /= np.linalg.norm(tang, axis=1, keepdims=True)
norm = np.c_[-tang[:, 1], tang[:, 0]]
# wobble the centre-line a little so it never looks drawn with a ruler
wob = smooth1d(L, 40, 1) * 9
main_xy = main_xy + norm * wob[:, None]
tang = np.gradient(main_xy, axis=0)
tang /= np.linalg.norm(tang, axis=1, keepdims=True)
norm = np.c_[-tang[:, 1], tang[:, 0]]
print("main path length", L)

gate_s = [int(L * k / NZ) for k in range(1, NZ)]
# nudge gates so they do not sit on a sharp bend
for gi, g in enumerate(gate_s):
    best, bs = 1e9, g
    for cand in range(g - 120, g + 120, 8):
        a_, b_ = tang[cand - 20], tang[cand + 20]
        c = abs(a_[0] * b_[1] - a_[1] * b_[0])
        if c < best:
            best, bs = c, cand
    gate_s[gi] = bs
zone_bounds = np.array(gate_s, float)


def zone_of_s(s):
    return int(np.digitize(s, zone_bounds))


# corridor radius profile
Rc = np.clip(17 + 6 * smooth1d(L, 60, 2), 11, 26)
for g in gate_s:
    d = np.abs(np.arange(L) - g)
    t = np.clip(1 - d / 55.0, 0, 1)
    t = t * t * (3 - 2 * t)
    Rc = Rc * (1 - t) + 6.0 * t
camp_start = (50, 1936)

# ----------------------------------------------------------------- side branches
MAXP = 120000
pts = np.zeros((MAXP, 2))
own = np.zeros(MAXP, int)
stp = np.zeros(MAXP, int)
mcount = 0
M = main_xy[::3]
branches = []


def valid(q, me, step, parent, bid):
    x, y = q
    if not (45 <= x <= N - 45 and 45 <= y <= N - 45):
        return False
    lo, hi = BANDS[bid]
    if not (lo + 48 <= y <= hi - 48):
        return False
    if (x - camp_start[0]) ** 2 + (y - camp_start[1]) ** 2 < 135 ** 2:
        return False
    if step >= 18:
        if np.hypot(M[:, 0] - x, M[:, 1] - y).min() < 56:
            return False
    if mcount > 0:
        d2 = (pts[:mcount, 0] - x) ** 2 + (pts[:mcount, 1] - y) ** 2
        close = d2 < 52 ** 2
        if close.any():
            o = own[:mcount][close]
            st = stp[:mcount][close]
            dd = d2[close]
            bad = (o != me) & ~((o == parent) & (step < 22))
            bad |= (o == me) & (st < step - 12) & (dd < 32 ** 2)
            if bad.any():
                return False
    return True


def grow(origin, theta, me, parent, bid, maxsteps):
    global mcount
    start = mcount
    path = [np.array(origin, float)]
    cur = path[0]
    th = theta
    for step in range(maxsteps):
        order = [0, 0.35, -0.35, 0.7, -0.7, 1.1, -1.1, 1.6, -1.6]
        if rng.random() < 0.5:
            order = [0] + [-v for v in order[1:]]
        ok = False
        for dth in order:
            t = th + dth
            q = cur + 4 * np.array([math.cos(t), math.sin(t)])
            if valid(q, me, step, parent, bid):
                th = t + rng.normal(0, 0.15)
                cur = q
                path.append(q)
                pts[mcount] = q
                own[mcount] = me
                stp[mcount] = step
                mcount += 1
                ok = True
                break
        if not ok:
            break
    if len(path) < 22:
        mcount = start
        return None
    return np.array(path), th


def spawn_all():
    bid_counter = 1
    s = 140.0
    while s < L - 120:
        i = int(s)
        s += rng.uniform(55, 90)
        if any(abs(i - g) < 80 for g in gate_s):
            continue
        bid = band_of(main_xy[i][1])
        if bid is None:
            continue
        for side in (1, -1):
            if rng.random() > 0.88:
                continue
            th0 = math.atan2(norm[i][1] * side, norm[i][0] * side) + rng.normal(0, 0.3)
            mx = int(rng.integers(30, 110))
            r = grow(main_xy[i], th0, bid_counter, 0, bid, mx)
            if r is None:
                continue
            pth, th = r
            br = dict(id=bid_counter, pts=pth, s0=i, band=bid, parent=0, end_heading=th)
            branches.append(br)
            me = bid_counter
            bid_counter += 1
            if len(pth) > 40 and rng.random() < 0.6:
                j = int(rng.integers(14, len(pth) - 14))
                hd = math.atan2(*(pth[j + 1] - pth[j])[::-1])
                sgn = 1 if rng.random() < 0.5 else -1
                r2 = grow(pth[j], hd + sgn * 1.2, bid_counter, me, bid, int(rng.integers(16, 50)))
                if r2 is not None:
                    branches.append(dict(id=bid_counter, pts=r2[0], s0=i, band=bid, parent=me,
                                         end_heading=r2[1]))
                    bid_counter += 1


spawn_all()
for b in branches:
    b["zone"] = zone_of_s(b["s0"])
    b["len"] = len(b["pts"]) * 4
print("branches", len(branches), [sum(1 for b in branches if b["zone"] == z) for z in range(NZ)])

# ----------------------------------------------------------------- assign site types
CLEAR_R = dict(dungeon=30, camp=22, cave=15, special=17, ruin=13)
SPECIAL_KINDS = ["shrine", "ruins", "altar", "hermit"]
sites = []
for z in range(NZ):
    bz = sorted([b for b in branches if b["zone"] == z], key=lambda b: -b["len"])
    order = ["dungeon", "cave", "camp", "camp", "special", "cave", "camp", "special", "camp", "ruin"]
    for k, b in enumerate(bz):
        typ = order[k] if k < len(order) else rng.choice(["camp", "ruin", "cave", "special"])
        b["type"] = typ
        sites.append(b)
rest = [b for b in branches if "type" not in b]
for b in rest:
    b["type"] = "ruin"

# ----------------------------------------------------------------- raster the structure fields
# main corridor
cx = np.clip(np.round(main_xy[:, 0]).astype(int), 0, N - 1)
cy = np.clip(np.round(main_xy[:, 1]).astype(int), 0, N - 1)
cmask = np.zeros((N, N), bool)
cmask[cy, cx] = True
dC, indC = ndi.distance_transform_edt(~cmask, return_indices=True)
sImg = np.zeros((N, N), np.float32)
sImg[cy, cx] = main_s
RImg = np.zeros((N, N), np.float32)
RImg[cy, cx] = Rc
s_near = sImg[indC[0], indC[1]]
R_near = RImg[indC[0], indC[1]]
edge1 = fbm(11, (30, 12, 5), (0.5, 0.3, 0.2))
walk_main = (R_near - dC + (edge1 - 0.5) * 9) > 0

# main road: meanders inside the corridor
road_off = smooth1d(L, 45, 3) * 0.3 * Rc
rxy = main_xy + norm * np.clip(road_off, -Rc * 0.6, Rc * 0.6)[:, None]
rx = np.clip(np.round(rxy[:, 0]).astype(int), 0, N - 1)
ry = np.clip(np.round(rxy[:, 1]).astype(int), 0, N - 1)
rmask = np.zeros((N, N), bool)
rmask[ry, rx] = True
dR = ndi.distance_transform_edt(~rmask)
road_w = 3.3 + 0.9 * (edge1 - 0.5) * 2
road = (dR < road_w) & walk_main

# branches
bmask = np.zeros((N, N), bool)
bR = np.zeros((N, N), np.float32)
for b in branches:
    p = b["pts"]
    b["r"] = float(rng.uniform(6.5, 9.0))
    fine = []
    for a, c in zip(p[:-1], p[1:]):
        for t in np.linspace(0, 1, 5, endpoint=False):
            fine.append(a + (c - a) * t)
    fine.append(p[-1])
    fine = np.array(fine)
    fx = np.clip(np.round(fine[:, 0]).astype(int), 0, N - 1)
    fy = np.clip(np.round(fine[:, 1]).astype(int), 0, N - 1)
    bmask[fy, fx] = True
    bR[fy, fx] = b["r"]
dB, indB = ndi.distance_transform_edt(~bmask, return_indices=True)
R_b = bR[indB[0], indB[1]]
edge2 = fbm(23, (25, 10, 4), (0.5, 0.3, 0.2))
walk_br = (R_b - dB + (edge2 - 0.5) * 6) > 0
trail = (dB < 1.9) & walk_br

# clearings
yy, xx = np.mgrid[0:N, 0:N]
walk_clear = np.zeros((N, N), bool)


def blob(cx_, cy_, r, seed):
    global walk_clear
    rr = np.random.default_rng(seed)
    a, b_, c = rr.uniform(0, 6.28, 3)
    x0, x1 = max(0, int(cx_ - r * 1.6)), min(N, int(cx_ + r * 1.6))
    y0, y1 = max(0, int(cy_ - r * 1.6)), min(N, int(cy_ + r * 1.6))
    X, Y = xx[y0:y1, x0:x1] - cx_, yy[y0:y1, x0:x1] - cy_
    th = np.arctan2(Y, X)
    rad = r * (1 + 0.16 * np.sin(3 * th + a) + 0.1 * np.sin(5 * th + b_) + 0.06 * np.sin(8 * th + c))
    walk_clear[y0:y1, x0:x1] |= (np.hypot(X, Y) + (edge2[y0:y1, x0:x1] - 0.5) * 4) < rad


for b in branches:
    e = b["pts"][-1]
    b["end"] = (float(e[0]), float(e[1]))
    b["cr"] = CLEAR_R[b["type"]]
    blob(e[0], e[1], b["cr"], 100 + b["id"])

# roaming arenas: widened pockets on the main corridor
arenas = []
for z in range(NZ):
    z0 = 0 if z == 0 else gate_s[z - 1]
    z1 = gate_s[z] if z < NZ - 1 else L - 1
    for _ in range(3):
        for attempt in range(40):
            i = int(rng.uniform(z0 + 110, z1 - 110))
            if band_of(main_xy[i][1]) is None:
                continue
            side = 1 if rng.random() < 0.5 else -1
            r = float(rng.uniform(26, 36))
            c = main_xy[i] + norm[i] * side * (Rc[i] * 0.4 + 10)
            if not (r + 50 < c[0] < N - r - 50 and r + 50 < c[1] < N - r - 50):
                continue
            lo, hi = BANDS[band_of(main_xy[i][1])]
            if not (lo + r + 30 < c[1] < hi - r - 30):
                continue
            if mcount and (np.hypot(pts[:mcount, 0] - c[0], pts[:mcount, 1] - c[1]).min() < r + 34):
                continue
            if any(math.hypot(a["x"] - c[0], a["y"] - c[1]) < 2 * r + 40 for a in arenas):
                continue
            if any(abs(i - g) < 140 for g in gate_s):
                continue
            blob(c[0], c[1], r, 900 + len(arenas))
            arenas.append(dict(x=float(c[0]), y=float(c[1]), r=r, zone=z))
            break

# start camp (user-drawn yellow blob) + final dungeon plaza
camp_mask = np.zeros((N, N), bool)
camp_mask[1888:1985, 0:103] = True
camp_src = os.path.join(HERE, "camp_mask.png")
if os.path.exists(camp_src):
    camp_mask = np.array(Image.open(camp_src).convert("L")) > 128
camp_mask = ndi.binary_dilation(camp_mask, iterations=4)
FINAL = main_xy[-1].copy()
blob(FINAL[0], FINAL[1], 36, 777)
walk = walk_main | walk_br | walk_clear | camp_mask
# remove tiny islands, fill tiny holes
lab, nl = ndi.label(walk)
sizes = ndi.sum(walk, lab, range(1, nl + 1))
for k, sz in enumerate(sizes, 1):
    if sz < 400:
        walk[lab == k] = False
holes = ndi.binary_fill_holes(walk) & ~walk
hl, hn = ndi.label(holes)
hs = ndi.sum(holes, hl, range(1, hn + 1))
for k, sz in enumerate(hs, 1):
    if sz < 400:
        walk[hl == k] = True
print("walkable fraction", walk.mean())

# ----------------------------------------------------------------- zone field (soft, dithered)
zn = fbm(31, (140, 60, 25), (0.5, 0.3, 0.2))
zs = s_near + (zn - 0.5) * 240          # warp so the blend follows the land, not a straight line
BLEND_W = 460.0                          # tiles of route over which one biome fades into the next
# spatially-clumped dither threshold, rank-normalised to a uniform 0..1
_t = 0.55 * vnoise(5, 91) + 0.3 * vnoise(11, 92) + 0.15 * vnoise(2, 93)
_r = np.empty(N * N, np.float32)
_r[np.argsort(_t, axis=None)] = np.linspace(0, 1, N * N, dtype=np.float32)
thr = _r.reshape(N, N)
zone = np.zeros((N, N), np.int8)
for b_ in zone_bounds:
    u = np.clip((zs - b_) / BLEND_W + 0.5, 0, 1)
    u = u * u * (3 - 2 * u)
    zone += (thr < u).astype(np.int8)
zone = np.clip(zone, 0, NZ - 1).astype(np.intp)

# ----------------------------------------------------------------- shortcut / connectivity verification
def verify():
    blk = 4
    h = N // blk
    cells = walk.reshape(h, blk, h, blk).mean(axis=(1, 3)) > 0.55
    ids = -np.ones((h, h), int)
    ids[cells] = np.arange(cells.sum())
    rows, cols, w = [], [], []
    for dy, dx, wt in ((0, 1, 1), (1, 0, 1), (1, 1, 1.414), (1, -1, 1.414)):
        A = ids[0:h - dy, max(0, -dx):h - max(0, dx)]
        B = ids[dy:h, max(0, dx):h - max(0, -dx)]
        m = (A >= 0) & (B >= 0)
        rows.append(A[m]); cols.append(B[m]); w.append(np.full(m.sum(), wt * blk))
    r_, c_, w_ = np.concatenate(rows), np.concatenate(cols), np.concatenate(w)
    g = csr_matrix((np.r_[w_, w_], (np.r_[r_, c_], np.r_[c_, r_])), shape=(cells.sum(),) * 2)
    sy, sx = int(camp_start[1] // blk), int(camp_start[0] // blk)
    src = ids[sy, sx]
    dist = dijkstra(g, indices=src)
    cy_, cx_ = np.where(cells)
    sn = s_near[(cy_ * blk + blk // 2), (cx_ * blk + blk // 2)]
    d = dist[ids[cy_, cx_]]
    unreachable = int(np.isinf(d).sum())
    short = sn - d
    short[np.isinf(d)] = 0
    # a shortcut is a cell reached with far less walking than its position along the route
    worst = float(np.max(short))
    bad = int((short > 140).sum())
    if bad:
        k = np.where(short > 140)[0]
        print('flagged cells (x,y,s_near,walked):', [(int(cx_[i]*blk), int(cy_[i]*blk), int(sn[i]), int(d[i])) for i in k[::4]])
    gate_ok = []
    for g_i in gate_s:
        px, py = main_xy[g_i]
        k = ids[int(py // blk), int(px // blk)]
        gate_ok.append((g_i, float(dist[k]) if k >= 0 else None))
    return unreachable, worst, bad, gate_ok


unr, worst, bad, gate_ok = verify()
print("unreachable cells", unr, "| max shortcut (tiles saved)", round(worst), "| cells with >140 saved", bad)
print("gate arc-length vs walked distance:", [(g, round(d) if d else None) for g, d in gate_ok])

np.savez_compressed(os.path.join(HERE, "layout_cache.npz"), walk=walk, road=road, trail=trail,
                    zone=zone, s_near=s_near)
if "--layout-only" in sys.argv:
    prev = np.zeros((N, N, 3), np.uint8)
    cols = np.array([hexc("#" + c) for c in ["4a7a3a", "3a8a9a", "8a4aa0", "c8c0a0", "c8c030", "d05a20", "a0c8e8", "6a60e0"]])
    prev[:] = (cols[zone] * 0.35).astype(np.uint8)
    prev[walk] = cols[zone][walk]
    prev[road] = (230, 200, 120)
    prev[trail & ~road] = (190, 160, 100)
    Image.fromarray(prev).resize((1000, 1000), Image.NEAREST).save(os.path.join(HERE, "layout_preview.png"))
    sys.exit(0)

exec(open(os.path.join(HERE, "render_map.py")).read())

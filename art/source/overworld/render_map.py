# Rendering stage. exec()'d from generate_map.py (shares its globals).
import time
_t0 = time.time()
rnd = np.random.default_rng(SEED + 1).random((N, N)).astype(np.float32)
blk = ~walk

# ---- palette lookup tables
GP = np.array([[hexc(c) for c in z["ground"]] for z in ZONES], np.uint8)      # (8,4,3)
RP = np.array([[hexc(c) for c in z["road"]] for z in ZONES], np.uint8)
AP = np.array([[hexc(c) for c in z["A"][1]] for z in ZONES], np.uint8)
BP = np.array([[hexc(c) for c in z["B"][1]] for z in ZONES], np.uint8)

# ---- ground
g = 0.5 * fbm(41, (70, 30), (0.6, 0.4)) + 0.3 * vnoise(12, 43) + 0.2 * vnoise(4, 44)
q = np.quantile(g, [0.22, 0.5, 0.82])
gl = np.digitize(g, q)
ground = GP[zone, gl].astype(np.int16)
sp = rnd
light = sp < 0.03
dark = (sp > 0.97)
ground[light] = GP[zone, np.minimum(gl + 1, 3)][light]
ground[dark] = GP[zone, np.maximum(gl - 1, 0)][dark]

# per-biome ground details (still walkable)
n45 = vnoise(45, 51)
n35 = vnoise(35, 52)
ridged = 1 - np.abs(2 * vnoise(40, 53) - 1)


def paint(mask, color):
    ground[mask] = hexc(color)


r2 = np.random.default_rng(SEED + 2).random((N, N))
for zi, z in enumerate(ZONES):
    zm = (zone == zi) & walk
    d = z["detail"]
    if d == "flowers":
        paint(zm & (r2 < 0.004), "#7a3a3a"); paint(zm & (r2 > 0.996), "#8c8a4a")
    elif d == "pools":
        pool = zm & (n35 > 0.7)
        ground[pool] = hexc("#22414b"); ground[pool & (rnd > 0.8)] = hexc("#3a6a78")
    elif d == "spores":
        paint(zm & (r2 < 0.005), "#7fd69a")
    elif d == "bones":
        paint(zm & (r2 < 0.006), "#bdb59d")
    elif d == "sulfur":
        patch = zm & (n45 > 0.76)
        ground[patch] = hexc("#8e8a2a"); ground[patch & (n45 > 0.84)] = hexc("#c4bc3e")
    elif d == "embers":
        paint(zm & (r2 < 0.004), "#d4561a")
        paint(zm & (ridged > 0.93), "#7a2a12")
    elif d == "snow":
        paint(zm & (n45 > 0.74), "#aebdc9"); paint(zm & (n35 < 0.22), "#86a9c2")
    elif d == "glints":
        paint(zm & (r2 < 0.006), "#8ee6f0")

# ---- blockers
de = ndi.distance_transform_edt(blk).astype(np.float32)   # distance to nearest walkable pixel (0 on walkable)
# rock heightfield (ridged mountains), lit from the top-left
hr = 0.55 * (1 - np.abs(2 * vnoise(60, 61) - 1)) + 0.3 * vnoise(22, 62) + 0.15 * vnoise(7, 63)
gy, gx = np.gradient(hr)
sr = hr + 9.0 * (gx + gy)
Lr = np.digitize(sr, np.quantile(sr, [0.25, 0.55, 0.85]))
# canopy clumps
hc = 0.55 * vnoise(6, 64) + 0.3 * vnoise(11, 65) + 0.15 * vnoise(25, 66)
gy, gx = np.gradient(hc)
sc = hc + 8.0 * (gx + gy)
Lc = np.digitize(sc, np.quantile(sc, [0.28, 0.58, 0.86]))
# water
wv = 0.7 * vnoise(25, 67) + 0.3 * vnoise(7, 68)
Lw = np.digitize(wv, np.quantile(wv, [0.3, 0.65, 0.93]))
Lw = np.where(vnoise(3, 69) > 0.86, 3, Lw)
# chasm: rim -> shaft
Lch = np.select([de <= 2, de <= 5, de <= 12], [3, 2, 1], 0)
Lch = np.where((ridged > 0.9) & (de > 3), np.minimum(Lch + 1, 2), Lch)
# crystal (sharper facets) and ice
sc2 = hr + 16.0 * (gx + gy)
Lcr = np.digitize(sc2, np.quantile(sc2, [0.3, 0.6, 0.88]))
LEVEL = dict(rock=Lr, canopy=Lc, water=Lw, chasm=Lch, ice=Lr, crystal=Lcr, lava=Lr)
bm = fbm(71, (110, 45), (0.65, 0.35))
lava_mask = (1 - np.abs(2 * vnoise(55, 72) - 1) > 0.86) & (de > 2)

out = np.zeros((N, N, 3), np.int16)
blk_img = np.zeros((N, N, 4), np.uint8)
for zi, z in enumerate(ZONES):
    zm = blk & (zone == zi)
    if zi == 5:
        isA = lava_mask
        LA = np.clip(np.digitize(1 - np.abs(2 * vnoise(55, 72) - 1), [0.9, 0.94, 0.97]), 0, 3)
    else:
        isA = bm > 0.5
        LA = LEVEL[z["A"][0]]
    LB = LEVEL[z["B"][0]]
    ca = AP[zi][np.clip(LA, 0, 3)]
    cb = BP[zi][np.clip(LB, 0, 3)]
    col = np.where(isA[..., None], ca, cb)
    out[zm] = col[zm]
out = out.astype(np.float32)
# mass darkening toward the middle of big blocked areas
out *= (1 - 0.16 * np.clip(de / 140, 0, 1))[..., None]
# sparkles per biome
for zi, z in enumerate(ZONES):
    if z["spark"]:
        m = blk & (zone == zi) & (rnd < z["sparkp"] * 0.6) & (r2 > 0.5)
        out[m] = hexc(z["spark"])
out = np.clip(out, 0, 255).astype(np.uint8)
# 1px dark outline where a blocker meets walkable ground
edge = blk & ndi.binary_dilation(walk, structure=ndi.generate_binary_structure(2, 1))
dark_col = np.zeros((N, N, 3), np.uint8)
for zi in range(NZ):
    dc = np.minimum(AP[zi][0], BP[zi][0])
    dark_col[zone == zi] = np.maximum(dc * 0.55, 0).astype(np.uint8)
out[edge] = dark_col[edge]
blk_img[..., :3] = out
blk_img[..., 3] = np.where(blk, 255, 0)

# ---- shadows cast down-right of blockers onto walkable ground
def shift(a, dy, dx):
    r = np.zeros_like(a)
    r[max(dy, 0):N + min(dy, 0), max(dx, 0):N + min(dx, 0)] = a[max(-dy, 0):N + min(-dy, 0), max(-dx, 0):N + min(-dx, 0)]
    return r


shad = walk & (shift(blk, 1, 1) | shift(blk, 0, 1) | shift(blk, 1, 0) | shift(blk, 2, 2))
shadow_img = np.zeros((N, N, 4), np.uint8)
shadow_img[shad] = (0, 0, 0, 95)

# ---- ground image (road + trails)
RL = np.clip(np.digitize(vnoise(5, 81), [0.35, 0.65, 0.9]), 0, 3)
road_col = RP[zone, RL]
rut = road & ((dR > road_w - 1.1) | (rnd < 0.05))
ground_full = ground.copy()
ground_full = np.where(blk[..., None], GP[zone, 1].astype(np.int16), ground_full)
ground_img = np.clip(ground_full, 0, 255).astype(np.uint8)

road_img = np.zeros((N, N, 4), np.uint8)
road_img[road] = np.c_[road_col[road], np.full(road.sum(), 255)]
rr = road & (dR > road_w - 1.0)
road_img[rr, :3] = (road_col[rr] * 0.78).astype(np.uint8)
tr = trail & ~road
trail_col = (RP[zone, np.clip(RL - 1, 0, 3)] * 0.9).astype(np.uint8)
road_img[tr] = np.c_[trail_col[tr], np.full(tr.sum(), 255)]
# worn paths in clearings (tiny dirt circle at every site)

# ---------------------------------------------------------------- sprites / drawing helpers
def new_layer():
    return Image.new("RGBA", (N, N), (0, 0, 0, 0))


def blit(img, grid, legend, cx_, cy_):
    h = len(grid); w = len(grid[0])
    x0 = int(cx_ - w // 2); y0 = int(cy_ - h + 1)
    px = img.load()
    for j, row in enumerate(grid):
        for i, ch in enumerate(row):
            c = legend.get(ch)
            if c and 0 <= x0 + i < N and 0 <= y0 + j < N:
                px[x0 + i, y0 + j] = c + (255,) if len(c) == 3 else c


O = hexc("#0c0a0a")
TENT = ["....o....", "...oto...", "..ottto..", ".ottdtto.", "ottttdtto", "ooooooooo"]
CHEST = ["ooooooo", "obbbbbo", "obgggbo", "obbbbbo", "ooooooo"]
FIRE = ["..y..", ".yRy.", "yRRRy", "sssss"]
SKULLPOLE = ["bbb", "bkb", ".b.", ".p.", ".p.", ".p."]


def tent(img, x, y, col):
    c = hexc(col)
    d = tuple(int(v * 0.45) for v in c)
    t2 = tuple(min(255, int(v * 1.25)) for v in c)
    blit(img, TENT, {"o": O, "t": c, "d": d}, x, y)
    img.putpixel((int(x) - 1, int(y) - 3), t2 + (255,))
    img.putpixel((int(x) - 2, int(y) - 2), t2 + (255,))


def campfire(img, x, y):
    blit(img, FIRE, {"y": hexc("#ffe27a"), "R": hexc("#ff7a1c"), "s": hexc("#4a4640")}, x, y)


def skullpole(img, x, y):
    blit(img, SKULLPOLE, {"b": hexc("#d8d0b8"), "k": O, "p": hexc("#4a3524")}, x, y)


def draw_ring_stones(d, cx_, cy_, r, col, n=14):
    for k in range(n):
        a = 2 * math.pi * k / n
        x = int(round(cx_ + math.cos(a) * r)); y = int(round(cy_ + math.sin(a) * r * 0.8))
        d.rectangle([x, y, x + 1, y + 1], fill=hexc(col) + (255,))


def checkpoint(img, x, y):
    d = ImageDraw.Draw(img)
    d.ellipse([x - 6, y - 5, x + 6, y + 5], fill=hexc("#3a3a40") + (255,), outline=O + (255,))
    draw_ring_stones(d, x, y, 5, "#8a8a90", 12)
    d.polygon([(x, y - 6), (x - 2, y - 1), (x + 2, y - 1)], fill=hexc("#5ee0ff") + (255,))
    d.polygon([(x, y - 4), (x - 1, y - 1), (x + 1, y - 1)], fill=hexc("#e8fbff") + (255,))
    d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=hexc("#6b5236") + (255,))
    # banner
    d.rectangle([x + 5, y - 9, x + 5, y - 1], fill=O + (255,))
    d.rectangle([x + 6, y - 9, x + 9, y - 6], fill=hexc("#2fa8c8") + (255,), outline=O + (255,))


def cave_entrance(img, x, y, zi):
    d = ImageDraw.Draw(img)
    base = hexc(ZONES[zi]["B"][1][2]); hi = hexc(ZONES[zi]["B"][1][3]); lo = hexc(ZONES[zi]["B"][1][0])
    d.ellipse([x - 9, y - 9, x + 9, y + 3], fill=base + (255,), outline=O + (255,))
    d.ellipse([x - 6, y - 8, x + 1, y - 4], fill=hi + (255,))
    d.ellipse([x - 5, y - 6, x + 5, y + 3], fill=O + (255,))
    d.rectangle([x - 5, y - 2, x + 5, y + 3], fill=O + (255,))
    d.rectangle([x - 2, y, x + 2, y + 3], fill=(40, 30, 50, 255))
    d.ellipse([x - 9, y + 1, x + 9, y + 4], outline=lo + (255,))


def dungeon_gate(img, x, y, zi, big=False):
    d = ImageDraw.Draw(img)
    s = 1.0 if not big else 1.6
    W = int(11 * s); H = int(11 * s)
    stone = hexc("#585a60"); stone_hi = hexc("#7a7c84"); stone_lo = hexc("#34363c")
    d.rectangle([x - W, y - H, x + W, y], fill=stone + (255,), outline=O + (255,))
    d.rectangle([x - W + 1, y - H + 1, x + W - 1, y - H + 2], fill=stone_hi + (255,))
    for tx in (-W, W - 3 * s // 1):
        tx = int(tx)
        d.rectangle([x + tx, y - H - 4, x + tx + 3, y], fill=stone_lo + (255,), outline=O + (255,))
        for mx in range(0, 4, 2):
            d.rectangle([x + tx + mx, y - H - 6, x + tx + mx, y - H - 4], fill=stone_hi + (255,))
    dw = int(4 * s)
    d.rectangle([x - dw, y - H + 3, x + dw, y], fill=O + (255,))
    d.ellipse([x - dw, y - H + 1, x + dw, y - H + 7], fill=O + (255,))
    glow = hexc(ZONES[zi]["A"][1][3])
    d.rectangle([x - 1, y - int(3 * s), x + 1, y], fill=glow + (255,))
    d.rectangle([x, y - int(5 * s), x, y - int(3 * s)], fill=glow + (255,))
    # skull over the door
    sx, sy = x, y - H + 1
    d.rectangle([sx - 1, sy - 1, sx + 1, sy + 1], fill=hexc("#e8e0cc") + (255,))
    d.point((sx - 1, sy), fill=O + (255,)); d.point((sx + 1, sy), fill=O + (255,))
    if big:
        for ox in (-W - 6, W + 3):
            d.rectangle([x + ox, y - H - 12, x + ox + 3, y + 1], fill=stone_lo + (255,), outline=O + (255,))
            d.polygon([(x + ox - 1, y - H - 12), (x + ox + 4, y - H - 12), (x + ox + 1, y - H - 19)],
                      fill=hexc("#7a1c24") + (255,), outline=O + (255,))
            d.rectangle([x + ox + 1, y - H - 8, x + ox + 2, y - H - 6], fill=hexc("#ff3a2a") + (255,))


def shrine(img, x, y, kind, zi):
    d = ImageDraw.Draw(img)
    stone = hexc("#6a6c72"); hi = hexc("#9a9ca4"); glow = hexc(ZONES[zi]["A"][1][3])
    if kind == "shrine":
        d.polygon([(x, y - 12), (x - 3, y - 2), (x + 3, y - 2)], fill=stone + (255,), outline=O + (255,))
        d.rectangle([x - 5, y - 2, x + 5, y], fill=stone + (255,), outline=O + (255,))
        d.point((x - 1, y - 8), fill=hi + (255,)); d.rectangle([x, y - 7, x, y - 5], fill=glow + (255,))
    elif kind == "ruins":
        for ox, h_ in ((-7, 6), (-2, 9), (3, 5), (7, 7)):
            d.rectangle([x + ox, y - h_, x + ox + 2, y], fill=stone + (255,), outline=O + (255,))
            d.point((x + ox, y - h_ + 1), fill=hi + (255,))
        d.rectangle([x - 8, y - 1, x + 9, y], fill=hexc("#4a4c52") + (255,))
    elif kind == "altar":
        d.rectangle([x - 6, y - 5, x + 6, y], fill=stone + (255,), outline=O + (255,))
        d.rectangle([x - 4, y - 7, x + 4, y - 5], fill=hi + (255,), outline=O + (255,))
        d.rectangle([x - 1, y - 6, x + 1, y - 6], fill=hexc("#c0242c") + (255,))
        d.point((x, y - 9), fill=hexc("#ff5a4a") + (255,))
    else:  # hermit hut
        d.polygon([(x - 7, y - 4), (x, y - 11), (x + 7, y - 4)], fill=hexc("#5a4630") + (255,), outline=O + (255,))
        d.rectangle([x - 5, y - 4, x + 5, y], fill=hexc("#6e5a40") + (255,), outline=O + (255,))
        d.rectangle([x - 1, y - 3, x + 1, y], fill=O + (255,))
        d.point((x + 3, y - 2), fill=hexc("#ffd36a") + (255,))


def lost_cache(img, x, y):
    blit(img, CHEST, {"o": O, "b": hexc("#6a4a2a"), "g": hexc("#e0b040")}, x, y)


def gate_choke(img, x, y, nx, ny, R):
    d = ImageDraw.Draw(img)
    stone = hexc("#6a6c74"); hi = hexc("#9496a0"); lo = hexc("#3a3c44")
    R = int(R)
    blocks = []
    for sgn in (-1, 1):
        for t in range(R + 1, R + 15, 2):
            blocks.append((x + nx * t * sgn, y + ny * t * sgn, 3, 5))
    for (bx, by, w_, h_) in blocks:
        d.rectangle([bx - w_ - 1, by - h_ - 1, bx + w_ + 1, by + 2], fill=O + (255,))
    for (bx, by, w_, h_) in blocks:
        d.rectangle([bx - w_, by - h_, bx + w_, by + 1], fill=stone + (255,))
        d.line([(bx - w_, by - h_), (bx + w_, by - h_)], fill=hi + (255,))
    for sgn in (-1, 1):
        tx_, ty_ = x + nx * (R + 2) * sgn, y + ny * (R + 2) * sgn
        d.rectangle([tx_ - 6, ty_ - 11, tx_ + 6, ty_ + 4], fill=O + (255,))
        d.rectangle([tx_ - 5, ty_ - 10, tx_ + 5, ty_ + 3], fill=lo + (255,))
        d.rectangle([tx_ - 5, ty_ - 10, tx_ + 5, ty_ - 8], fill=hi + (255,))
        for mx in (-5, -1, 3):
            d.rectangle([tx_ + mx, ty_ - 13, tx_ + mx + 2, ty_ - 10], fill=stone + (255,), outline=O + (255,))
        d.rectangle([tx_ - 1, ty_ - 6, tx_ + 1, ty_ - 3], fill=O + (255,))
    # lintel / banner across the gap
    ax, ay = x - nx * R, y - ny * R
    bx_, by_ = x + nx * R, y + ny * R
    d.line([(ax, ay - 9), (bx_, by_ - 9)], fill=O + (255,), width=3)
    d.line([(ax, ay - 9), (bx_, by_ - 9)], fill=hexc("#8a2a2a") + (255,), width=1)


def enemy_camp(img, x, y, zi):
    tent(img, x - 7, y - 1, "#6a2a26")
    tent(img, x + 7, y - 4, "#5a2a22")
    skullpole(img, x + 1, y - 6)
    campfire(img, x, y + 4)
    d = ImageDraw.Draw(img)
    for k in range(7):
        a = math.pi * (0.1 + 0.8 * k / 6)
        sx = int(x + math.cos(a) * 14); sy = int(y + 5 + math.sin(a) * 8)
        d.rectangle([sx, sy - 2, sx, sy], fill=hexc("#4a3524") + (255,))
        d.point((sx, sy - 3), fill=hexc("#b8b0a0") + (255,))


def start_camp(img, cx_, cy_):
    for (dx, dy, c) in ((-26, -20, "#a89a78"), (-6, -34, "#9a8c6c"), (22, -24, "#a89a78"),
                        (-30, 8, "#8e8264"), (26, 10, "#9a8c6c")):
        tent(img, cx_ + dx, cy_ + dy, c)
    campfire(img, cx_, cy_ - 6)
    blit(img, CHEST, {"o": O, "b": hexc("#6a4a2a"), "g": hexc("#b89a5a")}, cx_ + 12, cy_ + 2)
    blit(img, CHEST, {"o": O, "b": hexc("#6a4a2a"), "g": hexc("#b89a5a")}, cx_ + 20, cy_ + 4)
    d = ImageDraw.Draw(img)
    d.rectangle([cx_ - 2, cy_ - 30, cx_ - 2, cy_ - 22], fill=O + (255,))
    d.rectangle([cx_ - 1, cy_ - 30, cx_ + 3, cy_ - 26], fill=hexc("#c8a030") + (255,), outline=O + (255,))


# ---------------------------------------------------------------- compute marker list
markers = []


def add_marker(kind, x, y, zone_i, name, **kw):
    m = dict(kind=kind, x=int(round(x)), y=int(round(y)), zone=zone_i, name=name)
    m.update(kw)
    markers.append(m)


# start camp
camp_c = (51, 1936)
add_marker("start_camp", camp_c[0], camp_c[1], 0, "Starting Camp", checkpoint=True)
# checkpoints: two per zone along the route (just past the entry gate + mid zone)
cp_i = 1
for zi in range(NZ):
    z0 = 0 if zi == 0 else gate_s[zi - 1]
    z1 = gate_s[zi] if zi < NZ - 1 else L - 1
    cand = [z0 + 120, (z0 + z1) // 2 + 40] if zi else [z0 + 280, (z0 + z1) // 2 + 40]
    for ci in cand:
        ci = min(ci, L - 60)
        side = 1 if cp_i % 2 else -1
        p = main_xy[ci] + norm[ci] * side * (Rc[ci] * 0.55 + 4)
        add_marker("checkpoint", p[0], p[1], zi, f"{ZONES[zi]['name']} Checkpoint {cand.index(ci) + 1}")
        cp_i += 1
# gates
for gi, g_ in enumerate(gate_s):
    add_marker("gate", main_xy[g_][0], main_xy[g_][1], gi, GATE_NAMES[gi], leads_to=gi + 1,
               nx=float(norm[g_][0]), ny=float(norm[g_][1]))
# branch sites
site_count = {}
for b in branches:
    t = b["type"]; zi = b["zone"]
    x, y = b["end"]
    site_count[(zi, t)] = site_count.get((zi, t), 0) + 1
    k = site_count[(zi, t)]
    zname = ZONES[zi]["dungeon"]
    if t == "dungeon":
        add_marker("dungeon", x, y, zi, f"{zname} (Boss Dungeon)", map_id=ZONES[zi]["id"], boss=True)
    elif t == "cave":
        add_marker("cave", x, y, zi, f"{zname} Cave {k}", map_id=ZONES[zi]["id"])
    elif t == "camp":
        add_marker("camp", x, y, zi, f"{ZONES[zi]['name']} Enemy Camp {k}")
    elif t == "special":
        kind = SPECIAL_KINDS[int(rng.integers(0, len(SPECIAL_KINDS)))]
        add_marker("special", x, y, zi, f"{ZONES[zi]['name']} {kind.title()}", subtype=kind)
    else:
        add_marker("cache", x, y, zi, f"{ZONES[zi]['name']} Lost Cache {k}")
for a in arenas:
    add_marker("arena", a["x"], a["y"], a["zone"], f"{ZONES[a['zone']]['name']} Hunting Ground", radius=a["r"])
add_marker("final_dungeon", FINAL[0], FINAL[1], NZ - 1, "The Last Vault (Final Boss)", map_id="crystal_vault", boss=True)

# ---------------------------------------------------------------- props (trees, rocks, ...)
props = new_layer()
pd = ImageDraw.Draw(props)
avoid = np.zeros((N, N), bool)
for m in markers:
    r_ = 22 if m["kind"] in ("dungeon", "final_dungeon") else 14
    if m["kind"] == "start_camp":
        continue
    x0, x1 = max(0, m["x"] - r_), min(N, m["x"] + r_)
    y0, y1 = max(0, m["y"] - r_), min(N, m["y"] + r_)
    avoid[y0:y1, x0:x1] = True
avoid |= ndi.binary_dilation(road | trail, iterations=2)
avoid |= camp_mask
for g_ in gate_s:
    x0, x1 = int(main_xy[g_][0]) - 18, int(main_xy[g_][0]) + 18
    y0, y1 = int(main_xy[g_][1]) - 18, int(main_xy[g_][1]) + 18
    avoid[max(0, y0):y1, max(0, x0):x1] = True
cand_mask = walk & ~avoid & (de == 0)
ys_, xs_ = np.where(cand_mask)
order = np.random.default_rng(SEED + 3).permutation(len(ys_))[:110000]
occ = np.zeros((N // 4 + 2, N // 4 + 2), bool)


def c(h_):
    return hexc(h_) + (255,)


def spr_tree(d, x, y, canopy, trunk="#3a2a1c"):
    d.rectangle([x, y - 1, x, y + 1], fill=c(trunk))
    d.ellipse([x - 3, y - 6, x + 3, y - 1], fill=c(canopy[0]), outline=c(canopy[0]))
    d.ellipse([x - 2, y - 5, x + 2, y - 2], fill=c(canopy[1]))
    d.point((x - 1, y - 4), fill=c(canopy[2]))


def spr_pine(d, x, y, col, snow=False):
    d.rectangle([x, y, x, y + 1], fill=c("#2a1e14"))
    d.polygon([(x, y - 8), (x - 3, y - 4), (x + 3, y - 4)], fill=c(col[1]), outline=c(col[0]))
    d.polygon([(x, y - 5), (x - 4, y), (x + 4, y)], fill=c(col[1]), outline=c(col[0]))
    d.point((x - 1, y - 5), fill=c(col[2]))
    if snow:
        d.point((x, y - 7), fill=c("#e8f1f7")); d.point((x - 2, y - 1), fill=c("#e8f1f7")); d.point((x + 2, y - 1), fill=c("#e8f1f7"))


def spr_dead(d, x, y, col="#4a4038"):
    d.line([(x, y), (x, y - 6)], fill=c(col)); d.point((x - 1, y - 4), fill=c(col))
    d.point((x - 2, y - 5), fill=c(col)); d.point((x + 1, y - 3), fill=c(col)); d.point((x + 2, y - 4), fill=c(col))


def spr_rock(d, x, y, base, hi):
    d.ellipse([x - 2, y - 2, x + 2, y + 1], fill=c(base), outline=O + (255,))
    d.point((x - 1, y - 1), fill=c(hi))


def spr_shroom(d, x, y, cap, spot):
    d.rectangle([x, y - 2, x, y], fill=c("#d8d0c0"))
    d.pieslice([x - 3, y - 6, x + 3, y], 180, 360, fill=c(cap), outline=O + (255,))
    d.point((x - 1, y - 4), fill=c(spot)); d.point((x + 1, y - 3), fill=c(spot))


def spr_reed(d, x, y):
    for ox in (-1, 0, 1):
        d.line([(x + ox, y), (x + ox, y - 3 - (ox % 2) * 2)], fill=c("#5a7a4a"))
    d.point((x, y - 6), fill=c("#7a5a3a"))


def spr_bones(d, x, y):
    d.line([(x - 2, y), (x + 2, y - 1)], fill=c("#d8d0b8")); d.point((x - 3, y - 1), fill=c("#d8d0b8"))
    d.point((x + 3, y), fill=c("#d8d0b8")); d.point((x, y - 2), fill=c("#b8b098"))


def spr_tomb(d, x, y):
    d.rectangle([x - 1, y - 4, x + 1, y], fill=c("#7a7870"), outline=O + (255,)); d.point((x, y - 3), fill=c("#4a4a46"))


def spr_crystal(d, x, y, cols):
    for ox, h_ in ((-2, 4), (0, 7), (2, 5)):
        d.polygon([(x + ox, y - h_), (x + ox - 1, y), (x + ox + 1, y)], fill=c(cols[1]), outline=c(cols[0]))
    d.point((x, y - 5), fill=c(cols[2]))


def spr_vent(d, x, y, col, glow):
    d.ellipse([x - 2, y - 2, x + 2, y + 1], fill=c(col), outline=O + (255,)); d.point((x, y - 1), fill=c(glow))


def spr_stump(d, x, y, col="#2a2018"):
    d.rectangle([x - 1, y - 2, x + 1, y], fill=c(col), outline=O + (255,))


def spr_bush(d, x, y, col):
    d.ellipse([x - 2, y - 3, x + 2, y], fill=c(col[0])); d.point((x - 1, y - 2), fill=c(col[1]))


def spr_iceshard(d, x, y):
    d.polygon([(x, y - 6), (x - 2, y), (x + 2, y)], fill=c("#a4c8dc"), outline=c("#456680")); d.point((x - 1, y - 3), fill=c("#e8f1f7"))


def place(zi, d, x, y, r):
    z = ZONES[zi]["id"]
    if z == "mossy_hollow":
        if r < 0.45: spr_tree(d, x, y, ("#16261a", "#1f3623", "#3a5a38"))
        elif r < 0.65: spr_bush(d, x, y, ("#2c4a2f", "#4a6a3a"))
        elif r < 0.85: spr_rock(d, x, y, "#4a4e44", "#6a6e62")
        else: spr_stump(d, x, y)
    elif z == "flooded_gallery":
        if r < 0.4: spr_reed(d, x, y)
        elif r < 0.6: spr_dead(d, x, y, "#3a3a30")
        elif r < 0.8: spr_tree(d, x, y, ("#15291f", "#1e3a2b", "#3a5a48"), "#2a2a20")
        else: spr_rock(d, x, y, "#3a4a46", "#5a6a66")
    elif z == "spore_cavern":
        if r < 0.5: spr_shroom(d, x, y, "#6a3d96", "#8fe07a")
        elif r < 0.75: spr_shroom(d, x, y, "#a03a64", "#e8d0e0")
        else: spr_rock(d, x, y, "#403c55", "#58536f")
    elif z == "bone_warren":
        if r < 0.3: spr_bones(d, x, y)
        elif r < 0.55: spr_tomb(d, x, y)
        elif r < 0.8: spr_dead(d, x, y, "#3a3632")
        else: spr_rock(d, x, y, "#6b655a", "#9a927f")
    elif z == "sulfur_pits":
        if r < 0.35: spr_vent(d, x, y, "#7a7030", "#e0d848")
        elif r < 0.65: spr_crystal(d, x, y, ("#5a5220", "#c4bc3e", "#f0e870"))
        elif r < 0.85: spr_dead(d, x, y, "#4a3a20")
        else: spr_rock(d, x, y, "#5a5229", "#7a7035")
    elif z == "ember_depths":
        if r < 0.35: spr_stump(d, x, y, "#1a1412")
        elif r < 0.6: spr_vent(d, x, y, "#2e282a", "#ff7a1c")
        elif r < 0.85: spr_rock(d, x, y, "#2e282a", "#5a4c50")
        else: spr_dead(d, x, y, "#2a2220")
    elif z == "frostbite_grotto":
        if r < 0.5: spr_pine(d, x, y, ("#10211f", "#224239", "#3a6a58"), snow=True)
        elif r < 0.75: spr_iceshard(d, x, y)
        else: spr_rock(d, x, y, "#8a98a6", "#c4d0da")
    else:
        if r < 0.5: spr_crystal(d, x, y, ("#2d2a78", "#4e48c0", "#8f86f0"))
        elif r < 0.7: spr_crystal(d, x, y, ("#1a5a66", "#2ab0c0", "#8ee6f0"))
        else: spr_rock(d, x, y, "#312c52", "#453f6e")


DENS = [0.55, 0.45, 0.5, 0.4, 0.4, 0.35, 0.5, 0.4]
cnt = 0
for k in order:
    x, y = int(xs_[k]), int(ys_[k])
    zi = int(zone[y, x])
    if rnd[y, x] > DENS[zi]:
        continue
    ox, oy = x // 4, y // 4
    if occ[oy - 1:oy + 2, ox - 1:ox + 2].any():
        continue
    occ[oy, ox] = True
    place(zi, pd, x, y, float(r2[y, x]))
    cnt += 1
print("props", cnt, f"{time.time() - _t0:.1f}s")

# ---------------------------------------------------------------- structures
struct = new_layer()
for m in markers:
    k = m["kind"]; x, y = m["x"], m["y"]; zi = m["zone"]
    if k == "start_camp":
        start_camp(struct, x, y)
    elif k == "checkpoint":
        checkpoint(struct, x, y)
    elif k == "gate":
        gate_choke(struct, x, y, m["nx"], m["ny"], 6)
    elif k == "cave":
        cave_entrance(struct, x, y, zi)
    elif k == "dungeon":
        dungeon_gate(struct, x, y + 4, zi)
    elif k == "final_dungeon":
        dungeon_gate(struct, x, y + 8, zi, big=True)
    elif k == "camp":
        enemy_camp(struct, x, y, zi)
    elif k == "special":
        shrine(struct, x, y + 4, m["subtype"], zi)
    elif k == "cache":
        lost_cache(struct, x, y)
    elif k == "arena":
        d = ImageDraw.Draw(struct)
        for a_ in range(6):
            ang = a_ * math.pi / 3 + 0.4
            sx = int(x + math.cos(ang) * 9); sy = int(y + math.sin(ang) * 7)
            d.rectangle([sx, sy - 3, sx, sy], fill=c("#4a3524"))
            d.point((sx, sy - 4), fill=c("#c04a3a"))

# ---------------------------------------------------------------- markers (map pins) + labels
PIN_COL = dict(start_camp="#f0c840", checkpoint="#34c0e8", camp="#d8362c", cave="#e8862a",
               dungeon="#a040d8", final_dungeon="#e82a6a", special="#e8d040", gate="#e8e8f0",
               cache="#58c858", arena="#c06a3a")
GLYPH = dict(
    checkpoint=["..#..", ".###.", "#####", ".###.", "..#.."],
    start_camp=["..#..", ".###.", "#####", "#...#", "#####"],
    camp=["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    cave=[".###.", "#...#", "#...#", "#...#", "#####"],
    dungeon=[".###.", "#.#.#", "#####", ".###.", ".#.#."],
    final_dungeon=["#.#.#", "#####", ".###.", ".###.", ".#.#."],
    special=["..#..", ".###.", "#####", ".###.", "..#.."],
    gate=["#...#", "#.#.#", "#.#.#", "#.#.#", "#####"],
    cache=[".....", ".###.", "#####", "#.#.#", "#####"],
    arena=["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
)
markers_img = new_layer()
md = ImageDraw.Draw(markers_img)
STRUCT_H = dict(start_camp=26, checkpoint=9, camp=10, cave=11, dungeon=19, final_dungeon=34, special=13,
                gate=19, cache=6, arena=5)


def pin(d, x, y, kind, big=False):
    col = hexc(PIN_COL[kind]); s = 1.4 if big else 1.0
    rad = int(5 * s)
    d.polygon([(x - rad + 1, y - rad * 2 + 2), (x + rad - 1, y - rad * 2 + 2), (x, y)], fill=col + (255,), outline=O + (255,))
    d.ellipse([x - rad, y - rad * 3, x + rad, y - rad + 1], fill=col + (255,), outline=O + (255,))
    g_ = GLYPH[kind]
    gx0 = x - 2; gy0 = int(y - rad * 2 - 2)
    for j, row in enumerate(g_):
        for i, chh in enumerate(row):
            if chh == "#":
                d.point((gx0 + i, gy0 + j - (1 if big else 0)), fill=(14, 10, 12, 255))


for m in markers:
    if m["kind"] in ("gate",):
        pass
    top = STRUCT_H.get(m["kind"], 8)
    big = m["kind"] in ("dungeon", "final_dungeon", "start_camp")
    if m["kind"] == "arena":
        continue
    pin(md, m["x"], m["y"] - top - 1, m["kind"], big)

# labels
try:
    F_ZONE = ImageFont.truetype("/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf", 34)
    F_SM = ImageFont.truetype("/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf", 17)
    F_LG = ImageFont.truetype("/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf", 22)
except Exception:
    F_ZONE = F_SM = F_LG = ImageFont.load_default()
labels = new_layer()
ld = ImageDraw.Draw(labels)
ld.fontmode = "1"


def text_outlined(d, xy, txt, font, fill, anchor="mm"):
    x, y = xy
    for dx in (-2, -1, 0, 1, 2):
        for dy in (-2, -1, 0, 1, 2):
            if dx or dy:
                d.text((x + dx, y + dy), txt, font=font, fill=(10, 6, 6, 255), anchor=anchor)
    d.text((x, y), txt, font=font, fill=fill, anchor=anchor)


# zone titles: sit in the blocked band beside the middle of each zone's stretch of road
walk_dil = ndi.binary_dilation(walk, iterations=10)
label_boxes = []
for m in markers:
    if m["kind"] in ("dungeon", "final_dungeon", "gate"):
        nm = m["name"].split(" (")[0]
        w_ = ld.textlength(nm, font=F_SM)
        yy_ = m["y"] - STRUCT_H[m["kind"]] - 26 if m["kind"] != "gate" else m["y"] - 52
        label_boxes.append((int(m["x"] - w_ / 2 - 6), int(yy_ - 14), int(m["x"] + w_ / 2 + 6), int(yy_ + 14)))
for zi, z in enumerate(ZONES):
    z0 = 0 if zi == 0 else gate_s[zi - 1]
    z1 = gate_s[zi] if zi < NZ - 1 else L - 1
    tw = ld.textlength(z["name"], font=F_ZONE)
    placed_ = False
    for ds in (0, 60, -60, 120, -120, 180, -180, 240, -240):
        i = (z0 + z1) // 2 + ds
        for off in (110, -110, 150, -150, 190, -190, 240, -240, 300, -300):
            cxl = main_xy[i][0] + norm[i][0] * off
            cyl = main_xy[i][1] + norm[i][1] * off
            x0, x1 = int(cxl - tw / 2 - 8), int(cxl + tw / 2 + 8)
            y0, y1 = int(cyl - 24), int(cyl + 42)
            if x0 < 8 or x1 > N - 8 or y0 < 8 or y1 > N - 8:
                continue
            if walk_dil[y0:y1, x0:x1].any():
                continue
            if any(not (x1 < a or x0 > c_ or y1 < b_ or y0 > d_) for a, b_, c_, d_ in label_boxes):
                continue
            label_boxes.append((x0, y0, x1, y1))
            zc = hexc(z["A"][1][3] if z["A"][0] != "canopy" else z["B"][1][3])
            col = tuple(min(255, int(v * 0.35 + 190)) for v in hexc(z["ground"][3]))
            text_outlined(ld, (int(cxl), int(cyl)), z["name"].upper(), F_ZONE, col + (255,))
            ld.text((int(cxl), int(cyl) + 26), f"ZONE {zi + 1}  ·  {z['dungeon'].upper()}", font=F_SM,
                    fill=(200, 190, 170, 255), anchor="mm")
            z["label"] = dict(x=int(cxl), y=int(cyl))
            placed_ = True
            break
        if placed_:
            break
    if not placed_:
        zy, zx = np.where((zone == zi) & ~walk_dil)
        mid = main_xy[(z0 + z1) // 2]
        order_ = np.argsort(np.hypot(zx - mid[0], zy - mid[1]))[::37]
        for k_ in order_:
            cxl, cyl = int(zx[k_]), int(zy[k_])
            x0, x1 = int(cxl - tw / 2 - 8), int(cxl + tw / 2 + 8)
            y0, y1 = int(cyl - 24), int(cyl + 42)
            if x0 < 8 or x1 > N - 8 or y0 < 8 or y1 > N - 8 or walk_dil[y0:y1, x0:x1].any():
                continue
            if any(not (x1 < a or x0 > c_ or y1 < b_ or y0 > d_) for a, b_, c_, d_ in label_boxes):
                continue
            label_boxes.append((x0, y0, x1, y1))
            col = tuple(min(255, int(v * 0.35 + 190)) for v in hexc(z["ground"][3]))
            text_outlined(ld, (cxl, cyl), z["name"].upper(), F_ZONE, col + (255,))
            ld.text((cxl, cyl + 26), f"ZONE {zi + 1}  ·  {z['dungeon'].upper()}", font=F_SM, fill=(200, 190, 170, 255), anchor="mm")
            placed_ = True
            break
    if not placed_:
        print("WARN: no clear spot for label", z["name"])

# dungeon names beside each dungeon pin
for m in markers:
    if m["kind"] in ("dungeon", "final_dungeon"):
        top = STRUCT_H[m["kind"]]
        nm = m["name"].split(" (")[0]
        text_outlined(ld, (m["x"], m["y"] - top - 26), nm, F_SM, (230, 200, 230, 255))
    if m["kind"] == "gate":
        text_outlined(ld, (m["x"], m["y"] - 52), m["name"], F_SM, (225, 225, 235, 255))
text_outlined(ld, (64, 1860), "CAMP", F_SM, (255, 232, 140, 255))

# legend in the emptiest blocked rectangle
LW, LH = 330, 238
free = ~ndi.binary_dilation(walk, iterations=14)
for (a, b_, c_, d_) in label_boxes:
    free[b_ - 10:d_ + 10, a - 10:c_ + 10] = False
integral = free.astype(np.int32).cumsum(0).cumsum(1)
best = None
for y0 in range(1480 if False else 40, N - LH - 40, 20):
    for x0 in range(40, N - LW - 40, 20):
        s_ = integral[y0 + LH - 1, x0 + LW - 1] - integral[y0 - 1, x0 + LW - 1] - integral[y0 + LH - 1, x0 - 1] + integral[y0 - 1, x0 - 1]
        if s_ == LW * LH:
            best = (x0, y0)
            break
    if best:
        break
legend_pos = best or (900, 1500)
lx, ly = legend_pos
ld.rectangle([lx, ly, lx + LW, ly + LH], fill=(18, 14, 14, 235), outline=(120, 40, 44, 255), width=3)
ld.rectangle([lx + 5, ly + 5, lx + LW - 5, ly + LH - 5], outline=(70, 56, 52, 255), width=1)
ld.text((lx + LW // 2, ly + 22), "LEGEND", font=F_LG, fill=(176, 28, 32, 255), anchor="mm")
leg = [("start_camp", "Starting camp"), ("checkpoint", "Checkpoint"), ("camp", "Enemy camp"),
       ("cave", "Cave entrance"), ("dungeon", "Dungeon (boss)"), ("special", "Shrine / ruin / altar"),
       ("gate", "Zone gate (choke point)"), ("cache", "Lost cache")]
for i, (k_, t_) in enumerate(leg):
    col_i, row_i = divmod(i, 4)
    px_ = lx + 28 + col_i * 160
    py_ = ly + 78 + row_i * 40
    pin(ImageDraw.Draw(labels), px_, py_, k_)
    ld.text((px_ + 14, py_ - 10), t_ if col_i == 0 else t_, font=F_SM, fill=(214, 204, 184, 255), anchor="lm")
ld.text((lx + LW // 2, ly + LH - 22), "1 pixel = 1 tile (16 px)", font=F_SM, fill=(140, 130, 116, 255), anchor="mm")

# ---------------------------------------------------------------- grid layer (hidden helper)
grid = new_layer()
gd = ImageDraw.Draw(grid)
for v in range(0, N, 250):
    gd.line([(v, 0), (v, N)], fill=(255, 255, 255, 40))
    gd.line([(0, v), (N, v)], fill=(255, 255, 255, 40))
    gd.text((v + 3, 3), str(v), fill=(255, 255, 255, 140))
    gd.text((3, v + 3), str(v), fill=(255, 255, 255, 140))

# ---------------------------------------------------------------- write layers
def save_arr(arr, name, mode="RGB"):
    Image.fromarray(arr, mode).save(os.path.join(LAY, name))


save_arr(ground_img, "01_ground.png")
Image.fromarray(blk_img, "RGBA").save(os.path.join(LAY, "02_blockers.png"))
Image.fromarray(shadow_img, "RGBA").save(os.path.join(LAY, "03_shadows.png"))
Image.fromarray(road_img, "RGBA").save(os.path.join(LAY, "04_paths.png"))
props.save(os.path.join(LAY, "05_props.png"))
struct.save(os.path.join(LAY, "06_structures.png"))
markers_img.save(os.path.join(LAY, "07_markers.png"))
labels.save(os.path.join(LAY, "08_labels.png"))
grid.save(os.path.join(LAY, "09_grid.png"))
Image.fromarray((walk * 255).astype(np.uint8), "L").save(os.path.join(LAY, "10_collision.png"))

flat = Image.fromarray(ground_img, "RGB").convert("RGBA")
for im in (Image.fromarray(blk_img, "RGBA"), Image.fromarray(shadow_img, "RGBA"), Image.fromarray(road_img, "RGBA"),
           props, struct, markers_img, labels):
    flat = Image.alpha_composite(flat, im)
flat.convert("RGB").save(os.path.join(OUT, f"map-{VER}.png"))
Image.fromarray((walk * 255).astype(np.uint8), "L").save(os.path.join(OUT, f"collision_{VER}.png"))
Image.fromarray((zone * 30).astype(np.uint8), "L").save(os.path.join(OUT, f"zones_{VER}.png"))

# ---------------------------------------------------------------- JSON for Godot
def wp(v):
    return int(v * TILE + TILE // 2)


data = dict(
    map_size_tiles=[N, N], tile_px=TILE, world_size_px=[N * TILE, N * TILE],
    note="1 map pixel = 1 tile. world_px = tile * 16 + 8 (tile centre). Zones are listed in progression order.",
    path_length_tiles=int(L),
    zones=[dict(index=i, id=z["id"], name=z["name"], dungeon=z["dungeon"],
                route_start_tile=0 if i == 0 else int(gate_s[i - 1]),
                route_end_tile=int(gate_s[i]) if i < NZ - 1 else int(L)) for i, z in enumerate(ZONES)],
    main_path=[[int(round(p[0])), int(round(p[1]))] for p in main_xy[::8]],
    markers=[dict(m, world_x=wp(m["x"]), world_y=wp(m["y"])) for m in markers],
)
json.dump(data, open(os.path.join(OUT, f"map_data_{VER}.json"), "w"), indent=1)
from collections import Counter
print("markers", dict(Counter(m["kind"] for m in markers)))
print("per zone dungeons/caves/camps:", {ZONES[z]["id"]: dict(Counter(m["kind"] for m in markers if m["zone"] == z and m["kind"] in ("dungeon", "cave", "camp", "special", "checkpoint"))) for z in range(NZ)})
print("legend at", legend_pos, f"done {time.time() - _t0:.1f}s")

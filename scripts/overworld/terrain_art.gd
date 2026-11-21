class_name TerrainArt
extends RefCounted
## The pixel art of the first zone's generated tileset (spec 1.6 section 4): 16 x 16 tiles drawn at runtime from a seeded
## RandomNumberGenerator into one Image, so the same seed always gives the same atlas. Hard pixel edges, a handful of
## colours, no anti-aliasing. The palette is the world map's own: sampled from the guide's layers (01_ground.png for the
## grass, 04_paths.png for the dirt, 02_blockers.png for the canopy and the rock) around the start camp.
##
## Atlas layout (8 columns, 7 rows; the zone catalog `content/overworld/terrain/mossy_hollow.tres` names these cells):
##   row 0  grass 0..7          row 1  dirt path 0..5
##   row 2  forest 0..3, deep   row 3  rock 0..3, deep (deep is column 4)
##   row 4  edge (0), shadow (1)  row 5, 6  dirt path rims: cell index = mask of the sides touching grass (1 north,
##   2 east, 4 south, 8 west), so mask m is at column m % 8 of row 5 + m / 8 (mask 0 is a plain path tile again)

const TILE := 16
const COLUMNS := 8
const ROWS := 7

# 01_ground.png: the grass clearing (base, light speckle, blade/highlight, dark speckle) and its flower pixels.
const GRASS := Color8(47, 63, 37)
const GRASS_LIGHT := Color8(56, 74, 44)
const GRASS_HI := Color8(68, 90, 51)
const GRASS_DARK := Color8(39, 52, 31)
const FLOWER_YELLOW := Color8(140, 138, 74)
const FLOWER_RED := Color8(122, 58, 58)
# 04_paths.png: the dirt path, dark to light.
const DIRT_DARK := Color8(57, 46, 31)
const DIRT_EDGE := Color8(66, 53, 36)
const DIRT_SHADE := Color8(74, 59, 41)
const DIRT := Color8(81, 64, 45)
const DIRT_LIGHT := Color8(90, 72, 51)
const DIRT_HI := Color8(107, 87, 61)
const PEBBLE := Color8(125, 104, 73)
# 02_blockers.png: the forest canopy (darkest to lightest) and the rock (dark to light).
const FOREST_DEEP := Color8(8, 14, 8)
const FOREST_0 := Color8(14, 25, 15)
const FOREST_1 := Color8(21, 37, 25)
const FOREST_2 := Color8(30, 53, 34)
const FOREST_3 := Color8(43, 73, 46)
const ROCK_0 := Color8(24, 27, 23)
const ROCK_1 := Color8(30, 33, 28)
const ROCK_2 := Color8(45, 49, 42)
const ROCK_3 := Color8(62, 67, 58)

const GRASS_VARIANTS := 8
const PATH_VARIANTS := 6
const FOREST_VARIANTS := 4
const ROCK_VARIANTS := 4


## The whole atlas as an Image (RGBA8, 128 x 112) for a seed.
static func build_atlas(seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create(TILE * COLUMNS, TILE * ROWS, false, Image.FORMAT_RGBA8)
	for v in GRASS_VARIANTS:
		_blit(img, _grass(rng, v), Vector2i(v, 0))
	for v in PATH_VARIANTS:
		_blit(img, _path(rng, v), Vector2i(v, 1))
	for v in FOREST_VARIANTS:
		_blit(img, _canopy(rng, [FOREST_0, FOREST_1, FOREST_2, FOREST_3], 7 + v % 2), Vector2i(v, 2))
	_blit(img, _canopy(rng, [FOREST_DEEP, FOREST_DEEP, FOREST_0, FOREST_0], 6), Vector2i(4, 2))
	for v in ROCK_VARIANTS:
		_blit(img, _rock(rng, [ROCK_1, ROCK_2, ROCK_3, ROCK_3], v), Vector2i(v, 3))
	_blit(img, _rock(rng, [ROCK_0, ROCK_1, ROCK_1, ROCK_2], 1), Vector2i(4, 3))
	_blit(img, _edge(rng), Vector2i(0, 4))
	_blit(img, _shadow(), Vector2i(1, 4))
	for m in 16:
		_blit(img, _path_rim(rng, m), Vector2i(m % 8, 5 + m / 8))
	return img


static func _blit(atlas: Image, tile: Image, cell: Vector2i) -> void:
	atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), cell * TILE)


static func _tile() -> Image:
	return Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)


static func _put(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, TILE), posmod(y, TILE), c)


static func _grass(rng: RandomNumberGenerator, variant: int) -> Image:
	var img := _tile()
	img.fill(GRASS)
	# speckles: light and dark pixels, a few more of them in the later variants
	for i in 14 + variant:
		_put(img, rng.randi() % TILE, rng.randi() % TILE, GRASS_LIGHT)
	for i in 10:
		_put(img, rng.randi() % TILE, rng.randi() % TILE, GRASS_DARK)
	# blades: a two-pixel vertical tuft, a light tip over a darker stem
	for i in 2 + variant % 3:
		var x := rng.randi() % TILE
		var y := rng.randi() % (TILE - 1)
		_put(img, x, y, GRASS_HI)
		_put(img, x, y + 1, GRASS_LIGHT)
	# a flower on some variants (the map's yellow and red specks)
	if variant % 3 == 1:
		_put(img, rng.randi() % TILE, rng.randi() % TILE, FLOWER_YELLOW)
	elif variant == 5:
		_put(img, rng.randi() % TILE, rng.randi() % TILE, FLOWER_RED)
	return img


static func _path(rng: RandomNumberGenerator, variant: int) -> Image:
	var img := _tile()
	img.fill(DIRT)
	for i in 22:
		_put(img, rng.randi() % TILE, rng.randi() % TILE, DIRT_SHADE if i % 2 == 0 else DIRT_LIGHT)
	for i in 6:
		_put(img, rng.randi() % TILE, rng.randi() % TILE, DIRT_EDGE)
	# worn ruts: a short horizontal dark scratch and a light one
	var ry := rng.randi() % TILE
	var rx := rng.randi() % TILE
	for k in 3 + variant % 3:
		_put(img, rx + k, ry, DIRT_EDGE)
	# pebbles: a light pixel over a dark one
	for i in 1 + variant % 3:
		var px := rng.randi() % (TILE - 1)
		var py := rng.randi() % (TILE - 1)
		_put(img, px, py, PEBBLE)
		_put(img, px + 1, py + 1, DIRT_DARK)
	# soft border: a few pixels of the tile's rim fall back to grass, so a path does not read as a ruled strip
	for i in 5:
		var side := rng.randi() % 4
		var t := rng.randi() % TILE
		var c: Color = GRASS if i % 2 == 0 else GRASS_DARK
		match side:
			0:
				_put(img, t, 0, c)
			1:
				_put(img, t, TILE - 1, c)
			2:
				_put(img, 0, t, c)
			3:
				_put(img, TILE - 1, t, c)
	return img


## A path tile whose sides in `mask` fray into grass: along each such side the outer pixels turn to grass with a chance that
## falls off over three pixels, and the corners where two such sides meet are cut deeper.
static func _path_rim(rng: RandomNumberGenerator, mask: int) -> Image:
	var img := _path(rng, mask)
	for x in TILE:
		for y in TILE:
			var depth := 99
			if mask & 1:
				depth = mini(depth, y)
			if mask & 2:
				depth = mini(depth, TILE - 1 - x)
			if mask & 4:
				depth = mini(depth, TILE - 1 - y)
			if mask & 8:
				depth = mini(depth, x)
			if depth > 3:
				continue
			var chance: float = [0.9, 0.55, 0.25, 0.08][depth]
			if rng.randf() < chance:
				var r := rng.randf()
				img.set_pixel(x, y, GRASS_DARK if r < 0.2 else (GRASS_LIGHT if r < 0.35 else GRASS))
	return img


## Dense dark blobs that wrap at the tile's borders (so the tile repeats without a seam): each blob is a disc of a mid
## tone with a lighter top-left and a darker bottom-right rim. `tones` is darkest to lightest.
static func _canopy(rng: RandomNumberGenerator, tones: Array, blobs: int) -> Image:
	var img := _tile()
	img.fill(tones[0])
	for b in blobs:
		var cx := rng.randi() % TILE
		var cy := rng.randi() % TILE
		var r := 3 + rng.randi() % 3
		var base: int = 1 + rng.randi() % 2
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d2 := dx * dx + dy * dy
				if d2 > r * r:
					continue
				var tone := base
				if d2 > (r - 1) * (r - 1) and dx + dy > 0:
					tone = 0 # shadowed rim, bottom-right
				elif dx + dy < -r * 0.6 and d2 < r * r * 0.7:
					tone = mini(base + 1, 3) # lit top-left
				_put(img, cx + dx, cy + dy, tones[tone])
	return img


## Angular grey patches with hairline cracks. `tones` is darkest to lightest.
static func _rock(rng: RandomNumberGenerator, tones: Array, variant: int) -> Image:
	var img := _tile()
	img.fill(tones[1])
	for b in 5:
		var cx := rng.randi() % TILE
		var cy := rng.randi() % TILE
		var w := 3 + rng.randi() % 4
		var h := 2 + rng.randi() % 3
		var tone := 1 + rng.randi() % 3
		for dy in h:
			for dx in w - dy / 2:
				_put(img, cx + dx, cy + dy, tones[tone])
		# a lit top edge and a dark bottom edge, like a chipped slab
		for dx in w:
			_put(img, cx + dx, cy - 1, tones[mini(tone + 1, 3)])
			_put(img, cx + dx, cy + h, tones[0])
	# cracks: a short diagonal run of the darkest tone
	var x := rng.randi() % TILE
	var y := rng.randi() % TILE
	for k in 3 + variant:
		_put(img, x + k, y + k / 2, tones[0])
	return img


## A sparse lighter speckle (a lit rim) laid over a blocked tile that touches walkable ground.
static func _edge(rng: RandomNumberGenerator) -> Image:
	var img := _tile()
	for i in 22:
		var x := rng.randi() % TILE
		var y := rng.randi() % TILE
		img.set_pixel(x, y, Color(0.62, 0.72, 0.55, 0.30))
	return img


## A dithered shade for walkable tiles right of or below a blocked tile: every other pixel, so grass still reads through.
static func _shadow() -> Image:
	var img := _tile()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, Color(0, 0, 0, 0.28 if (x + y) % 2 == 0 else 0.08))
	return img

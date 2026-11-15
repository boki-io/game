extends TileMapLayer
## Placeholder checkerboard ground built at runtime until a real tileset exists.

const TILE := 16
const DIRT_SEED := 4242

enum Look { GRASS, DIRT }

@export var look := Look.GRASS
## DIRT only: floor that gets the lighter, worn-path tiles (the walk from the door to the pedestals).
@export var path_rects: Array[Rect2] = []


func _ready() -> void:
	z_index = -10
	if look == Look.DIRT:
		_build_dirt()
		return
	var img := Image.create(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE, TILE), Color("3b5d3a"))
	img.fill_rect(Rect2i(TILE, 0, TILE, TILE), Color("456b43"))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(source, 0)
	tile_set = ts
	for x in Arena.world_size.x / TILE:
		for y in Arena.world_size.y / TILE:
			set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))


## Dirt floor: plain tiles in a few shades, with seeded speckles; some pebbled and cracked ones, darker patches
## from noise and lighter worn paths. Seeded, so the floor is the same on every launch.
const DIRT_PLAIN := [Color("5b4632"), Color("604a35"), Color("574330"), Color("5e4934")]
const DIRT_DARK := Color("4a3828")
const DIRT_LIGHT := Color("6d5640")
const VARIANT_DARK := 4
const VARIANT_LIGHT := 5
const VARIANT_PEBBLED := 6
const VARIANT_CRACKED := 7


func _build_dirt() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DIRT_SEED
	var img := Image.create(TILE * 8, TILE, false, Image.FORMAT_RGBA8)
	for v in 8:
		var base: Color = DIRT_PLAIN[v % 4]
		if v == VARIANT_DARK:
			base = DIRT_DARK
		elif v == VARIANT_LIGHT:
			base = DIRT_LIGHT
		img.fill_rect(Rect2i(v * TILE, 0, TILE, TILE), base)
		for i in 7:  # speckles
			var c := base.darkened(0.18) if rng.randf() < 0.6 else base.lightened(0.12)
			img.set_pixel(v * TILE + rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), c)
		if v == VARIANT_PEBBLED:
			for i in 3:
				var p := Vector2i(v * TILE + rng.randi_range(1, TILE - 4), rng.randi_range(1, TILE - 4))
				img.fill_rect(Rect2i(p, Vector2i(2, 2)), Color("7a7268"))
				img.set_pixel(p.x, p.y + 2, Color("3a342e"))
		elif v == VARIANT_CRACKED:
			var p := Vector2i(v * TILE + 2, 3)
			for i in 11:
				img.set_pixel(p.x + i, clampi(p.y + i / 2 + rng.randi_range(-1, 1), 0, TILE - 1), Color("33261b"))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE, TILE)
	for v in 8:
		source.create_tile(Vector2i(v, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(source, 0)
	tile_set = ts

	var noise := FastNoiseLite.new()
	noise.seed = DIRT_SEED
	noise.frequency = 0.06
	for x in Arena.world_size.x / TILE:
		for y in Arena.world_size.y / TILE:
			var cell := Vector2i(x, y)
			var centre := Vector2(x + 0.5, y + 0.5) * TILE
			var roll := rng.randf()
			var variant := rng.randi_range(0, 3)
			if _on_path(centre) and roll < 0.55:
				variant = VARIANT_LIGHT
			elif noise.get_noise_2d(x, y) > 0.2 and roll < 0.7:
				variant = VARIANT_DARK
			elif roll > 0.95:
				variant = VARIANT_CRACKED
			elif roll > 0.88:
				variant = VARIANT_PEBBLED
			set_cell(cell, 0, Vector2i(variant, 0))


func _on_path(pos: Vector2) -> bool:
	for r in path_rects:
		if r.has_point(pos):
			return true
	return false

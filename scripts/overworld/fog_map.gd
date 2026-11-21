class_name FogMap
extends RefCounted
## The fog of war (spec 1.6): a 250 x 250 grid of revealed bytes over the world, one cell per 8 x 8 tiles (Journey.FOG_BYTES
## bytes). It wraps the journey's own `fog` array and writes into it, so the journey saves what was revealed. `reveal` marks
## the cells whose centre lies within a radius of a world position. `texture()` is the fog as a 250 x 250 image (opaque black
## where unrevealed, transparent where revealed) for the minimap and the world map; it is rebuilt only after a reveal changed
## something.

const CELLS := 250
const BYTES := CELLS * CELLS

var _bytes := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _dirty := true
## How many times the texture has been rebuilt (the tests check it only moves when a reveal changed something).
var rebuild_count := 0


## Wraps `bytes` (a journey's `fog`). A wrong-sized array is resized and zeroed in place.
func _init(bytes := PackedByteArray()) -> void:
	_bytes = bytes
	if _bytes.size() != BYTES:
		_bytes.resize(BYTES)
		_bytes.fill(0)


func bytes() -> PackedByteArray:
	return _bytes


static func cell_of_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / OverworldRules.FOG_CELL_TILES), floori(float(tile.y) / OverworldRules.FOG_CELL_TILES))


## Reveals the cells whose centre is within `radius_tiles` of `world_pos`. Returns whether any cell changed.
func reveal(world_pos: Vector2, radius_tiles: float = OverworldRules.FOG_REVEAL_TILES) -> bool:
	var cell_tiles := float(OverworldRules.FOG_CELL_TILES)
	var centre := world_pos / float(WorldData.TILE_PX)  # in tiles
	var c0 := maxi(floori((centre.x - radius_tiles) / cell_tiles), 0)
	var c1 := mini(floori((centre.x + radius_tiles) / cell_tiles), CELLS - 1)
	var r0 := maxi(floori((centre.y - radius_tiles) / cell_tiles), 0)
	var r1 := mini(floori((centre.y + radius_tiles) / cell_tiles), CELLS - 1)
	var limit := radius_tiles * radius_tiles
	var changed := false
	for cy in range(r0, r1 + 1):
		var dy := (cy + 0.5) * cell_tiles - centre.y
		for cx in range(c0, c1 + 1):
			var dx := (cx + 0.5) * cell_tiles - centre.x
			if dx * dx + dy * dy <= limit and _bytes[cy * CELLS + cx] == 0:
				_bytes[cy * CELLS + cx] = 1
				changed = true
	if changed:
		_dirty = true
	return changed


func is_revealed_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < CELLS and cell.y < CELLS and _bytes[cell.y * CELLS + cell.x] != 0


func is_revealed_tile(tile: Vector2i) -> bool:
	return is_revealed_cell(cell_of_tile(tile))


func is_revealed_world(pos: Vector2) -> bool:
	return is_revealed_tile(WorldData.tile_of(pos))


func revealed_count() -> int:
	var n := 0
	for b in _bytes:
		if b != 0:
			n += 1
	return n


## The image behind `texture()` (up to date). Headless runs have a dummy renderer whose texture reads back blank.
func image() -> Image:
	texture()
	return _image


## The fog as a 250 x 250 texture (the same object every time, updated when a reveal changed something).
func texture() -> ImageTexture:
	if _texture == null:
		_image = Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
		_texture = ImageTexture.create_from_image(_image)
	if _dirty:
		var data := PackedByteArray()
		data.resize(BYTES * 4)
		for i in BYTES:
			data[i * 4 + 3] = 0 if _bytes[i] != 0 else 255
		_image.set_data(CELLS, CELLS, false, Image.FORMAT_RGBA8, data)
		_texture.update(_image)
		_dirty = false
		rebuild_count += 1
	return _texture

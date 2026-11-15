extends TileMapLayer
## Placeholder checkerboard ground built at runtime until a real tileset exists.

const TILE := 16


func _ready() -> void:
	z_index = -10
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
	for x in Arena.SIZE.x / TILE:
		for y in Arena.SIZE.y / TILE:
			set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))

class_name ZoneTerrain
extends Resource
## One zone's terrain catalog (spec 1.6): which cells of its tileset sheet (`assets/tilesets/<id>.png`, 16 px tiles) draw
## each terrain role, and a flat fallback colour per role. A role whose cell is (-1, -1) uses the fallback colour (a
## generated one-colour tile), so a sheet without a usable tile still draws. Data lives in `content/overworld/terrain/`.

const TILE := 16
const NO_TILE := Vector2i(-1, -1)
## The roles in the order of the generated fallback strip (the atlas x of a role's fallback tile).
const ROLES: Array[StringName] = [&"ground", &"blocker", &"blocker_deep", &"edge", &"shadow"]

@export var id: StringName
@export var sheet: Texture2D
## The floor cells (a variant is picked per tile by a stable hash).
@export var ground: Array[Vector2i] = []
@export var blocker := NO_TILE
@export var blocker_deep := NO_TILE
## The lit lip on a blocked tile that touches a walkable one (an overlay cell, so usually a translucent tile).
@export var edge := NO_TILE
## The shadow on walkable tiles right of or below a blocked tile (an overlay cell).
@export var shadow := NO_TILE
@export var ground_color := Color(0.2, 0.2, 0.2)
@export var blocker_color := Color(0.1, 0.1, 0.1)
@export var blocker_deep_color := Color(0.06, 0.06, 0.06)
@export var edge_color := Color(1, 1, 1, 0.2)
@export var shadow_color := Color(0, 0, 0, 0.35)


## The atlas cell of a role (the variant picks among `ground`'s list), or NO_TILE when the role uses its fallback colour.
func cell_of(role: StringName, variant: int = 0) -> Vector2i:
	match role:
		&"ground":
			return ground[variant % ground.size()] if not ground.is_empty() else NO_TILE
		&"blocker":
			return blocker
		&"blocker_deep":
			return blocker_deep
		&"edge":
			return edge
		&"shadow":
			return shadow
	return NO_TILE


func color_of(role: StringName) -> Color:
	match role:
		&"ground":
			return ground_color
		&"blocker":
			return blocker_color
		&"blocker_deep":
			return blocker_deep_color
		&"edge":
			return edge_color
		&"shadow":
			return shadow_color
	return Color.MAGENTA


## True when the role draws from the sheet (every ground variant must be a real cell for `ground`).
func uses_sheet(role: StringName) -> bool:
	if role == &"ground":
		if ground.is_empty():
			return false
		for c in ground:
			if c == NO_TILE:
				return false
		return true
	return cell_of(role) != NO_TILE


## The roles that fall back to a flat colour (the build notes list them).
func gaps() -> Array[StringName]:
	var out: Array[StringName] = []
	for r in ROLES:
		if not uses_sheet(r):
			out.append(r)
	return out


## A TileSet of this zone alone: source 0 is the sheet, source 1 the fallback strip.
func build_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	add_sources(ts)
	return ts


## A TileSet for several zones: zone i has source 2i (its sheet) and 2i + 1 (its fallback strip).
static func build_world_tile_set(zones: Array[ZoneTerrain]) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	for z in zones:
		z.add_sources(ts)
	return ts


## Adds the sheet source and the fallback source as the next two source ids of the set.
func add_sources(ts: TileSet) -> void:
	var sheet_id := _next_id(ts)
	var src := TileSetAtlasSource.new()
	src.texture = sheet
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, sheet_id)
	for r in ROLES:
		var variants := ground.size() if r == &"ground" else 1
		for v in variants:
			var c := cell_of(r, v)
			if c != NO_TILE and not src.has_tile(c):
				src.create_tile(c)
	var fb := TileSetAtlasSource.new()
	fb.texture = _fallback_texture()
	fb.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(fb, sheet_id + 1)
	for i in ROLES.size():
		fb.create_tile(Vector2i(i, 0))


static func _next_id(ts: TileSet) -> int:
	var n := 0
	for i in ts.get_source_count():
		n = maxi(n, ts.get_source_id(i) + 1)
	return n


## The source id of this zone's sheet in a set built by `build_world_tile_set` is `2 * slot`; the cell of a role as
## (atlas x, atlas y, source id), with the fallback strip's cell when the role has no sheet tile.
func source_cell(role: StringName, variant: int, slot: int) -> Vector3i:
	var c := cell_of(role, variant)
	if c == NO_TILE:
		return Vector3i(ROLES.find(role), 0, 2 * slot + 1)
	return Vector3i(c.x, c.y, 2 * slot)


func _fallback_texture() -> Texture2D:
	var img := Image.create(TILE * ROLES.size(), TILE, false, Image.FORMAT_RGBA8)
	for i in ROLES.size():
		img.fill_rect(Rect2i(i * TILE, 0, TILE, TILE), color_of(ROLES[i]))
	return ImageTexture.create_from_image(img)

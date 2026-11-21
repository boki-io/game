class_name WorldData
extends RefCounted
## The overworld's data (spec 1.6): the five 2000 x 2000 masks of the world map (collision, zones, edge depth, dirt paths, blocker material) and the marker
## list from the guide's JSON. One tile is one map pixel and 16 world px; the world is 32,000 x 32,000 px. Loaded once and
## shared (`WorldData.shared()`). The masks are read from the imported textures (`load()` and `get_image()`), because an
## exported build has no `res://*.png` bytes, then kept as plain byte arrays; the textures are dropped.

const SIZE := 2000
const TILE_PX := 16
const COLLISION := "res://content/overworld/data/collision.png"
const ZONES := "res://content/overworld/data/zones.png"
const EDGE_DEPTH := "res://content/overworld/data/edge_depth.png"
const PATH_MASK := "res://content/overworld/data/path_mask.png"
const BLOCKER_MATERIAL := "res://content/overworld/data/blocker_material.png"
const MARKERS := "res://content/overworld/data/markers.json"
## The marker kinds whose names are unique (four special markers share names): `marker_named` serves only these.
const NAMED_KINDS: Array[StringName] = [&"start_camp", &"checkpoint", &"cave", &"dungeon", &"final_dungeon"]

const MATERIAL_FOREST := 1
const MATERIAL_ROCK := 2

static var _shared: WorldData

## 255 walkable, 0 blocked (collision_v3.png).
var collision := PackedByteArray()
## The zone index times 30 (zones_v3.png): `zone_at` divides.
var zone_values := PackedByteArray()
## Blocked tiles: tiles to the nearest walkable one (capped at 15); 0 for walkable and beyond the cap.
var depth := PackedByteArray()
## 255 on walkable tiles the guide's paths layer marks as a dirt path (path_mask.png), 0 elsewhere.
var path_mask := PackedByteArray()
## On blocked tiles 1 for forest, 2 for rock, 0 for walkable tiles and other hues (blocker_material.png).
var materials := PackedByteArray()
var markers: Array[Dictionary] = []
## The eight zones in progression order: `index`, `id`, `name`, `dungeon`, `route_start_tile`, `route_end_tile`.
var zones: Array[Dictionary] = []
## The main route sampled every 8 tiles, as tiles.
var main_path: Array[Vector2i] = []
var path_length_tiles := 0
var markers_version := 0  # a hash of markers.json, kept in a journey to notice a changed world file


static func shared() -> WorldData:
	if _shared == null:
		_shared = WorldData.new()
	return _shared


func _init() -> void:
	collision = _mask(COLLISION)
	zone_values = _mask(ZONES)
	depth = _mask(EDGE_DEPTH)
	path_mask = _mask(PATH_MASK)
	materials = _mask(BLOCKER_MATERIAL)
	var text := FileAccess.get_file_as_string(MARKERS)
	markers_version = text.hash()
	var data: Dictionary = JSON.parse_string(text)
	path_length_tiles = int(data.get("path_length_tiles", 0))
	for z in data.zones:
		zones.append(z)
	for m in data.markers:
		markers.append(m)
	for p in data.main_path:
		main_path.append(Vector2i(int(p[0]), int(p[1])))


## One of the masks as 2000 x 2000 bytes: the imported texture, converted to a single 8-bit channel.
static func _mask(path: String) -> PackedByteArray:
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func in_range(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < SIZE and tile.y < SIZE


func is_walkable(tile: Vector2i) -> bool:
	return in_range(tile) and collision[tile.y * SIZE + tile.x] > 127


## The zone index 0 to 7 of a tile (zone 0 outside the map).
func zone_at(tile: Vector2i) -> int:
	if not in_range(tile):
		return 0
	return clampi(zone_values[tile.y * SIZE + tile.x] / 30, 0, 7)


## Tiles from a blocked tile to the nearest walkable one, capped at 15 (15 outside the map, 0 when walkable).
func depth_at(tile: Vector2i) -> int:
	if not in_range(tile):
		return 15
	return depth[tile.y * SIZE + tile.x]


## True on a walkable tile of a dirt path (false outside the map).
func is_path(tile: Vector2i) -> bool:
	return in_range(tile) and path_mask[tile.y * SIZE + tile.x] > 127


## The material of a blocked tile: `MATERIAL_FOREST`, `MATERIAL_ROCK`, or 0 (walkable, other hues, outside the map).
func material_at(tile: Vector2i) -> int:
	if not in_range(tile):
		return 0
	return materials[tile.y * SIZE + tile.x]


static func tile_of(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / TILE_PX), floori(world.y / TILE_PX))


## The centre of a tile in world px (`tile * 16 + 8`).
static func world_of(tile: Vector2i) -> Vector2:
	return Vector2(tile * TILE_PX) + Vector2(TILE_PX / 2.0, TILE_PX / 2.0)


## A marker's position in world px (the JSON's `world_x`, `world_y`).
static func marker_world(marker: Dictionary) -> Vector2:
	return Vector2(float(marker.world_x), float(marker.world_y))


## The marker of a unique-named kind with this name, or an empty dictionary. Specials, camps and caches are addressed by
## index (`marker_at`), because some of their names repeat.
func marker_named(marker_name: String) -> Dictionary:
	for m in markers:
		if StringName(m.kind) in NAMED_KINDS and m.name == marker_name:
			return m
	return {}


func marker_at(index: int) -> Dictionary:
	return markers[index] if index >= 0 and index < markers.size() else {}


func start_marker() -> Dictionary:
	for m in markers:
		if m.kind == "start_camp":
			return m
	return {}

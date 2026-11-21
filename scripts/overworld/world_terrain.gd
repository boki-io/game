class_name WorldTerrain
extends Node2D
## The overworld's chunked terrain (spec 1.6 section 4). The world is 2000 x 2000 tiles; the terrain keeps the chunks
## around a focus position loaded (builds at most `BUILDS_PER_FRAME` per physics frame, nearest first) and frees chunks
## beyond `UNLOAD_RADIUS` (at most `FREES_PER_FRAME` per frame). A chunk is a Node2D with a `ground` and an `overlay`
## TileMapLayer and a `body` StaticBody2D (layer 1) whose rectangles cover blocked tiles 1 to `COLLIDER_DEPTH` deep.
## Uses no autoload: the owner calls `focus()` each physics frame.

const CHUNKS := ceili(float(WorldData.SIZE) / OverworldRules.CHUNK_TILES)
const CHUNK_PX := OverworldRules.CHUNK_TILES * WorldData.TILE_PX
## Blocked tiles deeper than this draw `blocker_deep`.
const DEEP_FROM := 4
const WALL_LAYER := 1

var world: WorldData
var _terrains: Array[ZoneTerrain] = []
## Per zone: the ground cells (Vector3i of atlas x, y and source id), and `_role_cells[zone][role]` for the others.
var _ground_cells: Array = []
var _role_cells: Array = []
var _tile_set: TileSet
var _chunks := {}  # Vector2i -> Node2D
var _focus_chunk := Vector2i(-1000, -1000)


## Loads the eight zone catalogs (in the order of `world.zones`) and builds the shared TileSet.
func setup(world_data: WorldData) -> void:
	world = world_data
	_terrains.clear()
	for z in world.zones:
		_terrains.append(load("res://content/overworld/terrain/%s.tres" % z.id))
	_tile_set = ZoneTerrain.build_world_tile_set(_terrains)
	_ground_cells.clear()
	_role_cells.clear()
	for slot in _terrains.size():
		var t := _terrains[slot]
		var ground: Array[Vector3i] = []
		for v in maxi(t.ground.size(), 1):
			ground.append(t.source_cell(&"ground", v, slot))
		_ground_cells.append(ground)
		var roles: Array[Vector3i] = []
		for r in [&"blocker", &"blocker_deep", &"edge", &"shadow"]:
			roles.append(t.source_cell(r, 0, slot))
		_role_cells.append(roles)


## The terrain to keep loaded: the owner calls this each physics frame with the player's (or camera's) position.
func focus(world_pos: Vector2) -> void:
	_focus_chunk = _chunk_of(world_pos)


func loaded_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _chunks:
		out.append(c)
	return out


func chunk_node(chunk: Vector2i) -> Node2D:
	return _chunks.get(chunk)


func _chunk_of(world_pos: Vector2) -> Vector2i:
	var t := WorldData.tile_of(world_pos)
	return Vector2i(floori(float(t.x) / OverworldRules.CHUNK_TILES), floori(float(t.y) / OverworldRules.CHUNK_TILES))


static func chunk_in_range(chunk: Vector2i) -> bool:
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < CHUNKS and chunk.y < CHUNKS


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var frees := 0
	for c in _chunks.keys():
		if _distance(c, _focus_chunk) > OverworldRules.UNLOAD_RADIUS and frees < OverworldRules.FREES_PER_FRAME:
			free_chunk_now(c)
			frees += 1
	var builds := 0
	while builds < OverworldRules.BUILDS_PER_FRAME:
		var next := _nearest_missing()
		if next.x == -1000:
			break
		build_chunk_now(next)
		builds += 1


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The nearest chunk within the load radius of the focus that is not built (x of -1000 when none).
func _nearest_missing() -> Vector2i:
	var best := Vector2i(-1000, -1000)
	var best_d := INF
	var r := OverworldRules.LOAD_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := _focus_chunk + Vector2i(dx, dy)
			if not chunk_in_range(c) or _chunks.has(c):
				continue
			var d := float(dx * dx + dy * dy)
			if d < best_d:
				best_d = d
				best = c
	return best


func free_chunk_now(chunk: Vector2i) -> void:
	var node: Node2D = _chunks.get(chunk)
	if node == null:
		return
	_chunks.erase(chunk)
	node.queue_free()


## True where the tile is blocked (the map's edge counts as blocked, like `WorldData`).
func _blocked(x: int, y: int) -> bool:
	return x < 0 or y < 0 or x >= WorldData.SIZE or y >= WorldData.SIZE or world.collision[y * WorldData.SIZE + x] <= 127


## A stable hash of a tile (the same after unload and reload): picks the ground variant.
static func tile_hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


func build_chunk_now(chunk: Vector2i) -> void:
	if world == null or not chunk_in_range(chunk) or _chunks.has(chunk):
		return
	var size := WorldData.SIZE
	var n := OverworldRules.CHUNK_TILES
	var ox := chunk.x * n
	var oy := chunk.y * n
	var w := mini(n, size - ox)
	var h := mini(n, size - oy)

	var node := Node2D.new()
	node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	node.position = Vector2(chunk * CHUNK_PX)
	var ground := _layer("ground", -10)
	var overlay := _layer("overlay", -9)
	node.add_child(ground)
	node.add_child(overlay)

	var solid := PackedByteArray()
	solid.resize(w * h)
	var draw_depth := OverworldRules.DRAW_DEPTH
	var collider_depth := OverworldRules.COLLIDER_DEPTH
	for ty in h:
		var y := oy + ty
		for tx in w:
			var x := ox + tx
			var i := y * size + x
			var zone := clampi(world.zone_values[i] / 30, 0, 7)
			var at := Vector2i(tx, ty)
			if world.collision[i] > 127:
				var variants: Array = _ground_cells[zone]
				var cell: Vector3i = variants[tile_hash(x, y) % variants.size()]
				ground.set_cell(at, cell.z, Vector2i(cell.x, cell.y))
				if _blocked(x - 1, y) or _blocked(x, y - 1):
					var s: Vector3i = _role_cells[zone][3]
					overlay.set_cell(at, s.z, Vector2i(s.x, s.y))
				continue
			var d: int = world.depth[i]
			if d < 1 or d > draw_depth:
				continue
			var b: Vector3i = _role_cells[zone][1 if d >= DEEP_FROM else 0]
			ground.set_cell(at, b.z, Vector2i(b.x, b.y))
			if d <= collider_depth:
				solid[ty * w + tx] = 1
			if not (_blocked(x - 1, y) and _blocked(x + 1, y) and _blocked(x, y - 1) and _blocked(x, y + 1)):
				var e: Vector3i = _role_cells[zone][2]
				overlay.set_cell(at, e.z, Vector2i(e.x, e.y))

	node.add_child(_body(solid, w, h))
	add_child(node)
	_chunks[chunk] = node


func _layer(layer_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _tile_set
	layer.z_index = z
	layer.collision_enabled = false
	layer.navigation_enabled = false
	return layer


## One StaticBody2D with the solid tiles merged into rectangles: runs along each row, then runs of the same x and width
## in consecutive rows stacked.
func _body(solid: PackedByteArray, w: int, h: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "body"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var rects: Array[Rect2i] = []
	var open := {}
	for ty in h:
		var cur := {}
		var tx := 0
		while tx < w:
			if solid[ty * w + tx] == 0:
				tx += 1
				continue
			var x0 := tx
			while tx < w and solid[ty * w + tx] == 1:
				tx += 1
			var key := x0 * 64 + (tx - x0)
			if open.has(key):
				var idx: int = open[key]
				rects[idx].size.y += 1
				cur[key] = idx
			else:
				rects.append(Rect2i(x0, ty, tx - x0, 1))
				cur[key] = rects.size() - 1
		open = cur
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size * WorldData.TILE_PX)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = (Vector2(r.position) + Vector2(r.size) / 2.0) * WorldData.TILE_PX
		body.add_child(cs)
	return body

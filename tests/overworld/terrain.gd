extends SceneTree
## The overworld's chunked terrain (spec 1.6 section 4): streaming (3 x 3 chunks, one build and at most two frees per
## frame), the drawn cells against the masks, the stable ground variants, the collider rectangles, a body pushed at a wall
## in four zones and at a gate, and the zone catalogs. WorldTerrain uses no autoload, so it is named through preload.
## Run: godot --headless --path . --script tests/overworld/terrain.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const WorldTerrainS := preload("res://scripts/overworld/world_terrain.gd")
const ZoneTerrainS := preload("res://scripts/overworld/zone_terrain.gd")
const OverworldRulesS := preload("res://scripts/overworld/overworld_rules.gd")

var _failed := false
var _world
var _terrain
var _root: Node2D


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_world = WorldDataS.shared()
	_catalog()
	_root = Node2D.new()
	root.add_child(_root)
	_terrain = WorldTerrainS.new()
	_root.add_child(_terrain)
	_terrain.setup(_world)
	for z in 8:
		await _zone_spot(z)
	await _stability()
	await _push_tests()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## A walkable spot of a zone: a point of the main route inside it.
func _spot(zone: int) -> Vector2i:
	var i: int = int(_world.zones[zone].route_start_tile) / 8 + 30
	return _world.main_path[i]


func _catalog() -> void:
	for slot in 8:
		var id: String = _world.zones[slot].id
		var t = load("res://content/overworld/terrain/%s.tres" % id)
		_check(t != null and t.get_script() == ZoneTerrainS, "zone %s has a ZoneTerrain catalog" % id)
		if t == null:
			continue
		_check(str(t.id) == id and t.sheet != null and t.sheet.get_width() == 256 and t.sheet.get_height() == 256, "%s: id matches and the sheet is 256 x 256" % id)
		var img: Image = t.sheet.get_image()
		var cells: Array[Vector2i] = []
		cells.append_array(t.ground)
		for c in [t.blocker, t.blocker_deep, t.edge, t.shadow]:
			cells.append(c)
		for c in cells:
			if c == ZoneTerrainS.NO_TILE:
				continue
			var opaque := false
			if c.x >= 0 and c.y >= 0 and c.x < 16 and c.y < 16:
				for y in 16:
					for x in 16:
						opaque = opaque or img.get_pixel(c.x * 16 + x, c.y * 16 + y).a > 0.0
			_check(opaque, "%s: atlas cell %s exists in the sheet and is not empty" % [id, c])
		for r in ZoneTerrainS.ROLES:
			if not t.uses_sheet(r):
				_check(t.color_of(r).a > 0.0, "%s: role %s has no sheet tile, so its fallback colour is set" % [id, r])
		var ts = t.build_tile_set()
		_check(ts.get_source_count() == 2, "%s: build_tile_set has a sheet and a fallback source" % id)


## Focus at a spot of a zone: the 3 x 3 chunks load (one build per frame), old chunks are freed (two per frame), and the
## drawn cells and colliders match the masks.
func _zone_spot(zone: int) -> void:
	var tile: Vector2i = _spot(zone)
	_check(_world.is_walkable(tile) and _world.zone_at(tile) == zone, "zone %d spot %s is walkable and in the zone" % [zone, tile])
	var pos: Vector2 = WorldDataS.world_of(tile)
	var chunk := Vector2i(tile.x / 32, tile.y / 32)
	var max_built := 0
	var max_freed := 0
	for f in 30:
		_terrain.focus(pos)
		var before: Array = _terrain.loaded_chunks()
		await physics_frame
		var after: Array = _terrain.loaded_chunks()
		var built := 0
		for c in after:
			if not before.has(c):
				built += 1
		var freed := 0
		for c in before:
			if not after.has(c):
				freed += 1
		max_built = maxi(max_built, built)
		max_freed = maxi(max_freed, freed)
	_check(max_built <= 1, "zone %d: at most one chunk built per frame (%d)" % [zone, max_built])
	_check(max_freed <= 2, "zone %d: at most two chunks freed per frame (%d)" % [zone, max_freed])
	var want: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := chunk + Vector2i(dx, dy)
			if WorldTerrainS.chunk_in_range(c):
				want.append(c)
	var got: Array = _terrain.loaded_chunks()
	got.sort()
	want.sort()
	_check(got == want, "zone %d: exactly the 3 x 3 chunks around %s are loaded (%s)" % [zone, chunk, got])
	_check(_terrain.get_child_count() == got.size(), "zone %d: freed chunk nodes are gone (%d children)" % [zone, _terrain.get_child_count()])
	for c in got:
		_cells(c, zone)
		_colliders(c)


func _cells(chunk: Vector2i, zone: int) -> void:
	var node: Node2D = _terrain.chunk_node(chunk)
	var ground: TileMapLayer = node.get_node("ground")
	var overlay: TileMapLayer = node.get_node("overlay")
	_check(ground.get_used_cells().size() <= 1024 and overlay.get_used_cells().size() <= 1024, "chunk %s: cell counts are bounded" % [chunk])
	_check(ground.z_index < 0 and overlay.z_index < 0, "chunk %s: layers draw below the actors" % [chunk])
	var bad := 0
	var wrong_zone := 0
	var bad_blocker := 0
	var bad_overlay := 0
	var origin := chunk * 32
	var n := mini(32, WorldDataS.SIZE - origin.x)
	var m := mini(32, WorldDataS.SIZE - origin.y)
	for ty in m:
		for tx in n:
			var tile := origin + Vector2i(tx, ty)
			var at := Vector2i(tx, ty)
			var src := ground.get_cell_source_id(at)
			var walk: bool = _world.is_walkable(tile)
			var d: int = _world.depth_at(tile)
			var want_cell: bool = walk or (d >= 1 and d <= OverworldRulesS.DRAW_DEPTH)
			if (src != -1) != want_cell:
				bad += 1
				continue
			if src != -1:
				var z: int = _world.zone_at(tile)
				if src / 2 != z:
					wrong_zone += 1
				if not walk:
					var t = load("res://content/overworld/terrain/%s.tres" % _world.zones[z].id)
					var role := &"blocker_deep" if d > 3 else &"blocker"
					var want: Vector3i = t.source_cell(role, 0, z)
					var coords := ground.get_cell_atlas_coords(at)
					if Vector3i(coords.x, coords.y, src) != want:
						bad_blocker += 1
			var ov := overlay.get_cell_source_id(at)
			if ov != -1:
				var tl = [_world.is_walkable(tile + Vector2i(-1, 0)), _world.is_walkable(tile + Vector2i(1, 0)), _world.is_walkable(tile + Vector2i(0, -1)), _world.is_walkable(tile + Vector2i(0, 1))]
				if walk:
					# a shadow: a blocked tile to the left or above
					if _world.is_walkable(tile + Vector2i(-1, 0)) and _world.is_walkable(tile + Vector2i(0, -1)):
						bad_overlay += 1
				elif not tl.has(true):
					bad_overlay += 1
	_check(bad == 0, "chunk %s: ground cells exactly on walkable tiles and blocked tiles of depth 1 to 15 (%d wrong)" % [chunk, bad])
	_check(wrong_zone == 0, "chunk %s: every cell's zone equals zones.png (%d wrong)" % [chunk, wrong_zone])
	_check(bad_blocker == 0, "chunk %s: blocked tiles use their zone's blocker tile (%d wrong)" % [chunk, bad_blocker])
	_check(bad_overlay == 0, "chunk %s: edge and shadow cells sit where they should (%d wrong)" % [chunk, bad_overlay])


## The collider rectangles cover exactly the blocked tiles of depth 1 and 2, each once, and never a walkable tile.
func _colliders(chunk: Vector2i) -> void:
	var node: Node2D = _terrain.chunk_node(chunk)
	var body: StaticBody2D = node.get_node("body")
	_check(body.collision_layer == 1 and body.collision_mask == 0, "chunk %s: the body is on layer 1, mask 0" % [chunk])
	var cover := {}
	var overlap := 0
	for cs in body.get_children():
		var size: Vector2 = cs.shape.size
		var top_left: Vector2 = cs.position - size / 2.0
		for ty in int(size.y / 16):
			for tx in int(size.x / 16):
				var t := Vector2i(int(top_left.x / 16) + tx, int(top_left.y / 16) + ty)
				if cover.has(t):
					overlap += 1
				cover[t] = true
	_check(overlap == 0, "chunk %s: no tile is covered by two rectangles" % [chunk])
	var origin := chunk * 32
	var walkable_hit := 0
	var deep_hit := 0
	var missing := 0
	for ty in 32:
		for tx in 32:
			var tile := origin + Vector2i(tx, ty)
			if tile.x >= WorldDataS.SIZE or tile.y >= WorldDataS.SIZE:
				continue
			var covered: bool = cover.has(Vector2i(tx, ty))
			var d: int = _world.depth_at(tile)
			if _world.is_walkable(tile):
				if covered:
					walkable_hit += 1
			elif d >= 1 and d <= OverworldRulesS.COLLIDER_DEPTH:
				if not covered:
					missing += 1
			elif covered:
				deep_hit += 1
	_check(walkable_hit == 0, "chunk %s: no walkable tile has a collider (%d)" % [chunk, walkable_hit])
	_check(deep_hit == 0 and missing == 0, "chunk %s: colliders cover depth 1 and 2 only (%d extra, %d missing)" % [chunk, deep_hit, missing])


func _ground_snapshot(chunk: Vector2i) -> Dictionary:
	var ground: TileMapLayer = _terrain.chunk_node(chunk).get_node("ground")
	var out := {}
	for c in ground.get_used_cells():
		out[c] = Vector3i(ground.get_cell_atlas_coords(c).x, ground.get_cell_atlas_coords(c).y, ground.get_cell_source_id(c))
	return out


## The ground variant of a tile is the same after the chunk is freed and built again.
func _stability() -> void:
	await physics_frame
	var tile: Vector2i = _spot(7)  # the zone the streaming loop ended in
	var chunk := Vector2i(tile.x / 32, tile.y / 32)
	var first := _ground_snapshot(chunk)
	_terrain.free_chunk_now(chunk)
	_check(_terrain.chunk_node(chunk) == null, "a freed chunk is no longer loaded")
	_terrain.build_chunk_now(chunk)
	var second := _ground_snapshot(chunk)
	_check(first.size() > 500 and first == second, "the ground variants are the same after unload and reload (%d cells)" % first.size())
	var variants := {}
	for v in first.values():
		variants[v] = true
	_check(variants.size() > 3, "several ground variants are used (%d distinct cells)" % variants.size())


## A CharacterBody2D like the player (layer 2, mask 1) pushed at a wall for 2 s never enters a blocked tile.
func _push_tests() -> void:
	for z in [0, 2, 4, 7]:
		await _push_from(_spot(z), Vector2.ZERO, "zone %d" % z)
	for m in _world.markers:
		if m.kind == "gate":
			var n := Vector2(float(m.nx), float(m.ny)).normalized()
			await _push_from(Vector2i(int(m.x), int(m.y)), n, "gate %s" % m.name)
			break


func _push_from(tile: Vector2i, axis: Vector2, label: String) -> void:
	# find a direction with a wall within 12 tiles: the given axis (both ways) or the four axes
	var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	if axis != Vector2.ZERO:
		dirs = [axis, -axis]
	var best := Vector2.ZERO
	var best_k := 999
	for d in dirs:
		for k in range(1, 40):
			var t := Vector2i((Vector2(tile) + d * k).round())
			if not _world.is_walkable(t):
				if k < best_k:
					best_k = k
					best = d
				break
	_check(best != Vector2.ZERO, "%s: a wall is within 40 tiles" % label)
	if best == Vector2.ZERO:
		return
	var start := WorldDataS.world_of(tile)
	_terrain.focus(start)
	for f in 30:
		_terrain.focus(start)
		await physics_frame
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	cs.shape = circle
	body.add_child(cs)
	body.position = start
	_root.add_child(body)
	var entered := 0
	var frames := int(2.0 * Engine.physics_ticks_per_second)
	for f in frames:
		body.velocity = best * 150.0
		body.move_and_slide()
		var t: Vector2i = WorldDataS.tile_of(body.position)
		if not _world.is_walkable(t):
			entered += 1
		await physics_frame
	_check(entered == 0, "%s: pushed at a wall for 2 s from %s (%d frames inside a blocked tile)" % [label, tile, entered])
	var travelled := body.position.distance_to(start)
	_check(travelled > 8.0 and travelled < (best_k + 1) * 16.0, "%s: the body moved toward the wall and stopped before it (%.0f px, wall %d tiles away)" % [label, travelled, best_k])
	body.queue_free()

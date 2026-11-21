extends SceneTree
## The overworld's chunked terrain (spec 1.6 section 4): streaming (3 x 3 chunks, one build and at most two frees per
## frame), the drawn cells against the masks, the stable ground variants, the collider rectangles, a body pushed at a wall
## in four zones and at a gate, and the zone catalogs. WorldTerrain uses no autoload, so it is named through preload.
## Run: godot --headless --path . --script tests/overworld/terrain.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const WorldTerrainS := preload("res://scripts/overworld/world_terrain.gd")
const ZoneTerrainS := preload("res://scripts/overworld/zone_terrain.gd")
const TerrainArtS := preload("res://scripts/overworld/terrain_art.gd")
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
	_generated_zone()
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
		var atlas: Texture2D = t.atlas()
		_check(str(t.id) == id and atlas != null, "%s: id matches and the zone has an atlas" % id)
		if not t.generated:
			_check(t.sheet != null and t.sheet.get_width() == 256 and t.sheet.get_height() == 256, "%s: the sheet is 256 x 256" % id)
		var img: Image = atlas.get_image()
		var cols := img.get_width() / 16
		var rows := img.get_height() / 16
		var cells: Array[Vector2i] = []
		for r in ZoneTerrainS.ROLES:
			cells.append_array(t.variants_of(r))
		for c in cells:
			if c == ZoneTerrainS.NO_TILE:
				continue
			var opaque := false
			if c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows:
				for y in 16:
					for x in 16:
						opaque = opaque or img.get_pixel(c.x * 16 + x, c.y * 16 + y).a > 0.0
			_check(opaque, "%s: atlas cell %s exists in the sheet and is not empty" % [id, c])
		for r in ZoneTerrainS.ROLES:
			if not t.uses_sheet(r) and t.has_role(r):
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


## The mask of sides of a path tile that touch walkable non-path ground (1 north, 2 east, 4 south, 8 west).
func _rim(tile: Vector2i) -> int:
	var m := 0
	for k in 4:
		var n: Vector2i = tile + [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][k]
		if _world.is_walkable(n) and not _world.is_path(n):
			m |= 1 << k
	return m


func _cells(chunk: Vector2i, zone: int) -> void:
	var node: Node2D = _terrain.chunk_node(chunk)
	var ground: TileMapLayer = node.get_node("ground")
	var overlay: TileMapLayer = node.get_node("overlay")
	_check(ground.get_used_cells().size() <= 1024 and overlay.get_used_cells().size() <= 1024, "chunk %s: cell counts are bounded" % [chunk])
	_check(ground.z_index < 0 and overlay.z_index < 0, "chunk %s: layers draw below the actors" % [chunk])
	var bad := 0
	var wrong_zone := 0
	var bad_blocker := 0
	var bad_walk := 0
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
				if walk:
					var tw = load("res://content/overworld/terrain/%s.tres" % _world.zones[z].id)
					var variants: Array[Vector2i] = tw.variants_of(&"ground")
					var got := ground.get_cell_atlas_coords(at)
					if not tw.path.is_empty() and _world.is_path(tile):
						var rim: int = _rim(tile)
						if rim > 0 and not tw.path_edges.is_empty():
							bad_walk += 0 if got == tw.path_edges[rim] else 1
						else:
							bad_walk += 0 if got == tw.path[WorldTerrainS.tile_hash(tile.x, tile.y) % tw.path.size()] else 1
					elif tw.uses_sheet(&"ground"):
						bad_walk += 0 if got == variants[WorldTerrainS.tile_hash(tile.x, tile.y) % variants.size()] else 1
				if not walk:
					var t = load("res://content/overworld/terrain/%s.tres" % _world.zones[z].id)
					var role := &"blocker_deep" if d > 3 else &"blocker"
					if _world.material_at(tile) == 2 and not t.blocker_rock.is_empty():
						role = &"blocker_rock_deep" if d > 3 else &"blocker_rock"
					var nv: int = t.variants_of(role).size()
					if t.cell_of(role) == ZoneTerrainS.NO_TILE and role == &"blocker_rock_deep":
						role = &"blocker_rock"
						nv = t.blocker_rock.size()
					var want: Vector3i = t.source_cell(role, WorldTerrainS.tile_hash(tile.x, tile.y) % nv, z)
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
	_check(bad_walk == 0, "chunk %s: walkable tiles use their ground or path variant (%d wrong)" % [chunk, bad_walk])
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


## Zone 0 is generated: path tiles draw path variants, other walkable tiles grass, rock tiles rock; the other zones draw no path
## tiles; the atlas is deterministic and holds every cell the catalog names.
func _generated_zone() -> void:
	var t = load("res://content/overworld/terrain/mossy_hollow.tres")
	_check(t.generated and t.sheet == null, "zone 0's catalog is the generated one")
	_check(t.ground.size() >= 6 and t.path.size() >= 4 and (1 + t.blocker_alts.size()) >= 3 and t.blocker_rock.size() >= 3 and t.path_edges.size() == 16, "zone 0 has 6+ grass, 4+ path, 3+ forest and 3+ rock variants")
	_check(t.blocker_deep != ZoneTerrainS.NO_TILE and t.blocker_rock_deep != ZoneTerrainS.NO_TILE, "zone 0 has a deep forest and a deep rock tile")
	var a: Image = t.atlas().get_image()
	var b: Image = TerrainArtS.build_atlas(t.art_seed)
	_check(a.get_data() == b.get_data(), "two builds of the generated atlas are equal")
	_check(TerrainArtS.build_atlas(t.art_seed + 1).get_data() != a.get_data(), "another seed gives another atlas")
	var cols := a.get_width() / 16
	var rows := a.get_height() / 16
	var seen := {}
	for r in ZoneTerrainS.ROLES:
		for c in t.variants_of(r):
			var inside: bool = c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows
			_check(inside, "catalog cell %s of %s is inside the generated atlas" % [c, r])
			if not inside:
				continue
			seen[c] = true
			var alpha := 0
			var colours := {}
			for y in 16:
				for x in 16:
					var px := a.get_pixel(c.x * 16 + x, c.y * 16 + y)
					alpha += 1 if px.a > 0.0 else 0
					colours[px] = true
			_check(alpha > 0, "generated cell %s (%s) is not empty" % [c, r])
			if r in [&"ground", &"path", &"blocker", &"blocker_rock", &"path_edge"]:
				_check(alpha == 256 and colours.size() >= 3, "%s cell %s is opaque with several colours" % [r, c])
	_check(seen.size() >= 8 + 6 + 4 + 4 + 2 + 2 + 16, "every role's cells are distinct tiles (%d)" % seen.size())
	# the world: count what zone-0 tiles around the start camp and the paths draw
	var counts := {"path_ok": 0, "path_bad": 0, "grass_ok": 0, "grass_bad": 0, "rock_ok": 0, "rock_bad": 0}
	var start: Dictionary = _world.start_marker()
	var tile0 := Vector2i(int(start.x), int(start.y))
	var ch0 := Vector2i(tile0.x / 32, tile0.y / 32)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_terrain.build_chunk_now(ch0 + Vector2i(dx, dy))
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var chunk: Vector2i = ch0 + Vector2i(dx, dy)
			var node: Node2D = _terrain.chunk_node(chunk)
			if node == null:
				continue
			var ground: TileMapLayer = node.get_node("ground")
			for ty in 32:
				for tx in 32:
					var tile: Vector2i = chunk * 32 + Vector2i(tx, ty)
					if _world.zone_at(tile) != 0:
						continue
					var c := ground.get_cell_atlas_coords(Vector2i(tx, ty))
					if ground.get_cell_source_id(Vector2i(tx, ty)) != 0:
						continue
					if _world.is_walkable(tile):
						if _world.is_path(tile):
							counts["path_ok" if (c in t.path or c in t.path_edges) else "path_bad"] += 1
						else:
							counts["grass_ok" if c in t.ground else "grass_bad"] += 1
					elif _world.material_at(tile) == 2:
						counts["rock_ok" if (c in t.blocker_rock or c == t.blocker_rock_deep) else "rock_bad"] += 1
	_check(counts.path_ok > 100 and counts.path_bad == 0, "zone 0: path tiles use path variants (%d ok, %d wrong)" % [counts.path_ok, counts.path_bad])
	_check(counts.grass_ok > 1000 and counts.grass_bad == 0, "zone 0: other walkable tiles use grass variants (%d ok, %d wrong)" % [counts.grass_ok, counts.grass_bad])
	_check(counts.rock_ok > 100 and counts.rock_bad == 0, "zone 0: rock tiles use rock variants (%d ok, %d wrong)" % [counts.rock_ok, counts.rock_bad])
	# no path tile is drawn as a path in a zone without the path role: the other catalogs have none
	for slot in range(1, 8):
		var o = load("res://content/overworld/terrain/%s.tres" % _world.zones[slot].id)
		_check(o.path.is_empty() and o.blocker_rock.is_empty() and not o.generated, "zone %d has no path or rock role and no generated atlas" % slot)
	var path_elsewhere := 0
	for chunk in _terrain.loaded_chunks():
		var node: Node2D = _terrain.chunk_node(chunk)
		var ground: TileMapLayer = node.get_node("ground")
		for cell in ground.get_used_cells():
			var tile: Vector2i = chunk * 32 + cell
			if _world.zone_at(tile) != 0 and ground.get_cell_source_id(cell) == 2 * _world.zone_at(tile):
				var o = load("res://content/overworld/terrain/%s.tres" % _world.zones[_world.zone_at(tile)].id)
				if _world.is_path(tile) and ground.get_cell_atlas_coords(cell) not in o.ground:
					path_elsewhere += 1
	_check(path_elsewhere == 0, "no path variant is drawn in a zone without the path role (%d)" % path_elsewhere)


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

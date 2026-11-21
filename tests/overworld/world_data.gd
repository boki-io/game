extends SceneTree
## The overworld's data (spec 1.6): the masks and JSON are as the guide says, tile and world positions invert each other,
## every marker stands on a walkable tile and is reachable from the start camp, the zone and depth masks are consistent, and
## the gates are narrow.
## Run: godot --headless --path . --script tests/overworld/world_data.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var w = WorldDataS.shared()
	_data(w)
	_markers(w)
	_reach(w)
	_depth(w)
	_terrain_masks(w)
	_gates(w)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _data(w) -> void:
	_check(w.collision.size() == 4_000_000 and w.zone_values.size() == 4_000_000 and w.depth.size() == 4_000_000, "each mask is 2000 x 2000 bytes (%d, %d, %d)" % [w.collision.size(), w.zone_values.size(), w.depth.size()])
	_check(w.zones.size() == 8 and w.path_length_tiles == 6723 and w.main_path.size() == 841, "8 zones, route 6723 tiles, 841 path points")
	var ids := []
	for z in w.zones:
		ids.append(z.id)
	_check(ids == ["mossy_hollow", "flooded_gallery", "spore_cavern", "bone_warren", "sulfur_pits", "ember_depths", "frostbite_grotto", "crystal_vault"], "the zone ids in progression order: %s" % [ids])
	for id in ids:
		_check(DirAccess.dir_exists_absolute("res://content/maps/%s" % id), "zone %s is a map folder" % id)
	var walkable := 0
	var bad_values := 0
	for i in 4_000_000:
		if w.collision[i] > 127:
			walkable += 1
			if w.zone_values[i] % 30 != 0 or w.zone_values[i] / 30 > 7:
				bad_values += 1
	var share := float(walkable) / 4_000_000.0
	_check(share > 0.10 and share < 0.20, "walkable share %.3f between 10%% and 20%%" % share)
	_check(bad_values == 0, "walkable tiles have zone values 0 to 7 (%d bad)" % bad_values)
	_check(w.tile_of(Vector2(8, 8)) == Vector2i(0, 0) and w.tile_of(Vector2(31999, 31999)) == Vector2i(1999, 1999) and w.tile_of(Vector2(-1, 0)).x == -1, "tile_of")
	_check(w.world_of(Vector2i(51, 1936)) == Vector2(824, 30984) and w.tile_of(w.world_of(Vector2i(7, 9))) == Vector2i(7, 9), "world_of is tile * 16 + 8 and inverts tile_of")
	_check(not w.is_walkable(Vector2i(-1, 5)) and not w.is_walkable(Vector2i(2000, 0)) and w.zone_at(Vector2i(-3, 3)) == 0 and w.depth_at(Vector2i(-3, 3)) == 15, "outside the map is blocked, zone 0, depth 15")


func _markers(w) -> void:
	var kinds := {}
	var subtypes := {}
	var names := {}
	for m in w.markers:
		kinds[m.kind] = kinds.get(m.kind, 0) + 1
		if m.kind == "special":
			subtypes[m.subtype] = subtypes.get(m.subtype, 0) + 1
		var tile := Vector2i(int(m.x), int(m.y))
		_check(w.is_walkable(tile), "marker %s (%s) is on a walkable tile" % [m.name, m.kind])
		_check(w.marker_world(m) == w.world_of(tile), "marker %s world position is tile * 16 + 8" % m.name)
		_check(int(m.zone) >= 0 and int(m.zone) <= 7, "marker %s has a zone" % m.name)
		if StringName(m.kind) in w.NAMED_KINDS:
			_check(not names.has(m.name), "marker name %s is unique among the named kinds" % m.name)
			names[m.name] = true
			_check(w.marker_named(m.name) == m, "marker_named finds %s" % m.name)
	var want := {"start_camp": 1, "checkpoint": 16, "gate": 7, "camp": 31, "cave": 18, "dungeon": 8, "final_dungeon": 1, "special": 18, "cache": 4, "arena": 4}
	_check(kinds == want, "marker counts by kind: %s" % [kinds])
	_check(subtypes == {"hermit": 8, "shrine": 6, "ruins": 3, "altar": 1}, "special subtypes: %s" % [subtypes])
	_check(w.markers.size() == 108, "108 markers")
	_check(w.start_marker().name == "Starting Camp" and w.marker_at(0) == w.markers[0] and w.marker_at(500).is_empty(), "start marker and marker_at")
	for m in w.markers:
		if m.kind in ["cave", "dungeon", "final_dungeon"]:
			_check(DirAccess.dir_exists_absolute("res://content/maps/%s" % m.map_id), "%s names a map folder (%s)" % [m.name, m.map_id])
	for p in w.main_path:
		_check(w.is_walkable(p), "main path point %s is walkable" % [p])


## Every marker is reachable from the start camp over walkable tiles (4-connected flood fill on the mask).
func _reach(w) -> void:
	var seen := PackedByteArray()
	seen.resize(4_000_000)
	var queue := PackedInt32Array()
	queue.resize(700_000)
	var start = w.start_marker()
	var s := int(start.y) * 2000 + int(start.x)
	var head := 0
	var tail := 0
	queue[tail] = s
	tail += 1
	seen[s] = 1
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % 2000
		var y := i / 2000
		for n in [i - 1 if x > 0 else -1, i + 1 if x < 1999 else -1, i - 2000 if y > 0 else -1, i + 2000 if y < 1999 else -1]:
			if n >= 0 and seen[n] == 0 and w.collision[n] > 127:
				seen[n] = 1
				queue[tail] = n
				tail += 1
	for m in w.markers:
		_check(seen[int(m.y) * 2000 + int(m.x)] == 1, "marker %s is reachable from the start camp" % m.name)


## path_mask.png marks walkable tiles only (a sensible share, some in zone 0); blocker_material.png blocked tiles only.
func _terrain_masks(w) -> void:
	_check(w.path_mask.size() == 4_000_000 and w.materials.size() == 4_000_000, "the path and material masks are 2000 x 2000 bytes")
	var paths := 0
	var zone0_paths := 0
	var on_blocked := 0
	var material_on_walkable := 0
	var forest := 0
	var rock := 0
	var bad_value := 0
	var blocked := 0
	for i in 4_000_000:
		var walk: bool = w.collision[i] > 127
		if not walk:
			blocked += 1
		if w.path_mask[i] > 127:
			paths += 1
			if not walk:
				on_blocked += 1
			if w.zone_values[i] / 30 == 0:
				zone0_paths += 1
		if w.materials[i] != 0:
			if walk:
				material_on_walkable += 1
			elif w.materials[i] == 1:
				forest += 1
			elif w.materials[i] == 2:
				rock += 1
			else:
				bad_value += 1
	_check(on_blocked == 0, "no path tile is blocked (%d)" % on_blocked)
	_check(paths > 20_000 and paths < 600_000, "the paths cover a sensible share of the world (%d tiles)" % paths)
	_check(zone0_paths > 1000, "zone 0 has dirt path tiles (%d)" % zone0_paths)
	_check(material_on_walkable == 0 and bad_value == 0, "materials are 1 or 2 and only on blocked tiles (%d on walkable, %d odd)" % [material_on_walkable, bad_value])
	_check(forest > 100_000 and rock > 100_000, "both forest and rock exist (%d, %d of %d blocked)" % [forest, rock, blocked])
	var start: Dictionary = w.start_marker()
	var near_path := false
	for dy in range(-40, 41):
		for dx in range(-40, 41):
			near_path = near_path or w.is_path(Vector2i(int(start.x) + dx, int(start.y) + dy))
	_check(near_path, "a dirt path starts within 40 tiles of the start camp")
	_check(not w.is_path(Vector2i(-1, 0)) and w.material_at(Vector2i(2000, 5)) == 0, "outside the map is no path and no material")


## edge_depth.png is 0 on walkable tiles, 1 beside them, and equals the Chebyshev distance (capped at 15) on a sample.
func _depth(w) -> void:
	for i in 4_000_000:
		if w.collision[i] > 127 and w.depth[i] != 0:
			_check(false, "walkable tile %d has depth %d" % [i, w.depth[i]])
			break
	var bad := 0
	var checked := 0
	for chunk in [Vector2i(1, 59), Vector2i(14, 50), Vector2i(30, 30), Vector2i(50, 10), Vector2i(58, 4), Vector2i(8, 56)]:
		for ty in range(chunk.y * 32, chunk.y * 32 + 32):
			for tx in range(chunk.x * 32, chunk.x * 32 + 32):
				var tile := Vector2i(tx, ty)
				if tx >= 2000 or ty >= 2000 or w.is_walkable(tile):
					continue
				var best := 16
				for r in range(1, 16):
					var found := false
					for dy in range(-r, r + 1):
						for dx in range(-r, r + 1):
							if maxi(absi(dx), absi(dy)) != r:
								continue
							if w.is_walkable(Vector2i(tx + dx, ty + dy)):
								found = true
								break
						if found:
							break
					if found:
						best = r
						break
				var want := best if best <= 15 else 0
				checked += 1
				if w.depth_at(tile) != want:
					bad += 1
	_check(checked > 500 and bad == 0, "edge depth equals the Chebyshev distance on %d sampled blocked tiles (%d wrong)" % [checked, bad])


## A gate's open gap, measured along the gate's (nx, ny) vector, is narrow (the guide says 12; the corridor wiggles: 10 to 21).
func _gates(w) -> void:
	for m in w.markers:
		if m.kind != "gate":
			continue
		var n := Vector2(float(m.get("nx", 0.0)), float(m.get("ny", 0.0))).normalized()
		var along := n  # the marker's (nx, ny) runs across the gap
		var origin := Vector2(float(m.x), float(m.y))
		var count := 1
		for sign_dir in [1.0, -1.0]:
			var k := 1
			while k < 40 and w.is_walkable(Vector2i((origin + along * sign_dir * k).round())):
				count += 1
				k += 1
		_check(count >= 10 and count <= 21, "gate %s is %d tiles wide (10 to 21)" % [m.name, count])

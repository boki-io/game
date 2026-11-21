extends SceneTree
## The nature layout (spec 1.7 section 3 and 4), on the real world data with a fake sprite catalog: a chunk's props are the
## same on every call and whatever was built first, every base is inside its chunk, nothing is placed twice, every placement
## passes the rules (also for 30 other seeds), the statistics of the green zone hold, loner trees stand alone, the rule streams
## are independent, the per-chunk cap holds and a closed cell has nothing.
## Run: godot --headless --path . --script tests/overworld/nature_layout.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const Layout := preload("res://scripts/overworld/nature_layout.gd")
const Rules := preload("res://scripts/overworld/nature_rules.gd")
const FakeSprites := preload("res://tests/overworld/fake_nature_sprites.gd")
const SEED_COUNT := 30
## The chunks that touch the green zone's bounding box (x 0 to 1003, y 1539 to 1988 tiles).
const CHUNK_X := [0, 33]
const CHUNK_Y := [47, 63]

var _failed := false
var _world
var _sprites


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_world = WorldDataS.shared()
	_sprites = FakeSprites.new()
	var rules: Rules = load("res://content/overworld/nature/mossy_hollow.tres")
	var cache := {}
	var all := _zone_props(rules, cache)
	var chunks := _chunk_list(all)
	_check(all.size() > 500, "the zone has props (%d)" % all.size())
	_reproducible(rules, chunks)
	_inside_and_unique(rules, cache)
	_check_rules(rules, all, "shipped seed")
	_statistics(rules, all)
	_loners(all)
	_independent_rules(rules, all)
	_cap_and_closed_cells(rules, cache)
	_other_seeds(rules, chunks)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Every placement of every chunk of the box (Array of Placement), building through `cache`.
func _zone_props(rules, cache: Dictionary) -> Array:
	var out := []
	for cy in range(CHUNK_Y[0], CHUNK_Y[1] + 1):
		for cx in range(CHUNK_X[0], CHUNK_X[1] + 1):
			out.append_array(Layout.props_for_chunk(_world, rules, _sprites, Vector2i(cx, cy), cache))
	return out


## The chunks holding at least 20 placements, in scan order.
func _chunk_list(all: Array) -> Array:
	var counts := {}
	for p in all:
		var c := Vector2i(floori(p.base.x / 512.0), floori(p.base.y / 512.0))
		counts[c] = counts.get(c, 0) + 1
	var out := []
	for cy in range(CHUNK_Y[0], CHUNK_Y[1] + 1):
		for cx in range(CHUNK_X[0], CHUNK_X[1] + 1):
			if counts.get(Vector2i(cx, cy), 0) >= 20:
				out.append(Vector2i(cx, cy))
	return out


func _signature(list: Array) -> String:
	var parts := PackedStringArray()
	for p in list:
		parts.append("%s %d %s %s %.2f %d" % [p.kind, p.sprite, p.base, p.flip, p.solid_radius, p.rule])
	return "\n".join(parts)


func _reproducible(rules, chunks: Array) -> void:
	_check(chunks.size() > 30, "at least 30 chunks hold 20 or more props (%d)" % chunks.size())
	var chunk: Vector2i = chunks[chunks.size() / 2]
	var a := _signature(Layout.props_for_chunk(_world, rules, _sprites, chunk))
	var b := _signature(Layout.props_for_chunk(_world, rules, _sprites, chunk))
	_check(a == b and not a.is_empty(), "a chunk's props are the same on two calls")
	var cache := {}
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, 1)]:
		Layout.props_for_chunk(_world, rules, _sprites, chunk + d, cache)
	_check(_signature(Layout.props_for_chunk(_world, rules, _sprites, chunk, cache)) == a, "the same props when neighbours were built first (shared cache)")
	Layout.evict(cache, chunk + Vector2i(3, 0), 1)
	_check(_signature(Layout.props_for_chunk(_world, rules, _sprites, chunk, cache)) == a, "the same props after eviction")
	_check(not cache.is_empty(), "the cache holds cells")
	_check(Layout.mix(1707, 3, 4, 1) == Layout.mix(1707, 3, 4, 1) and Layout.mix(1707, 3, 4, 1) != Layout.mix(1707, 3, 4, 2) and Layout.mix(1707, 3, 4, 1) != Layout.mix(1707, 4, 3, 1), "mix is stable and depends on every part")


func _inside_and_unique(rules, cache: Dictionary) -> void:
	var seen := {}
	var outside := 0
	var dupes := 0
	for cy in range(CHUNK_Y[0], CHUNK_Y[1] + 1):
		for cx in range(CHUNK_X[0], CHUNK_X[1] + 1):
			for p in Layout.props_for_chunk(_world, rules, _sprites, Vector2i(cx, cy), cache):
				if Vector2i(floori(p.base.x / 512.0), floori(p.base.y / 512.0)) != Vector2i(cx, cy):
					outside += 1
				var key := "%s %s" % [p.kind, p.base]
				if seen.has(key):
					dupes += 1
				seen[key] = true
				_check(p.sprite >= 0 and p.sprite < _sprites.count(p.kind), "sprite index in range")
	_check(outside == 0, "every base is inside its chunk (%d outside)" % outside)
	_check(dupes == 0, "no prop is placed twice (%d)" % dupes)


## Walkable, zone, off the path, wall and path clearances by kind, marker clearings, trunk spacing.
func _check_rules(rules, list: Array, label: String) -> void:
	var trees := PackedVector2Array()
	for p in list:
		if p.kind == &"tree":
			trees.append(p.base)
	var bad := {}
	var radius_ok := true
	for p in list:
		var tile: Vector2i = WorldDataS.tile_of(p.base)
		var large: bool = p.kind == &"tree" or (p.kind == &"rock" and p.solid_radius > 0.0)
		if not _world.is_walkable(tile) or _world.zone_at(tile) != rules.zone:
			bad["not walkable zone tile"] = true
		if _world.is_path(tile):
			bad["on the path"] = true
		var wall: int = rules.wall_clear_tiles if large else rules.wall_clear_small_tiles
		for dy in range(-wall, wall + 1):
			for dx in range(-wall, wall + 1):
				if not _world.is_walkable(tile + Vector2i(dx, dy)):
					bad["wall clearance"] = true
		if large:
			for dy in range(-rules.path_clear_tiles, rules.path_clear_tiles + 1):
				for dx in range(-rules.path_clear_tiles, rules.path_clear_tiles + 1):
					if _world.is_path(tile + Vector2i(dx, dy)):
						bad["path clearance"] = true
		for m in _world.markers:
			var tiles: int = rules.marker_clear_tiles if m.kind in ["start_camp", "checkpoint", "gate", "camp"] else rules.marker_clear_minor_tiles
			if p.base.distance_to(WorldDataS.marker_world(m)) < tiles * 16.0:
				bad["marker clearing"] = true
		if p.kind != &"tree":
			for q in trees:
				if p.base.distance_to(q) < rules.trunk_clear_px:
					bad["rock or shrub on a trunk"] = true
		var want := 0.0
		if p.kind == &"tree":
			want = rules.trunk_radius_px
		elif large:
			want = rules.big_rock_radius_factor * _sprites.size_px(&"rock", p.sprite).x * 0.5
		if absf(p.solid_radius - want) > 0.001:
			radius_ok = false
	_check(bad.is_empty(), "%s: every placement passes the rules (%s)" % [label, bad.keys()])
	_check(radius_ok, "%s: solid radii are the trunk radius, the big-rock factor and 0" % label)


func _statistics(rules, all: Array) -> void:
	var trees := []
	var rocks := []
	var shrubs := []
	for p in all:
		if p.kind == &"tree":
			trees.append(p)
		elif p.kind == &"rock":
			rocks.append(p)
		else:
			shrubs.append(p)
	var walkable := 0
	for i in 4_000_000:
		if _world.collision[i] > 127 and _world.zone_values[i] / 30 == rules.zone:
			walkable += 1
	var per_1000 := 1000.0 * trees.size() / walkable
	_check(per_1000 >= 8.0 and per_1000 <= 18.0, "trees per 1000 walkable tiles %.1f in 8 to 18 (%d trees)" % [per_1000, trees.size()])
	var in_wood := 0
	for a in trees:
		var n := 0
		for b in trees:
			if a != b and a.base.distance_to(b.base) < 96.0:
				n += 1
		if n >= 3:
			in_wood += 1
	var wood_share := float(in_wood) / maxi(trees.size(), 1)
	_check(wood_share >= 0.35 and wood_share <= 0.60, "%.0f %% of trees are in a wood (35 to 60)" % (wood_share * 100.0))
	var seen := {}
	var woods := 0
	for i in trees.size():
		if seen.has(i):
			continue
		var group := [i]
		seen[i] = true
		var k := 0
		while k < group.size():
			for j in trees.size():
				if not seen.has(j) and trees[group[k]].base.distance_to(trees[j].base) < 64.0:
					seen[j] = true
					group.append(j)
			k += 1
		if group.size() >= 5:
			woods += 1
	_check(woods >= 20, "%d clumps of 5 or more trees (at least 20)" % woods)
	var bigs := []
	for r in rocks:
		if r.solid_radius > 0.0:
			bigs.append(r)
	var piles := 0
	var pile_big := {}
	for b in bigs:
		var near := 0
		for r in rocks:
			if r != b and r.base.distance_to(b.base) < 48.0:
				near += 1
		if near >= 2:
			piles += 1
			pile_big[b] = true
	var in_pile := 0
	for r in rocks:
		for b in pile_big:
			if r.base.distance_to(b.base) < 48.0:
				in_pile += 1
				break
	var pile_share := float(in_pile) / maxi(rocks.size(), 1)
	_check(piles >= 15, "%d rock piles (at least 15)" % piles)
	_check(pile_share >= 0.30 and pile_share <= 0.60, "%.0f %% of rocks are in a pile (30 to 60, %d rocks)" % [pile_share * 100.0, rocks.size()])
	var by_path := 0
	for s in shrubs:
		var tile: Vector2i = WorldDataS.tile_of(s.base)
		var hit := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				hit = hit or _world.is_path(tile + Vector2i(dx, dy))
		if hit:
			by_path += 1
	var path_share := float(by_path) / maxi(shrubs.size(), 1)
	_check(path_share >= 0.25, "%.0f %% of shrubs are within 3 tiles of the path (at least 25, %d shrubs)" % [path_share * 100.0, shrubs.size()])
	var camp: Vector2 = WorldDataS.marker_world(_world.start_marker())
	var nearest := 1e9
	for p in all:
		nearest = minf(nearest, p.base.distance_to(camp))
	_check(nearest >= 14.0 * 16.0, "no prop within 14 tiles of the start camp (nearest %.0f px)" % nearest)
	var autumn := 0
	var tree_tags: Array = _sprites.indices_with_tag(&"tree", "autumn")
	for t in trees:
		if t.sprite in tree_tags:
			autumn += 1
	_check(autumn > 0 and float(autumn) / trees.size() < 0.2, "a few autumn trees (%d of %d)" % [autumn, trees.size()])


## Loner trees keep `loner_clear_tiles` from every other tree.
func _loners(all: Array) -> void:
	var rules: Rules = load("res://content/overworld/nature/mossy_hollow.tres")
	var trees := []
	for p in all:
		if p.kind == &"tree":
			trees.append(p)
	var loners := 0
	var close := 0
	for a in trees:
		if a.rule != Layout.RULE_LONER_TREE:
			continue
		loners += 1
		for b in trees:
			if a != b and a.base.distance_to(b.base) < rules.loner_clear_tiles * 16.0:
				close += 1
	_check(loners > 100, "there are loner trees (%d)" % loners)
	_check(close == 0, "loner trees are at least %d tiles from other trees (%d pairs too close)" % [rules.loner_clear_tiles, close])


## With no woods, the rocks and shrubs of the other rules stay, except where a wood's trunk had kept them off (and the
## other way round): the rule streams do not share draws.
func _independent_rules(rules, _all: Array) -> void:
	var base: Rules = rules.duplicate()
	base.max_props_per_chunk = 100000
	var none: Rules = base.duplicate()
	none.wood_chance = 0.0
	var a := _zone_props(base, {})
	var b := _zone_props(none, {})
	var key := func(p) -> String: return "%s %d %s" % [p.kind, p.sprite, p.base]
	var small_a := {}
	var small_b := {}
	var trees_a := []
	var trees_b := []
	for p in a:
		if p.kind == &"tree":
			trees_a.append(p.base)
		elif p.rule != Layout.RULE_WOOD:
			small_a[key.call(p)] = p
	for p in b:
		if p.kind == &"tree":
			trees_b.append(p.base)
		elif p.rule != Layout.RULE_WOOD:
			small_b[key.call(p)] = p
	var lost := 0
	for k in small_a:
		if not small_b.has(k):
			var near := false
			for t in trees_b:
				near = near or t.distance_to(small_a[k].base) < base.trunk_clear_px
			if not near:
				lost += 1
	var extra := 0
	for k in small_b:
		if not small_a.has(k):
			var near := false
			for t in trees_a:
				near = near or t.distance_to(small_b[k].base) < base.trunk_clear_px
			if not near:
				extra += 1
	_check(small_a.size() > 300, "rocks and shrubs of the other rules exist (%d)" % small_a.size())
	_check(lost == 0 and extra == 0, "wood_chance 0 changes no other rock or shrub except by trunk clearance (%d lost, %d new)" % [lost, extra])
	var woodless := 0
	for p in b:
		if p.rule == Layout.RULE_WOOD:
			woodless += 1
	_check(woodless == 0, "wood_chance 0 places no wood props (%d)" % woodless)


func _cap_and_closed_cells(rules, cache: Dictionary) -> void:
	var capped: Rules = rules.duplicate()
	capped.max_props_per_chunk = 7
	var full: Rules = rules.duplicate()
	full.max_props_per_chunk = 100000
	var chunk := Vector2i(10, 55)
	var n := 0
	for cy in range(CHUNK_Y[0], CHUNK_Y[1] + 1):
		for cx in range(CHUNK_X[0], CHUNK_X[1] + 1):
			var c := Layout.props_for_chunk(_world, capped, _sprites, Vector2i(cx, cy))
			var f := Layout.props_for_chunk(_world, full, _sprites, Vector2i(cx, cy))
			if c.size() > 7 or c.size() != mini(f.size(), 7) or _signature(c) != _signature(f.slice(0, c.size())):
				n += 1
	_check(n == 0, "max_props_per_chunk caps every chunk and drops only the last placements (%d wrong)" % n)
	var stock := 0
	for cy in range(CHUNK_Y[0], CHUNK_Y[1] + 1):
		for cx in range(CHUNK_X[0], CHUNK_X[1] + 1):
			stock = maxi(stock, Layout.props_for_chunk(_world, rules, _sprites, Vector2i(cx, cy), cache).size())
	_check(stock <= rules.max_props_per_chunk, "no shipped chunk is over the cap (%d)" % stock)
	_check(Layout.open_factor(_world, rules, Vector2i(0, 0)) == 0.0 and Layout.props_for_chunk(_world, rules, _sprites, Vector2i(0, 0)).is_empty(), "a cell with no open tile has no props")
	_check(Layout.props_for_chunk(_world, rules, _sprites, Vector2i(-3, -3)).is_empty() and Layout.props_for_chunk(_world, rules, _sprites, Vector2i(70, 70)).is_empty(), "chunks outside the map have no props")
	var open := Layout.open_factor(_world, rules, chunk)
	_check(open >= 0.0 and open <= 1.0, "open factor is a share (%.2f)" % open)


## The rules also hold for other seeds, over a sample of 40 chunks each.
func _other_seeds(rules, chunks: Array) -> void:
	var step := maxi(1, chunks.size() / 40)
	var sample := []
	for i in range(0, chunks.size(), step):
		sample.append(chunks[i])
	sample = sample.slice(0, 40)
	for s in SEED_COUNT:
		var alt: Rules = rules.duplicate()
		alt.seed = 1000 + s * 7919
		var cache := {}
		var list := []
		for chunk in sample:
			list.append_array(Layout.props_for_chunk(_world, alt, _sprites, chunk, cache))
		_check(list.size() > 200, "seed %d places props (%d)" % [alt.seed, list.size()])
		_check_rules(alt, list, "seed %d" % alt.seed)

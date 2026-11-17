extends SceneTree
## Sprite props and prop sets (test-props): the catalog and its sets load, every theme with props places them legally for 30 seeds (inside the room,
## off the start square, passable gaps to walls and other blockers, no sealed area), a seed repeats, and adding props
## moves no wall, pillar, decor piece or torch.
## Run: godot --headless --path . --script tests/maps/map_props.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const Layout := preload("res://scripts/maps/map_layout.gd")
const Catalog := preload("res://scripts/maps/prop_catalog.gd")
const ObstacleMapScript := preload("res://scripts/maps/obstacle_map.gd")
const FlowFieldScript := preload("res://scripts/maps/flow_field.gd")
const Builder := preload("res://scripts/maps/map_builder.gd")

const SEED_COUNT := 30
const SIZE := Vector2(1600, 896)
const BAND := 16.0
const CELL := 16.0
const REACH := 0.99
const PLACED_FLOOR := 0.8  # share of prop_count (single props) that must be placed
const SETS_FLOOR := 0.6  # share of a map's sets that must be placed over the seeds

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 25:
			print("FAIL: ", what)


func _init() -> void:
	_catalog()
	var themes_with_props := 0
	for theme in Registry.all():
		if theme.prop_count > 0:
			themes_with_props += 1
			_theme(theme)
	_check(themes_with_props >= 8, "at least the eight maps have props (%d)" % themes_with_props)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _catalog() -> void:
	var c := Catalog.get_shared()
	_check(c != null and c.sheet != null, "the catalog and its sheet load")
	var ids := {}
	var groups := {}
	for p in c.props:
		_check(not ids.has(p.id), "prop id %s is unique" % p.id)
		ids[p.id] = true
		groups[p.group] = true
		var sheet := Rect2i(Vector2i.ZERO, c.sheet.get_size())
		_check(sheet.encloses(p.region), "%s lies on the sheet" % p.id)
		_check(Rect2(p.region).has_point(p.anchor + Vector2(p.region.position)) or p.anchor.y == p.region.size.y,
			"%s anchor is in its region" % p.id)
		_check(c.find(p.id) == p, "%s is found by id" % p.id)
	for g in [&"storage", &"grave", &"furniture", &"monument", &"rock"]:
		_check(groups.has(g), "group %s has props" % g)
	var set_ids := {}
	for set in c.sets:
		_check(not set_ids.has(set.id), "set id %s is unique" % set.id)
		set_ids[set.id] = true
		_check(not set.members.is_empty(), "set %s has members" % set.id)
		for m in set.members:
			_check(m.count_min >= 0 and m.count_max >= m.count_min, "set %s: count range" % set.id)
			_check(m.chance >= 0.0 and m.chance <= 1.0, "set %s: chance" % set.id)
			_check(not m.props.is_empty() or m.group != &"", "set %s: a line names props or a group" % set.id)
			for pid in m.props:
				_check(c.find(pid) != null, "set %s: prop %s exists" % [set.id, pid])
	for want in [&"graveyard_small", &"graveyard_medium", &"graveyard_large", &"camp_small", &"camp_supply", &"camp_cache",
			&"nook_crates", &"nook_barrels", &"nook_pots"]:
		_check(set_ids.has(want), "set %s exists" % want)


func _theme(theme) -> void:
	var catalog := Catalog.get_shared()
	var singles_min := 1.0
	var sets_wanted := 0
	var sets_placed := 0
	var placed_kinds := {}
	for sid in theme.prop_sets:
		_check(catalog.find_set(StringName(sid)) != null, "%s names a set that exists: %s" % [theme.id, sid])
	for i in SEED_COUNT:
		var map_seed := hash("%d:%s" % [i, theme.id])
		var a = Layout.generate(theme, map_seed, SIZE)
		var b = Layout.generate(theme, map_seed, SIZE)
		_check(a.equals(b), "%s seed %d repeats" % [theme.id, i])
		var singles := 0
		var instances := {}
		for item in a.props:
			if item.set == &"":
				singles += 1
			else:
				instances[item.inst] = item.set
		if theme.prop_count > 0:
			singles_min = minf(singles_min, float(singles) / theme.prop_count)
		for inst in instances:
			placed_kinds[instances[inst]] = true
		sets_placed += instances.size()
		for sid in theme.prop_sets:
			sets_wanted += int(theme.prop_sets[sid])
		_legal(theme, a, catalog, i)
		_isolated(theme, a, map_seed)
	_check(singles_min >= PLACED_FLOOR, "%s places at least %.0f%% of its single props (%.2f)" % [theme.id, PLACED_FLOOR * 100.0, singles_min])
	if sets_wanted > 0:
		var share := float(sets_placed) / sets_wanted
		_check(share >= SETS_FLOOR, "%s places at least %.0f%% of its sets (%.2f)" % [theme.id, SETS_FLOOR * 100.0, share])
		for sid in theme.prop_sets:
			_check(placed_kinds.has(StringName(sid)), "%s: set %s is placed in some seed" % [theme.id, sid])


func _legal(theme, layout, catalog, i: int) -> void:
	var start: Rect2 = Layout.start_rect(SIZE)
	var inner := Rect2(Vector2(BAND, BAND), SIZE - Vector2(BAND, BAND) * 2.0)
	var blockers: Array[Dictionary] = []  # {rect, inst, nook}
	var single_inst := 1000
	for item in layout.props:
		var data = catalog.find(item.id)
		_check(data != null, "%s %d: prop %s is in the catalog" % [theme.id, i, item.id])
		if item.set == &"":
			_check(theme.prop_weights.has(String(data.group)), "%s %d: %s is of a weighted group" % [theme.id, i, item.id])
		else:
			_check(theme.prop_sets.has(String(item.set)), "%s %d: set %s is in the map's list" % [theme.id, i, item.set])
		if data.blocks():
			var inst: int = item.inst if item.set != &"" else single_inst
			single_inst += 1
			var set = catalog.find_set(item.set) if item.set != &"" else null
			blockers.append({rect = data.footprint(item.pos), inst = inst, nook = set != null and set.place == PropSet.Place.WALL})
	_check(blockers.size() == layout.prop_rects.size(), "%s %d: one rect per blocking prop" % [theme.id, i])
	for n in blockers.size():
		var rect: Rect2 = blockers[n].rect
		_check(inner.encloses(rect), "%s %d: blocker %d is inside the room" % [theme.id, i, n])
		_check(not rect.intersects(start), "%s %d: blocker %d is off the start square" % [theme.id, i, n])
		var near_walls := 0
		for wall in layout.walls:
			_check(not rect.intersects(wall), "%s %d: blocker %d is clear of walls" % [theme.id, i, n])
			if _gap(rect, wall) < Layout.PROP_WALL_GAP - 0.01:
				near_walls += 1
		# A nook stands against one wall; everything else keeps the full gap.
		_check(near_walls <= (1 if blockers[n].nook else 0), "%s %d: blocker %d keeps %.0f px from walls" % [theme.id, i, n, Layout.PROP_WALL_GAP])
		for m in range(n + 1, blockers.size()):
			if blockers[m].inst != blockers[n].inst:
				_check(_gap(rect, blockers[m].rect) >= Layout.PROP_GAP - 0.01, "%s %d: blockers %d and %d keep apart" % [theme.id, i, n, m])
	# No sealed area: the free cells stay connected with the blockers in.
	var map = ObstacleMapScript.new()
	map.setup(layout.walls + layout.prop_rects, layout.pillars, SIZE, Builder.playable_rect(SIZE, BAND))
	var cols := int(SIZE.x / CELL)
	var rows := int(SIZE.y / CELL)
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for r in rows:
		for c in cols:
			blocked[r * cols + c] = 1 if FlowFieldScript.cell_blocked(map, Vector2i(c, r)) else 0
	map.free()
	var reach := _reach(blocked)
	_check(reach >= REACH, "%s %d: free area stays connected (%.3f)" % [theme.id, i, reach])


## Adding props and sets must leave everything else as it was: the same layout with none.
func _isolated(theme, layout, map_seed: int) -> void:
	var plain = theme.duplicate()
	plain.prop_count = 0
	plain.prop_sets = {}
	var base = Layout.generate(plain, map_seed, SIZE)
	_check(base.walls == layout.walls and base.pillars == layout.pillars and base.decor == layout.decor
		and base.torches == layout.torches, "%s: props move no wall, pillar, decor or torch (%d)" % [theme.id, map_seed])
	_check(base.props.is_empty() and base.prop_rects.is_empty(), "%s: no props and no sets places none" % theme.id)


func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0)
	var dy := maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)
	return Vector2(dx, dy).length()


func _reach(blocked: PackedByteArray) -> float:
	var cols := int(SIZE.x / CELL)
	var rows := int(SIZE.y / CELL)
	var free := 0
	for v in blocked:
		if v == 0:
			free += 1
	var seen := PackedByteArray()
	seen.resize(blocked.size())
	var first := int(SIZE.y / 2.0 / CELL) * cols + int(SIZE.x / 2.0 / CELL)
	var stack := PackedInt32Array([first])
	seen[first] = 1
	var count := 0
	while not stack.is_empty():
		var idx := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		count += 1
		var c := idx % cols
		var r := idx / cols
		for n in [idx - 1 if c > 0 else -1, idx + 1 if c < cols - 1 else -1, idx - cols if r > 0 else -1, idx + cols if r < rows - 1 else -1]:
			if n >= 0 and blocked[n] == 0 and seen[n] == 0:
				seen[n] = 1
				stack.append(n)
	return float(count) / float(maxi(free, 1))

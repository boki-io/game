extends SceneTree
## Sprite props (test-props): the catalog loads, every theme with props places them legally for 30 seeds (inside the room,
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
const PLACED_FLOOR := 0.8  # share of prop_count that must be placed

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


func _theme(theme) -> void:
	var catalog := Catalog.get_shared()
	var placed_min := 1.0
	for i in SEED_COUNT:
		var map_seed := hash("%d:%s" % [i, theme.id])
		var a = Layout.generate(theme, map_seed, SIZE)
		var b = Layout.generate(theme, map_seed, SIZE)
		_check(a.equals(b), "%s seed %d repeats" % [theme.id, i])
		placed_min = minf(placed_min, float(a.props.size()) / theme.prop_count)
		_legal(theme, a, catalog, i)
		_isolated(theme, a, map_seed)
	_check(placed_min >= PLACED_FLOOR, "%s places at least %.0f%% of its props (%.2f)" % [theme.id, PLACED_FLOOR * 100.0, placed_min])


func _legal(theme, layout, catalog, i: int) -> void:
	var start: Rect2 = Layout.start_rect(SIZE)
	var inner := Rect2(Vector2(BAND, BAND), SIZE - Vector2(BAND, BAND) * 2.0)
	_check(layout.prop_rects.size() <= layout.props.size(), "%s %d: blockers are props" % [theme.id, i])
	var blockers := 0
	for item in layout.props:
		var data = catalog.find(item.id)
		_check(data != null, "%s %d: prop %s is in the catalog" % [theme.id, i, item.id])
		_check(theme.prop_weights.has(String(data.group)), "%s %d: %s is of a weighted group" % [theme.id, i, item.id])
		if data.blocks():
			blockers += 1
	_check(blockers == layout.prop_rects.size(), "%s %d: one rect per blocking prop" % [theme.id, i])
	for n in layout.prop_rects.size():
		var rect: Rect2 = layout.prop_rects[n]
		_check(inner.encloses(rect), "%s %d: blocker %d is inside the room" % [theme.id, i, n])
		_check(not rect.intersects(start), "%s %d: blocker %d is off the start square" % [theme.id, i, n])
		for wall in layout.walls:
			_check(_gap(rect, wall) >= Layout.PROP_WALL_GAP - 0.01, "%s %d: blocker %d keeps %.0f px from a wall" % [theme.id, i, n, Layout.PROP_WALL_GAP])
		for m in range(n + 1, layout.prop_rects.size()):
			_check(_gap(rect, layout.prop_rects[m]) >= Layout.PROP_GAP - 0.01, "%s %d: blockers %d and %d keep apart" % [theme.id, i, n, m])
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
	_check(_reach(blocked) >= REACH, "%s %d: free area stays connected (%.3f)" % [theme.id, i, _reach(blocked)])


## Adding props must leave everything else as it was: the same layout with prop_count 0.
func _isolated(theme, layout, map_seed: int) -> void:
	var plain = theme.duplicate()
	plain.prop_count = 0
	var base = Layout.generate(plain, map_seed, SIZE)
	_check(base.walls == layout.walls and base.pillars == layout.pillars and base.decor == layout.decor
		and base.torches == layout.torches, "%s: props move no wall, pillar, decor or torch (%d)" % [theme.id, map_seed])
	_check(base.props.is_empty() and base.prop_rects.is_empty(), "%s: prop_count 0 places none" % theme.id)


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

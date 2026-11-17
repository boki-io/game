extends SceneTree
## The doubled run arena (3200x1792, Arena.RUN_SIZE): for each of the eight maps and a few seeds, the counts scale
## with the room (walls, pillars, decor, props by area, torches by perimeter), the placement rules of map_layout.gd
## still hold, no area is sealed off, and a layout generates in under a second. At 1600x896 every scale is 1.0.
## Run: godot --headless --path . --script tests/maps/map_large.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const Layout := preload("res://scripts/maps/map_layout.gd")
const ThemeScript := preload("res://scripts/maps/map_theme.gd")
const ObstacleMapScript := preload("res://scripts/maps/obstacle_map.gd")
const FlowFieldScript := preload("res://scripts/maps/flow_field.gd")
const Builder := preload("res://scripts/maps/map_builder.gd")

const SIZE := Vector2(3200, 1792)
const SEEDS := 5
const BAND := 16.0
const CELL := 16.0
const PLACED_FLOOR := 0.8
const REACH := 0.99
const MAX_SECONDS := 1.0
const PILLAR_OFFSET := Vector2(0, -6)
const PILLAR_RADIUS := 6.0

var _failed := false
var _fails_logged := 0
var _slowest := 0.0
var _min_share := 1.0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 25:
			print("FAIL: ", what)


func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0)
	var dy := maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)
	return Vector2(dx, dy).length()


func _reach(layout) -> float:
	var cols := int(SIZE.x / CELL)
	var rows := int(SIZE.y / CELL)
	var map = ObstacleMapScript.new()
	map.setup(layout.walls + layout.prop_rects, layout.pillars, SIZE, Builder.playable_rect(SIZE, BAND))
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	var free := 0
	for r in rows:
		for c in cols:
			var b := FlowFieldScript.cell_blocked(map, Vector2i(c, r))
			blocked[r * cols + c] = 1 if b else 0
			if not b:
				free += 1
	map.free()
	var seen := PackedByteArray()
	seen.resize(blocked.size())
	var start := int(SIZE.y / 2.0 / CELL) * cols + int(SIZE.x / 2.0 / CELL)
	var stack := PackedInt32Array([start])
	seen[start] = 1
	var count := 0
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		count += 1
		var c := i % cols
		var r := i / cols
		for n in [i - 1 if c > 0 else -1, i + 1 if c < cols - 1 else -1, i - cols if r > 0 else -1, i + cols if r < rows - 1 else -1]:
			if n >= 0 and blocked[n] == 0 and seen[n] == 0:
				seen[n] = 1
				stack.append(n)
	return float(count) / float(maxi(free, 1))


func _check_layout(theme, layout, tag: String) -> void:
	var k := Layout.area_scale(SIZE)
	var start := Layout.start_rect(SIZE)
	var edge := BAND + 56.0
	var walls: Array[Rect2] = layout.walls
	var wall_gap := 56.0 if theme.style == ThemeScript.Style.SCATTER else 40.0
	# Counts follow the area.
	var wanted_walls := roundi(theme.wall_count * k)
	var share := float(walls.size()) / float(maxi(wanted_walls, 1))
	_min_share = minf(_min_share, share)
	_check(share >= PLACED_FLOOR, tag + "only %d of %d walls placed" % [walls.size(), wanted_walls])
	_check(layout.pillars.size() >= roundi(theme.pillar_count * k) * PLACED_FLOOR, tag + "only %d pillars" % layout.pillars.size())
	_check(layout.decor.size() >= roundi(theme.decor_count * k) * 0.9, tag + "only %d decor pieces" % layout.decor.size())
	_check(layout.props.size() >= roundi(theme.prop_count * k) * PLACED_FLOOR, tag + "only %d props" % layout.props.size())
	_check(layout.torches.size() == Layout.torch_total(theme.torch_count, SIZE) and layout.torches.size() <= Layout.MAX_TORCHES,
		tag + "%d torches" % layout.torches.size())
	# Walls: start clearing, rock band margin, lengths, gaps.
	for rect in walls:
		_check(_rect_gap(rect, start) >= 24.0, tag + "wall %s is near the start square" % rect)
		_check(rect.position.x >= edge and rect.position.y >= edge and rect.end.x <= SIZE.x - edge and rect.end.y <= SIZE.y - edge,
			tag + "wall %s is outside the rock band margin" % rect)
		_check(theme.wall_lengths.has(maxf(rect.size.x, rect.size.y)) and minf(rect.size.x, rect.size.y) == 16.0, tag + "wall %s length" % rect)
	for a in walls.size():
		for b in range(a + 1, walls.size()):
			_check(_rect_gap(walls[a], walls[b]) >= wall_gap - 0.001, tag + "walls %s and %s are too close" % [walls[a], walls[b]])
	# Pillars (collider centre = base + (0, -6)).
	for a in layout.pillars.size():
		var c: Vector2 = layout.pillars[a] + PILLAR_OFFSET
		_check(c.distance_to(SIZE / 2.0) >= 60.0 and _rect_gap(Rect2(c, Vector2.ZERO), start) >= PILLAR_RADIUS, tag + "pillar %s near the centre" % c)
		_check(c.x >= BAND + 24.0 and c.y >= BAND + 24.0 and c.x <= SIZE.x - BAND - 24.0 and c.y <= SIZE.y - BAND - 24.0, tag + "pillar %s near the band" % c)
		for rect in walls:
			_check(Layout.point_rect_distance(c, rect) - PILLAR_RADIUS >= 40.0 - 0.001, tag + "pillar %s near wall %s" % [c, rect])
		for b in range(a + 1, layout.pillars.size()):
			_check(c.distance_to(layout.pillars[b] + PILLAR_OFFSET) - 2.0 * PILLAR_RADIUS >= 40.0 - 0.001, tag + "two pillars are too close")
	# Decor: off the start square, walls, pillars and the band.
	for item in layout.decor:
		var pos: Vector2 = item.pos
		_check(not start.has_point(pos), tag + "decor %s on the start square" % pos)
		_check(pos.x >= BAND + 8.0 and pos.y >= BAND + 8.0 and pos.x <= SIZE.x - BAND - 8.0 and pos.y <= SIZE.y - BAND - 8.0, tag + "decor %s on the band" % pos)
		for rect in walls:
			_check(not rect.has_point(pos), tag + "decor %s on a wall" % pos)
	# Torches stay out of the corners.
	for t: Vector2 in layout.torches:
		var horizontal_side := t.y < BAND or t.y > SIZE.y - BAND
		var along := t.x if horizontal_side else t.y
		var length := SIZE.x if horizontal_side else SIZE.y
		_check(along >= 40.0 and along <= length - 40.0, tag + "torch %s is in a corner" % t)
	# Blocking props keep out of the start square and the walls.
	for rect: Rect2 in layout.prop_rects:
		_check(not rect.intersects(start), tag + "prop footprint %s on the start square" % rect)
	_check(_reach(layout) >= REACH, tag + "an area is sealed off")


func _init() -> void:
	await process_frame
	await process_frame
	var ref := Vector2(1600, 896)
	_check(Layout.area_scale(ref) == 1.0 and Layout.perimeter_scale(ref) == 1.0, "the reference room scales by exactly 1")
	_check(Layout.area_scale(SIZE) == 4.0 and Layout.perimeter_scale(SIZE) == 2.0, "3200x1792 is 4x the area and 2x the perimeter")
	_check(Layout.torch_total(12, ref) == 12 and Layout.torch_total(12, SIZE) == 24 and Layout.torch_total(12, SIZE * 3.0) == Layout.MAX_TORCHES,
		"the torch count scales by perimeter, capped")
	_check(Arena.RUN_SIZE == Vector2i(SIZE), "the test size is the run arena")
	var themes := Registry.all()
	_check(themes.size() == 8, "eight maps")
	for theme in themes:
		for i in SEEDS:
			var map_seed := hash("%d:%s:large" % [i, theme.id])
			var t0 := Time.get_ticks_usec()
			var layout = Layout.generate(theme, map_seed, SIZE)
			var seconds := (Time.get_ticks_usec() - t0) / 1e6
			_slowest = maxf(_slowest, seconds)
			_check(seconds < MAX_SECONDS, "%s seed %d took %.2f s to generate" % [theme.id, i, seconds])
			var again = Layout.generate(theme, map_seed, SIZE)
			_check(again.walls == layout.walls and again.pillars == layout.pillars and again.decor == layout.decor, "%s seed %d repeats" % [theme.id, i])
			_check_layout(theme, layout, "%s seed %d: " % [theme.id, i])
	# The default theme (legacy layout) scales too.
	var default = Layout.generate(Registry.default(), 1, SIZE)
	_check(default.walls.size() >= 20 and default.torches.size() == 24, "the default theme fills the big room (%d walls, %d torches)" % [default.walls.size(), default.torches.size()])
	print("slowest layout %.3f s, least share of walls placed %.2f" % [_slowest, _min_share])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## Map layouts (spec 0.6 sections 6 and 12): the legacy layout equals today's arena, and for each of the eight maps and
## 30 seeds the rules of 6.2 hold (spawn clearing, rock band margin, wall gaps, pillar distances, obstacle budget,
## placement count, lengths, no sealed area, no narrow gap), the same seed repeats and decor and torches are legal.
## Run: godot --headless --path . --script tests/maps/map_layout.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const Layout := preload("res://scripts/maps/map_layout.gd")
const WallScript := preload("res://scripts/cave/cave_wall.gd")
const DecorScript := preload("res://scripts/cave/cave_decor.gd")
const ThemeScript := preload("res://scripts/maps/map_theme.gd")

const SEED_COUNT := 30
const SIZE := Vector2(1600, 896)
const BAND := 16.0
const PLACED_FLOOR := 0.8  # share of wall_count that must be placed
const CELL := 16.0  # the flow field's grid
const GROW := 8.0
const REACH := 0.99
const PILLAR_OFFSET := Vector2(0, -6)  # prop.gd: the collider is centred 6 px above the base
const PILLAR_RADIUS := 6.0

var _failed := false
var _fails_logged := 0
var _min_placed := {}  # theme id -> least share of walls placed
var _min_reach := {}


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 25:
			print("FAIL: ", what)


func _map_seed(theme, i: int) -> int:
	return hash("%d:%s" % [i, theme.id])


# --- Blocking, the FlowField rule -------------------------------------------------------------------------------------
# TODO: switch to FlowField.cell_blocked once it is merged (spec 6.6). Same rule written locally: a 16 px grid cell is
# blocked when its centre lies inside an obstacle grown by 8 px. The rock band is treated as blocked here too.

func _blocked_cells(layout) -> PackedByteArray:
	var cols := int(SIZE.x / CELL)
	var rows := int(SIZE.y / CELL)
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for r in rows:
		for c in cols:
			var centre := Vector2((c + 0.5) * CELL, (r + 0.5) * CELL)
			if centre.x < BAND or centre.y < BAND or centre.x > SIZE.x - BAND or centre.y > SIZE.y - BAND:
				blocked[r * cols + c] = 2  # rock band: not a free cell, not an obstacle
	for rect: Rect2 in layout.walls:
		_mark_rect(blocked, rect.grow(GROW), cols, rows)
	for base: Vector2 in layout.pillars:
		var circle_c := base + PILLAR_OFFSET
		var reach := PILLAR_RADIUS + GROW
		var c0 := maxi(int((circle_c.x - reach) / CELL), 0)
		var c1 := mini(int((circle_c.x + reach) / CELL), cols - 1)
		var r0 := maxi(int((circle_c.y - reach) / CELL), 0)
		var r1 := mini(int((circle_c.y + reach) / CELL), rows - 1)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				if Vector2((c + 0.5) * CELL, (r + 0.5) * CELL).distance_to(circle_c) <= reach:
					blocked[r * cols + c] = 1
	return blocked


func _mark_rect(blocked: PackedByteArray, rect: Rect2, cols: int, rows: int) -> void:
	var c0 := maxi(int(rect.position.x / CELL), 0)
	var c1 := mini(int(rect.end.x / CELL), cols - 1)
	var r0 := maxi(int(rect.position.y / CELL), 0)
	var r1 := mini(int(rect.end.y / CELL), rows - 1)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if rect.has_point(Vector2((c + 0.5) * CELL, (r + 0.5) * CELL)):
				blocked[r * cols + c] = 1


## Share of free cells reachable (4-connected) from the arena centre's cell.
func _reach(blocked: PackedByteArray) -> float:
	var cols := int(SIZE.x / CELL)
	var rows := int(SIZE.y / CELL)
	var free := 0
	for v in blocked:
		if v == 0:
			free += 1
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


## A free cell centre within 12 px of `p` (half a diagonal of a cell, 11.3, plus a little).
func _free_cell_near(blocked: PackedByteArray, p: Vector2) -> bool:
	var cols := int(SIZE.x / CELL)
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var c := int(p.x / CELL) + dc
			var r := int(p.y / CELL) + dr
			if c < 0 or r < 0 or c >= cols or r >= int(SIZE.y / CELL):
				continue
			if blocked[r * cols + c] == 0 and Vector2((c + 0.5) * CELL, (r + 0.5) * CELL).distance_to(p) <= 12.0:
				return true
	return false


# --- Geometry ----------------------------------------------------------------------------------------------------------

func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0)
	var dy := maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)
	return Vector2(dx, dy).length()


func _closest_on_rect(p: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))


## Closest points of two rectangles (a on rect a, b on rect b).
func _closest_pair(a: Rect2, b: Rect2) -> Array[Vector2]:
	var pa := Vector2(clampf((b.get_center().x), a.position.x, a.end.x), clampf(b.get_center().y, a.position.y, a.end.y))
	var pb := _closest_on_rect(pa, b)
	pa = _closest_on_rect(pb, a)
	return [pa, pb]


# --- Checks ---------------------------------------------------------------------------------------------------------------

func _legacy_matches_today() -> void:
	var theme = Registry.default()
	_check(theme.legacy_layout, "the default theme uses the legacy layout")
	var start := Rect2(SIZE / 2.0 - Vector2(110, 110), Vector2(220, 220))
	var walls := WallScript.layout(SIZE, BAND, [start])
	# main.gd _spawn_props, copied: the fixed seed 1 and its skips.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var pillars: Array[Vector2] = []
	for i in 8:
		var pos := Vector2(rng.randf_range(48.0, SIZE.x - 48.0), rng.randf_range(48.0, SIZE.y - 48.0))
		if pos.distance_to(SIZE / 2.0) < 60.0:
			continue
		var blocked := false
		for rect in walls:
			if rect.grow(16.0).has_point(pos):
				blocked = true
		if not blocked:
			pillars.append(pos)
	var reserved: Array[Rect2] = [start]
	reserved.append_array(walls)
	var decor := DecorScript.layout(SIZE, BAND, reserved, 110)
	for map_seed in [0, 1, 12345]:  # the seed is ignored
		var layout = Layout.generate(theme, map_seed, SIZE)
		_check(layout.walls == walls, "legacy walls equal CaveWall.layout (seed %d)" % map_seed)
		_check(layout.pillars == pillars, "legacy pillars equal main.gd's (seed %d)" % map_seed)
		_check(layout.decor == decor, "legacy decor equals CaveDecor.layout (seed %d)" % map_seed)
		_check(layout.walls.size() == 6 and layout.torches.size() == 12, "legacy has 6 walls and 12 torches")
	_check(Layout.generate(theme, 1, SIZE).torches[0] == Vector2(200.0, 9.0), "legacy torches are the hand-placed ones")


func _check_layout(theme, layout, tag: String, seed_index: int) -> void:
	var start := Rect2(SIZE / 2.0 - Vector2(110, 110), Vector2(220, 220))
	var edge := BAND + 56.0
	var walls: Array[Rect2] = layout.walls
	var wall_gap := 56.0 if theme.style == ThemeScript.Style.SCATTER else 40.0

	# Spawn clearing and rock band margin; lengths from the theme.
	for rect in walls:
		_check(_rect_gap(rect, start) >= 24.0, tag + "wall %s is within 24 px of the start square" % rect)
		_check(rect.position.x >= edge and rect.position.y >= edge and rect.end.x <= SIZE.x - edge and rect.end.y <= SIZE.y - edge,
			tag + "wall %s is inside the rock band margin" % rect)
		var length := maxf(rect.size.x, rect.size.y)
		_check(theme.wall_lengths.has(length) and minf(rect.size.x, rect.size.y) == 16.0,
			tag + "wall %s has a length not in wall_lengths" % rect)
	# Walls do not touch and keep the style's gap.
	for a in walls.size():
		for b in range(a + 1, walls.size()):
			_check(_rect_gap(walls[a], walls[b]) >= wall_gap - 0.001 and not walls[a].intersects(walls[b]),
				tag + "walls %s and %s are closer than %.0f px (%.1f)" % [walls[a], walls[b], wall_gap, _rect_gap(walls[a], walls[b])])
	# Obstacle budget and placement.
	_check(walls.size() + layout.pillars.size() <= 16, tag + "more than 16 obstacles")
	var share := float(walls.size()) / float(maxi(theme.wall_count, 1))
	_check(share >= PLACED_FLOOR, tag + "only %d of %d walls placed" % [walls.size(), theme.wall_count])
	_min_placed[theme.id] = minf(_min_placed.get(theme.id, 1.0), share)
	_check(layout.pillars.size() >= theme.pillar_count * PLACED_FLOOR, tag + "only %d of %d pillars placed" % [layout.pillars.size(), theme.pillar_count])
	# Pillars (collider centre = base + (0, -6)).
	for a in layout.pillars.size():
		var c: Vector2 = layout.pillars[a] + PILLAR_OFFSET
		_check(c.distance_to(SIZE / 2.0) >= 60.0, tag + "pillar %s is within 60 px of the centre" % c)
		_check(_rect_gap(Rect2(c, Vector2.ZERO), start) >= PILLAR_RADIUS, tag + "pillar %s touches the start square" % c)
		_check(c.x >= BAND + 24.0 and c.y >= BAND + 24.0 and c.x <= SIZE.x - BAND - 24.0 and c.y <= SIZE.y - BAND - 24.0,
			tag + "pillar %s is too near the rock band" % c)
		for rect in walls:
			_check(_closest_on_rect(c, rect).distance_to(c) - PILLAR_RADIUS >= 40.0 - 0.001, tag + "pillar %s is within 40 px of wall %s" % [c, rect])
		for b in range(a + 1, layout.pillars.size()):
			_check(c.distance_to(layout.pillars[b] + PILLAR_OFFSET) - 2.0 * PILLAR_RADIUS >= 40.0 - 0.001, tag + "pillars %s and %s are within 40 px" % [c, layout.pillars[b]])
	# Decor: legal kinds, clear of the start square, walls, pillars; 8 px from the rock band.
	_check(layout.decor.size() >= theme.decor_count * 0.9, tag + "only %d of %d decor pieces placed" % [layout.decor.size(), theme.decor_count])
	for item in layout.decor:
		var pos: Vector2 = item.pos
		_check(theme.decor_weights.has(item.kind) and theme.decor_weights[item.kind] > 0.0, tag + "decor kind %d has no weight" % item.kind)
		_check(not start.has_point(pos), tag + "decor %s is on the start square" % pos)
		_check(pos.x >= BAND + 8.0 and pos.y >= BAND + 8.0 and pos.x <= SIZE.x - BAND - 8.0 and pos.y <= SIZE.y - BAND - 8.0, tag + "decor %s is on the rock band" % pos)
		for rect in walls:
			_check(not rect.has_point(pos), tag + "decor %s is on a wall" % pos)
		for base: Vector2 in layout.pillars:
			_check(pos.distance_to(base + PILLAR_OFFSET) > PILLAR_RADIUS, tag + "decor %s is on a pillar" % pos)
	# Torches: the count, never in a corner, on the band.
	_check(layout.torches.size() == theme.torch_count, tag + "%d torches, wanted %d" % [layout.torches.size(), theme.torch_count])
	for t: Vector2 in layout.torches:
		var along := t.x if t.y < BAND or t.y > SIZE.y - BAND else t.y
		var length := SIZE.x if t.y < BAND or t.y > SIZE.y - BAND else SIZE.y
		_check(along >= 40.0 and along <= length - 40.0, tag + "torch %s is in a corner" % t)

	# No sealed area, and a free cell across every gap.
	var blocked := _blocked_cells(layout)
	var reach := _reach(blocked)
	_min_reach[theme.id] = minf(_min_reach.get(theme.id, 1.0), reach)
	_check(reach >= REACH, tag + "only %.1f%% of the free cells are reachable" % (reach * 100.0))
	var shapes: Array = []  # [rect or circle centre]
	for rect in walls:
		shapes.append(rect)
	for base: Vector2 in layout.pillars:
		var c := base + PILLAR_OFFSET
		shapes.append(Rect2(c - Vector2(PILLAR_RADIUS, PILLAR_RADIUS), Vector2(PILLAR_RADIUS, PILLAR_RADIUS) * 2.0))  # a pillar by its square
	for a in shapes.size():
		for b in range(a + 1, shapes.size()):
			if _rect_gap(shapes[a], shapes[b]) < 80.0:
				var pair := _closest_pair(shapes[a], shapes[b])
				_check(_free_cell_near(blocked, (pair[0] + pair[1]) / 2.0), tag + "no free cell across the gap near %s" % ((pair[0] + pair[1]) / 2.0))


func _init() -> void:
	await process_frame
	_legacy_matches_today()
	var themes: Array = Registry.all()
	_check(themes.size() == 8, "eight maps")
	var started := Time.get_ticks_msec()
	for theme in themes:
		var tag := "%s: " % theme.id
		var seen := {}
		for i in SEED_COUNT:
			var map_seed := _map_seed(theme, i)
			var layout = Layout.generate(theme, map_seed, SIZE)
			_check_layout(theme, layout, tag + "seed %d: " % i, i)
			_check(layout.equals(Layout.generate(theme, map_seed, SIZE)), tag + "seed %d does not reproduce" % i)
			seen[str(layout.walls) + str(layout.pillars)] = true
		_check(seen.size() >= SEED_COUNT - 1, tag + "different seeds give the same layout (%d distinct of %d)" % [seen.size(), SEED_COUNT])
		print("%s: least walls placed %.0f%%, least reach %.2f%%" % [theme.id, _min_placed[theme.id] * 100.0, _min_reach[theme.id] * 100.0])
	print("layouts checked in %d ms" % (Time.get_ticks_msec() - started))
	print("FAIL: see above" if _failed else "PASS")
	quit(1 if _failed else 0)

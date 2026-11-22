extends SceneTree
## WorldObstacles (spec 1.8, section 6) on the real world mask near zone 0's start: the queries agree with the walkable
## mask on sampled tiles, a push out leaves a clear circle, a segment across a wall is not clear, the flow field leads
## 30 chosen starts around walls to the target, and a window rebuild stays within the per-frame budget.
## Also prints the measured cost per call.
## Run: godot --headless --path . --script tests/overworld/world_obstacles.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const WorldObstaclesS := preload("res://scripts/overworld/world_obstacles.gd")

const CENTER := Vector2i(51, 1936)  # zone 0's start area
const SPAN := 60  # tiles around CENTER that are sampled
const SEED_COUNT := 30

var _failed := false
var _world
var _map
var _src := Vector2.ZERO  # what the maps' player_source returns (a lambda copies locals)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_world = WorldDataS.shared()
	_map = WorldObstaclesS.new()
	_map.setup_world(_world)
	_check(_map.has_obstacles(), "has_obstacles is true")
	_check(_map.wall_rects().is_empty() and _map.pillar_centers().is_empty() and _map.flow() == null, "arena shapes are empty")
	_blocked_agrees()
	_push_out()
	_segments()
	_ray()
	_flow()
	_budget()
	_costs()
	_map.free()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _solid(t: Vector2i) -> bool:
	return not _world.is_walkable(t)


func _tile_centre(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * 16.0


## Tiles near the start that are walls with a walkable neighbour (a wall face), and walkable tiles.
func _faces() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(CENTER.y - SPAN, CENTER.y + SPAN):
		for x in range(CENTER.x - SPAN, CENTER.x + SPAN):
			var t := Vector2i(x, y)
			if _solid(t) and _world.is_walkable(t + Vector2i(1, 0)):
				out.append(t)
	return out


func _blocked_agrees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var solid := 0
	var open := 0
	for i in 3000:
		var t := Vector2i(CENTER.x + rng.randi_range(-SPAN, SPAN), CENTER.y + rng.randi_range(-SPAN, SPAN))
		var c := _tile_centre(t)
		if _solid(t):
			solid += 1
			_check(_map.blocked(c, 6.0), "the centre of wall tile %s is blocked" % t)
		else:
			open += 1
			# A point is blocked exactly when a circle touches some solid tile: brute force over the 3 x 3 block.
			var p := c + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			var r := rng.randf_range(2.0, 16.0)
			var expect := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var n := t + Vector2i(dx, dy)
					if _solid(n):
						var rect := Rect2(Vector2(n) * 16.0, Vector2(16, 16))
						var near := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
						if p.distance_to(near) < r:
							expect = true
			_check(_map.blocked(p, r) == expect, "blocked(%s, %.1f) agrees with the tile mask" % [p, r])
	_check(solid > 100 and open > 100, "the sample holds walls and floor (%d, %d)" % [solid, open])
	# Outside the world is blocked.
	_check(_map.blocked(Vector2(-4, 100), 6.0) and _map.blocked(Vector2(100, 32010), 6.0), "outside the world is blocked")
	# A wall face: just inside the face is blocked, a radius away is not.
	var faces := _faces()
	_check(faces.size() > 50, "there are wall faces near the start (%d)" % faces.size())
	for k in 40:
		var f: Vector2i = faces[(k * 37) % faces.size()]
		var edge_x := (f.x + 1) * 16.0
		var y := (f.y + 0.5) * 16.0
		_check(_map.blocked(Vector2(edge_x + 3.0, y), 6.0), "a circle 3 px off a wall face (tile %s) is blocked" % f)
		_check(not _map.blocked(Vector2(edge_x + 7.0, y), 6.0) or _solid(f + Vector2i(1, 0)) or _solid(f + Vector2i(1, -1)) or _solid(f + Vector2i(1, 1)) or _solid(f + Vector2i(0, -1)) or _solid(f + Vector2i(0, 1)), "a circle 7 px off a wall face (tile %s) is clear" % f)


func _push_out() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pushed := 0
	for i in 2000:
		var p := (Vector2(CENTER) + Vector2(rng.randf_range(-SPAN, SPAN), rng.randf_range(-SPAN, SPAN))) * 16.0
		var r: float = [6.0, 8.0, 12.0, 16.0][i % 4]
		if not _shallow(p):
			continue  # deep inside the rock (or outside the world) nothing can be, and the push is not meant to reach out
		var q: Vector2 = _map.push_out(p, r)
		_check(not _map.blocked(q, r), "push_out(%s, %.0f) = %s is clear" % [p, r, q])
		if _map.blocked(p, r):
			pushed += 1
			_check(p.distance_to(q) < 72.0, "push_out moves %s by less than 72 px" % p)
		else:
			_check(q == p, "push_out leaves a clear position alone")
	_check(pushed > 100, "the push_out sample includes blocked points (%d)" % pushed)


## True when a walkable tile is within one tile of the tile at `p` (a position an enemy could be pushed into).
func _shallow(p: Vector2) -> bool:
	var t := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _world.is_walkable(t + Vector2i(dx, dy)):
				return true
	return false


func _segments() -> void:
	var faces := _faces()
	var crossed := 0
	for k in 40:
		var f: Vector2i = faces[(k * 53) % faces.size()]
		# From the floor east of a wall face to a point three tiles inside the wall.
		var a := _tile_centre(f + Vector2i(1, 0))
		var b := _tile_centre(f - Vector2i(2, 0))
		if _solid(f - Vector2i(2, 0)) and not _map.blocked(a, 6.0):
			_check(not _map.segment_clear(a, b, 6.0), "segment into the wall at %s is not clear" % f)
			crossed += 1
	_check(crossed >= 20, "enough wall entries were tried (%d)" % crossed)
	# Across the rock: floor, then wall, then floor again along a column or a row.
	var across := 0
	for x in range(CENTER.x, CENTER.x + 260, 4):
		var y0 := CENTER.y - 100
		var seen_wall := false
		var start := Vector2i(-1, -1)
		for y in range(y0, CENTER.y + 60):
			var t := Vector2i(x, y)
			if _solid(t):
				seen_wall = start.x >= 0
			elif seen_wall and start.x >= 0:
				_check(not _map.segment_clear(_tile_centre(start), _tile_centre(t), 6.0), "segment across the rock at column %d is not clear" % x)
				across += 1
				break
			elif not seen_wall:
				start = t
	_check(across >= 5, "rock crossings were tried (%d)" % across)
	# A clear straight segment on open floor: walk a row of walkable tiles.
	var clear_found := 0
	for y in range(CENTER.y - SPAN, CENTER.y + SPAN):
		var run := 0
		for x in range(CENTER.x - SPAN, CENTER.x + SPAN):
			var t := Vector2i(x, y)
			var open: bool = _world.is_walkable(t) and _world.is_walkable(t + Vector2i(0, 1)) and _world.is_walkable(t + Vector2i(0, -1))
			run = run + 1 if open else 0
			if run == 12:
				_check(_map.segment_clear(_tile_centre(t - Vector2i(11, 0)), _tile_centre(t), 6.0), "a clear row at %s is clear" % t)
				clear_found += 1
				run = 0
	_check(clear_found > 5, "clear rows were found (%d)" % clear_found)
	_check(_map.segment_clear(Vector2(100, 100), Vector2(100, 100), 0.0) == not _map.blocked(Vector2(100, 100), 0.0), "a zero-length segment matches blocked")


func _ray() -> void:
	var faces := _faces()
	for k in 30:
		var f: Vector2i = faces[(k * 29) % faces.size()]
		var from := _tile_centre(f + Vector2i(1, 0))
		if _map.blocked(from, 6.0):
			continue
		var d: float = _map.ray_distance(from, Vector2.LEFT, 80.0, 6.0)
		# The circle of radius 6 touches the face x = (f.x + 1) * 16 when its centre is 6 px from it.
		var expect := 8.0 - 6.0
		_check(absf(d - expect) < 3.0 or d < 80.0, "ray towards the wall at %s stops (%.1f)" % [f, d])
		_check(not _map.blocked(from + Vector2.LEFT * d, 6.0), "the ray's end at %s is clear" % f)
		_check(_map.ray_distance(from, Vector2.RIGHT, 0.0, 6.0) == 0.0, "a zero-length ray is zero")


## Builds the field of `map` around `pos` (a rebuild is due when the interval has passed).
func _build(map, pos: Vector2) -> void:
	_src = pos
	map.player_source = func() -> Vector2: return _src
	map._physics_process(0.3)
	for i in 12:
		map._physics_process(1.0 / 60.0)


## Starts 18 to 44 tiles from a target with a wall in the way: following the flow field reaches the target. The target
## is the first candidate within a few hundred tiles of zone 0's start (the path bends around the rock there) that has 30 such starts.
func _flow() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	var map = WorldObstaclesS.new()
	map.setup_world(_world)
	var starts: Array[Vector2] = []
	var tpos := Vector2.ZERO
	var candidates: Array[Vector2i] = []
	for y in range(CENTER.y - 90, CENTER.y + 50, 8):
		for x in range(CENTER.x, CENTER.x + 230, 8):
			candidates.append(Vector2i(x, y))
	for target in candidates:
		if _solid(target):
			continue
		tpos = _tile_centre(target)
		_build(map, tpos)
		starts.clear()
		for k in 6000:
			var t := target + Vector2i(rng.randi_range(-44, 44), rng.randi_range(-44, 44))
			var dist := Vector2(t - target).length()
			if dist < 18.0 or dist > 44.0 or _solid(t):
				continue
			var s := _tile_centre(t)
			var walk: int = map.distance_at(s)
			if _map.segment_clear(s, tpos, 6.0) or walk < 0 or walk < 1.5 * (absi(t.x - target.x) + absi(t.y - target.y)):
				continue  # only starts with a wall in the way, reachable, and a real detour (walk 1.5x the Manhattan distance)
			starts.append(s)
			if starts.size() == SEED_COUNT:
				break
		if starts.size() == SEED_COUNT:
			break
	_check(starts.size() == SEED_COUNT, "30 starts behind walls were found (%d)" % starts.size())
	_check(map.has_field() and map.distance_at(tpos) == 0, "the target cell has distance 0")
	_check(map.flow_direction(Vector2(-100, -100)) == Vector2.ZERO, "outside the window gives zero")
	var reached := 0
	var detour := 0
	for s in starts:
		var p := s
		var steps := 0
		while steps < 400 and p.distance_to(tpos) > 20.0:
			var dir: Vector2 = map.flow_direction(p)
			if dir == Vector2.ZERO:
				break
			p = _map.push_out(p + dir * 8.0, 6.0)
			steps += 1
		if p.distance_to(tpos) <= 20.0:
			reached += 1
			if steps * 8.0 > s.distance_to(tpos) * 1.2:
				detour += 1
		else:
			print("  start ", s, " stopped at ", p, " after ", steps, " steps")
	_check(reached == SEED_COUNT, "the flow reaches the target from all starts (%d of %d)" % [reached, SEED_COUNT])
	_check(detour >= 25, "the walks go around walls, not straight (%d detours)" % detour)
	map.free()


## A rebuild spreads over frames of at most SEARCH_BUDGET expansions, and starts no more often than SEARCH_INTERVAL.
func _budget() -> void:
	var map = WorldObstaclesS.new()
	map.setup_world(_world)
	_src = _tile_centre(CENTER)
	map.player_source = func() -> Vector2: return _src
	var frames := 0
	var total := 0
	while not map.has_field() and frames < 40:
		map._physics_process(1.0 / 60.0)
		total += map.frame_expansions
		frames += 1
	_check(map.max_frame_expansions <= WorldObstaclesS.SEARCH_BUDGET, "a frame expands at most %d cells (%d)" % [WorldObstaclesS.SEARCH_BUDGET, map.max_frame_expansions])
	_check(frames >= 2 and frames <= 12, "a rebuild takes a few frames (%d)" % frames)
	_check(total <= WorldObstaclesS.WINDOW * WorldObstaclesS.WINDOW, "a rebuild expands at most the window (%d)" % total)
	# Moving a tile at once does not start a second search before the interval; after it, it does.
	var started: int = map.searches_started
	_src += Vector2(16, 0)
	map._physics_process(0.016)
	_check(map.searches_started == started, "no new search inside the interval")
	map._physics_process(0.3)
	_check(map.searches_started == started + 1, "a new search starts after the interval")
	for i in 12:
		map._physics_process(1.0 / 60.0)
	_check(map.max_frame_expansions <= WorldObstaclesS.SEARCH_BUDGET, "the budget holds over the second rebuild")
	map.free()


func _costs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts: Array[Vector2] = []
	for i in 2000:
		var q := (Vector2(CENTER) + Vector2(rng.randf_range(-SPAN, SPAN), rng.randf_range(-SPAN, SPAN))) * 16.0
		if _shallow(q):  # positions an enemy could be at: floor, or a push away from it
			pts.append(q)
	var n := pts.size()
	var t0 := Time.get_ticks_usec()
	for p in pts:
		_map.blocked(p, 8.0)
	var t1 := Time.get_ticks_usec()
	for p in pts:
		_map.push_out(p, 8.0)
	var t2 := Time.get_ticks_usec()
	for i in n - 1:
		_map.segment_clear(pts[i], pts[i] + Vector2(150, 0), 8.0)
	var t3 := Time.get_ticks_usec()
	var map = WorldObstaclesS.new()
	map.setup_world(_world)
	_src = pts[0]
	map.player_source = func() -> Vector2: return _src
	var r0 := Time.get_ticks_usec()
	var frames := 0
	while not map.has_field() and frames < 40:
		map._physics_process(1.0 / 60.0)
		frames += 1
	var r1 := Time.get_ticks_usec()
	map.free()
	print("cost: blocked %.2f us, push_out %.2f us, segment_clear(150 px) %.2f us, window rebuild %.2f ms over %d frames" % [
		float(t1 - t0) / n, float(t2 - t1) / n, float(t3 - t2) / (n - 1), float(r1 - r0) / 1000.0, frames])

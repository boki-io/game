class_name WorldObstacles
extends ObstacleMap
## The overworld's navigation (spec 1.8, section 6). The arena's ObstacleMap holds wall rectangles and a flow field over
## the whole arena; a 32,000 px world is too big for that, so this one answers the same queries from the world's
## walkable mask (`WorldData.collision`, walkable > 127, blocked otherwise, outside the world blocked) and keeps a local
## breadth-first flow field in a window of 96 x 96 tiles around the player. `setup()` is never called.
## Queries take a circle radius up to 16 px, so they read at most 4 x 4 tiles.

const TILE := 16
const WORLD_SIZE := WorldData.SIZE
const WINDOW := 96  # flow-field window, in tiles per side
const RING_REACH := 64.0  # push_out's fallback ring search reaches this far
const SAMPLE_STEP := 8.0  # segment_clear and ray_distance sample every 8 px

## The nearest player's world position, or Vector2.INF when there is none. When unset, the first living Player in
## `PlayerRegistry` is used.
var player_source := Callable()

var _collision := PackedByteArray()
var _no_rects: Array[Rect2] = []
var _no_centers := PackedVector2Array()

var _dist := PackedInt32Array()  # the live field (window cells): walking distance in tiles, -1 where unreached
var _building := PackedInt32Array()
var _queue := PackedInt32Array()
var _head := 0
var _queue_size := 0
var _origin := Vector2i.ZERO  # tile of the live window's top-left cell
var _building_origin := Vector2i.ZERO
var _field_ready := false
var _searching := false
var _last_tile := Vector2i(-1000000, -1000000)
var _since_rebuild := SEARCH_INTERVAL


## Reads the walkable mask of `world`; the window buffers are allocated here, once.
func setup_world(world: WorldData) -> void:
	_collision = world.collision
	_dist.resize(WINDOW * WINDOW)
	_dist.fill(-1)
	_building.resize(WINDOW * WINDOW)
	_queue.resize(WINDOW * WINDOW)
	size = Vector2(WORLD_SIZE * TILE, WORLD_SIZE * TILE)
	bounds = Rect2(Vector2.ZERO, size)
	_field_ready = false
	_searching = false
	_last_tile = Vector2i(-1000000, -1000000)
	_since_rebuild = SEARCH_INTERVAL


func has_obstacles() -> bool:
	return true


func wall_rects() -> Array[Rect2]:
	return _no_rects


func pillar_centers() -> PackedVector2Array:
	return _no_centers


## There is no arena-wide FlowField here.
func flow() -> FlowField:
	return null


## Whether the live window field has been built at least once.
func has_field() -> bool:
	return _field_ready


## Walking distance in tiles from the live field's source, or -1 outside the window or where unreached.
func distance_at(pos: Vector2) -> int:
	var i := _window_index(Vector2i(floori(pos.x / TILE), floori(pos.y / TILE)), _origin)
	return _dist[i] if i >= 0 and _field_ready else -1


func _solid(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= WORLD_SIZE or ty >= WORLD_SIZE:
		return true
	return _collision[ty * WORLD_SIZE + tx] <= 127


## True when a circle of `radius` at `pos` overlaps a non-walkable tile.
func blocked(pos: Vector2, radius: float) -> bool:
	var r2 := radius * radius
	var tx1 := floori((pos.x + radius) / TILE)
	var ty1 := floori((pos.y + radius) / TILE)
	for ty in range(floori((pos.y - radius) / TILE), ty1 + 1):
		for tx in range(floori((pos.x - radius) / TILE), tx1 + 1):
			if _solid(tx, ty):
				var dx := pos.x - clampf(pos.x, tx * TILE, tx * TILE + TILE)
				var dy := pos.y - clampf(pos.y, ty * TILE, ty * TILE + TILE)
				if dx * dx + dy * dy < r2:
					return true
	return false


## The nearest position where a circle of `radius` overlaps no wall (`pos` itself when it is already clear): up to 4
## passes of shortest-axis pushes out of the tiles it overlaps, then a ring search if that left it blocked or far away.
func push_out(pos: Vector2, radius: float) -> Vector2:
	var p := pos
	for pass_i in 4:
		var moved := false
		var tx1 := floori((p.x + radius) / TILE)
		var ty1 := floori((p.y + radius) / TILE)
		for ty in range(floori((p.y - radius) / TILE), ty1 + 1):
			for tx in range(floori((p.x - radius) / TILE), tx1 + 1):
				if _solid(tx, ty):
					var push := _tile_push(tx, ty, p, radius)
					if push != Vector2.ZERO:
						p += push
						moved = true
		if not moved:
			return p
	if not blocked(p, radius) and p.distance_squared_to(pos) < RING_REACH * RING_REACH:
		return p
	# Rare: a pocket of walls, where the pushes chained into more wall. Take the nearest clear spot on growing rings.
	for ring in range(1, int(RING_REACH / 4.0) + 1):
		var d := ring * 4.0
		for k in 24:
			var q := pos + Vector2.from_angle(k * TAU / 24.0) * d
			if not blocked(q, radius):
				return q
	return p


func _tile_push(tx: int, ty: int, p: Vector2, radius: float) -> Vector2:
	var x0 := float(tx * TILE)
	var y0 := float(ty * TILE)
	var dx := p.x - clampf(p.x, x0, x0 + TILE)
	var dy := p.y - clampf(p.y, y0, y0 + TILE)
	var dl := sqrt(dx * dx + dy * dy)
	if dl > 0.0:
		return Vector2(dx, dy) / dl * (radius - dl + 0.001) if dl < radius else Vector2.ZERO
	# The centre is inside the tile: leave by the nearest edge.
	var to_left := p.x - x0
	var to_right := x0 + TILE - p.x
	var to_top := p.y - y0
	var to_bottom := y0 + TILE - p.y
	var m := minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if m == to_left:
		return Vector2(-(to_left + radius + 0.001), 0)
	if m == to_right:
		return Vector2(to_right + radius + 0.001, 0)
	if m == to_top:
		return Vector2(0, -(to_top + radius + 0.001))
	return Vector2(0, to_bottom + radius + 0.001)


## Whether a circle of `radius` swept from `a` to `b` touches no wall (samples every 8 px, both ends included).
func segment_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	var length := a.distance_to(b)
	var steps := maxi(ceili(length / SAMPLE_STEP), 1)
	for s in steps + 1:
		if blocked(a.lerp(b, float(s) / steps), radius):
			return false
	return true


## How far a circle of `radius` can travel from `from` along the unit vector `dir` before it touches a wall, at most
## `max_len`: the first blocked sample (every 8 px), refined by bisection. Starting inside a wall it is blocked only
## when heading further in (the arena's rule), so a push out can walk away.
func ray_distance(from: Vector2, dir: Vector2, max_len: float, radius: float) -> float:
	if blocked(from, radius):
		return 0.0 if blocked(from + dir * SAMPLE_STEP, radius) else max_len
	var steps := maxi(ceili(max_len / SAMPLE_STEP), 1)
	var prev := 0.0
	for s in range(1, steps + 1):
		var t := minf(s * SAMPLE_STEP, max_len)
		if blocked(from + dir * t, radius):
			var lo := prev
			var hi := t
			for k in 3:
				var mid := (lo + hi) * 0.5
				if blocked(from + dir * mid, radius):
					hi = mid
				else:
					lo = mid
			return lo
		prev = t
	return max_len


## Unit vector towards the lowest neighbouring cell of the window field (no corner cutting), or ZERO outside the window,
## before the first field, or where nothing is better.
func flow_direction(pos: Vector2) -> Vector2:
	if not _field_ready:
		return Vector2.ZERO
	var cx := floori(pos.x / TILE)
	var cy := floori(pos.y / TILE)
	var lx := cx - _origin.x
	var ly := cy - _origin.y
	if lx < 0 or ly < 0 or lx >= WINDOW or ly >= WINDOW:
		return Vector2.ZERO
	var here := _dist[ly * WINDOW + lx]
	var best := here if here >= 0 else 1 << 30
	var bx := 0
	var by := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := lx + dx
			var ny := ly + dy
			if nx < 0 or ny < 0 or nx >= WINDOW or ny >= WINDOW:
				continue
			var nd := _dist[ny * WINDOW + nx]
			if nd < 0 or nd >= best:
				continue
			if dx != 0 and dy != 0 and (_solid(cx + dx, cy) or _solid(cx, cy + dy)):
				continue
			best = nd
			bx = dx
			by = dy
	return Vector2(bx, by).normalized() if bx != 0 or by != 0 else Vector2.ZERO


func _physics_process(delta: float) -> void:
	if _collision.is_empty():
		return
	_since_rebuild += delta
	frame_expansions = 0
	if _searching:
		frame_expansions = _step(SEARCH_BUDGET)
	elif _since_rebuild >= SEARCH_INTERVAL:
		var pos := _player_position()
		if pos != Vector2.INF:
			var tile := Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
			if tile != _last_tile:
				_last_tile = tile
				_since_rebuild = 0.0
				searches_started += 1
				_begin(tile)
				frame_expansions = _step(SEARCH_BUDGET)
	max_frame_expansions = maxi(max_frame_expansions, frame_expansions)


func _player_position() -> Vector2:
	if player_source.is_valid():
		return player_source.call()
	# Looked up by path so this script compiles without the autoloads (pure-logic tests preload it).
	var registry := get_node_or_null("/root/PlayerRegistry") if is_inside_tree() else null
	for p in (registry.players if registry else []):
		if not p.dead:
			return p.global_position
	return Vector2.INF


func _window_index(tile: Vector2i, origin: Vector2i) -> int:
	var lx := tile.x - origin.x
	var ly := tile.y - origin.y
	if lx < 0 or ly < 0 or lx >= WINDOW or ly >= WINDOW:
		return -1
	return ly * WINDOW + lx


func _begin(tile: Vector2i) -> void:
	_building_origin = tile - Vector2i(WINDOW / 2, WINDOW / 2)
	_building.fill(-1)
	_head = 0
	var src := _window_index(tile, _building_origin)
	_building[src] = 0  # the source counts as free even when the player stands in a wall tile
	_queue[0] = src
	_queue_size = 1
	_searching = true


## Runs up to `budget` cell expansions of the current search; returns how many it did. The finished field replaces the
## live one in one go.
func _step(budget: int) -> int:
	var done := 0
	var ox := _building_origin.x
	var oy := _building_origin.y
	while _head < _queue_size and done < budget:
		var c := _queue[_head]
		_head += 1
		done += 1
		var d := _building[c] + 1
		var x := c % WINDOW
		var y := c / WINDOW
		if x > 0:
			_visit(c - 1, d, ox + x - 1, oy + y)
		if x < WINDOW - 1:
			_visit(c + 1, d, ox + x + 1, oy + y)
		if y > 0:
			_visit(c - WINDOW, d, ox + x, oy + y - 1)
		if y < WINDOW - 1:
			_visit(c + WINDOW, d, ox + x, oy + y + 1)
	if _head >= _queue_size:
		var finished := _building
		_building = _dist
		_dist = finished
		_origin = _building_origin
		_searching = false
		_field_ready = true
	return done


func _visit(index: int, d: int, tx: int, ty: int) -> void:
	if _building[index] != -1 or _solid(tx, ty):
		return
	_building[index] = d
	_queue[_queue_size] = index
	_queue_size += 1

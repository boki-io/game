class_name ObstacleMap
extends Node
## The solid things enemies must not walk through: the freestanding rock walls (rectangles) and the pillars
## (circles). Pure geometry plus a thin node: `setup()` and the queries work on an instance that is not in the
## tree (tests do that); in the tree it also keeps the FlowField fresh from the living Players' positions.
## Enemies are plain Node2Ds, so blocking is done here, not by the physics engine (spec 0.6, section 6.6).

const CELL := 64.0  # spatial grid cell
const INFLATE := 32.0  # a shape is listed in every cell within this distance; queries may use radius up to 16
const PILLAR_OFFSET := Vector2(0, -6)  # a pillar's collider sits 6 px above its base (prop.gd)
const PILLAR_RADIUS := 6.0
const SEARCH_BUDGET := 1000  # flow-field cell expansions per physics frame
const SEARCH_INTERVAL := 0.25  # at least this long between two search starts

## The area enemies can occupy (inside the rock band); the flow field treats cells outside it as blocked.
var bounds := Rect2()
var size := Vector2.ZERO

## Flow-field bookkeeping, read by tests.
var searches_started := 0
var frame_expansions := 0
var max_frame_expansions := 0

var _rects: Array[Rect2] = []
var _centers := PackedVector2Array()  # pillar circle centres (base + offset)
var _grid: Array[PackedInt32Array] = []  # cell -> shape indexes (rects first, then circles)
var _gw := 0
var _gh := 0
var _stamp := PackedInt32Array()
var _stamp_id := 0
var _flow: FlowField
var _last_sources: Array[Vector2i] = []
var _since_start := SEARCH_INTERVAL  # the first search may start at once


## The ObstacleMap of the scene `node` is in, or null (the hub has none).
static func get_for(node: Node) -> ObstacleMap:
	return node.get_tree().get_first_node_in_group(&"obstacles") as ObstacleMap


## `walls` are the CaveWall footprints, `pillars` the Prop base positions, `arena` the arena size in px.
## `playable` (optional) is the region enemies can stand in; default the whole arena.
func setup(walls: Array[Rect2], pillars: Array[Vector2], arena: Vector2, playable := Rect2()) -> void:
	size = arena
	bounds = playable if playable.size != Vector2.ZERO else Rect2(Vector2.ZERO, arena)
	_rects = walls.duplicate()
	_centers = PackedVector2Array()
	for p in pillars:
		_centers.append(p + PILLAR_OFFSET)
	_gw = ceili(arena.x / CELL)
	_gh = ceili(arena.y / CELL)
	_grid = []
	for i in _gw * _gh:
		_grid.append(PackedInt32Array())
	var n := _rects.size()
	_stamp = PackedInt32Array()
	_stamp.resize(n + _centers.size())
	for i in n:
		_list_shape(i, _rects[i].grow(INFLATE))
	for j in _centers.size():
		var c := _centers[j]
		_list_shape(n + j, Rect2(c, Vector2.ZERO).grow(PILLAR_RADIUS + INFLATE))
	if has_obstacles():
		_flow = FlowField.new()
		_flow.setup(self)


func _ready() -> void:
	add_to_group(&"obstacles")


func has_obstacles() -> bool:
	return not _rects.is_empty() or not _centers.is_empty()


func wall_rects() -> Array[Rect2]:
	return _rects


## Circle centres (already offset) of the pillars.
func pillar_centers() -> PackedVector2Array:
	return _centers


## True when a circle of `radius` at `pos` overlaps an obstacle. `radius` is at most 16.
func blocked(pos: Vector2, radius: float) -> bool:
	var cell := _cell_index(pos)
	if cell < 0:
		return false
	for i in _grid[cell]:
		if _push(i, pos, radius) != Vector2.ZERO:
			return true
	return false


## The nearest position where a circle of `radius` overlaps no obstacle (`pos` itself when it is already clear).
func push_out(pos: Vector2, radius: float) -> Vector2:
	var cell := _cell_index(pos)
	if cell < 0:
		return pos
	var list := _grid[cell]
	if list.is_empty():
		return pos
	var p := pos
	for pass_i in 3:  # a push out of one shape can touch the next
		var moved := false
		for i in list:
			var push := _push(i, p, radius)
			if push != Vector2.ZERO:
				p += push
				moved = true
		if not moved:
			break
	return p


## Whether a circle of `radius` swept from `a` to `b` touches no obstacle.
func segment_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	if not has_obstacles():
		return true
	_stamp_id += 1
	var length := a.distance_to(b)
	var steps := maxi(ceili(length / (INFLATE / 2.0)), 1)
	for s in steps + 1:
		var cell := _cell_index(a.lerp(b, float(s) / steps))
		if cell < 0:
			continue
		for i in _grid[cell]:
			if _stamp[i] == _stamp_id:
				continue
			_stamp[i] = _stamp_id
			if _segment_hits(i, a, b, radius):
				return false
	return true


## How far a circle of `radius` can travel from `from` along the unit vector `dir` before it touches an obstacle,
## at most `max_len`.
func ray_distance(from: Vector2, dir: Vector2, max_len: float, radius: float) -> float:
	if not has_obstacles():
		return max_len
	var best := max_len
	_stamp_id += 1
	var steps := maxi(ceili(max_len / (INFLATE / 2.0)), 1)
	for s in steps + 1:
		var cell := _cell_index(from + dir * (max_len * s / steps))
		if cell < 0:
			continue
		for i in _grid[cell]:
			if _stamp[i] == _stamp_id:
				continue
			_stamp[i] = _stamp_id
			best = minf(best, _ray_hit(i, from, dir, radius, best))
	return best


## Unit vector the flow field says to walk from `pos` toward the nearest living Player, or ZERO (no field yet, or
## nowhere better to go).
func flow_direction(pos: Vector2) -> Vector2:
	return _flow.direction_at(pos) if _flow else Vector2.ZERO


func flow() -> FlowField:
	return _flow


func _physics_process(delta: float) -> void:
	if _flow == null:
		return
	_since_start += delta
	frame_expansions = 0
	if _flow.searching:
		frame_expansions = _flow.step(SEARCH_BUDGET)
	elif _since_start >= SEARCH_INTERVAL:
		var sources: Array[Vector2i] = []
		var points: Array[Vector2] = []
		# Looked up by path, not named, so this script compiles without the autoloads (pure-logic tests preload it).
		var registry := get_node_or_null("/root/PlayerRegistry")
		for p in (registry.players if registry else []):
			if not p.dead:
				var pos: Vector2 = p.global_position
				sources.append(FlowField.cell_of(pos))
				points.append(pos)
		if not sources.is_empty() and sources != _last_sources:
			_last_sources = sources
			_since_start = 0.0
			searches_started += 1
			_flow.begin(points)
			frame_expansions = _flow.step(SEARCH_BUDGET)
	max_frame_expansions = maxi(max_frame_expansions, frame_expansions)


func _list_shape(index: int, area: Rect2) -> void:
	var x0 := clampi(floori(area.position.x / CELL), 0, _gw - 1)
	var x1 := clampi(floori(area.end.x / CELL), 0, _gw - 1)
	var y0 := clampi(floori(area.position.y / CELL), 0, _gh - 1)
	var y1 := clampi(floori(area.end.y / CELL), 0, _gh - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_grid[y * _gw + x].append(index)


func _cell_index(pos: Vector2) -> int:
	var x := floori(pos.x / CELL)
	var y := floori(pos.y / CELL)
	if x < 0 or y < 0 or x >= _gw or y >= _gh:
		return -1
	return y * _gw + x


## The shortest displacement that moves a circle at `p` out of shape `i`, or ZERO when it does not overlap.
func _push(i: int, p: Vector2, radius: float) -> Vector2:
	var n := _rects.size()
	if i < n:
		var r := _rects[i]
		var near := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := p - near
		var dl := d.length()
		if dl > 0.0:
			return d / dl * (radius - dl + 0.001) if dl < radius else Vector2.ZERO
		# The centre is inside the rectangle: leave by the nearest edge.
		var to_left := p.x - r.position.x
		var to_right := r.end.x - p.x
		var to_top := p.y - r.position.y
		var to_bottom := r.end.y - p.y
		var m := minf(minf(to_left, to_right), minf(to_top, to_bottom))
		if m == to_left:
			return Vector2(-(to_left + radius + 0.001), 0)
		if m == to_right:
			return Vector2(to_right + radius + 0.001, 0)
		if m == to_top:
			return Vector2(0, -(to_top + radius + 0.001))
		return Vector2(0, to_bottom + radius + 0.001)
	var c := _centers[i - n]
	var d := p - c
	var reach := PILLAR_RADIUS + radius
	var dl := d.length()
	if dl >= reach:
		return Vector2.ZERO
	if dl < 0.0001:
		return Vector2(0, -(reach + 0.001))
	return d / dl * (reach - dl + 0.001)


func _segment_hits(i: int, a: Vector2, b: Vector2, radius: float) -> bool:
	var n := _rects.size()
	if i < n:
		var g := _rects[i].grow(radius)
		return _slab(g, a, b - a, 0.01) != null
	var reach := PILLAR_RADIUS + radius
	var c := _centers[i - n]
	var ab := b - a
	var len2 := ab.length_squared()
	var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	return (a + ab * t).distance_to(c) < reach


func _ray_hit(i: int, from: Vector2, dir: Vector2, radius: float, limit: float) -> float:
	var n := _rects.size()
	if i < n:
		var hit: Variant = _slab(_rects[i].grow(radius), from, dir * limit, 0.01)
		return limit if hit == null else hit * limit
	var reach := PILLAR_RADIUS + radius
	var f := from - _centers[i - n]
	var b := f.dot(dir)
	var c := f.length_squared() - reach * reach
	if c <= 0.0:
		return 0.0 if b < 0.0 else limit  # starting inside: blocked only when heading further in
	var disc := b * b - c
	if disc < 0.0:
		return limit
	var t := -b - sqrt(disc)
	return t if t >= 0.0 and t < limit else limit


## Entry parameter (0..1 along `delta` from `a`) where the segment first meets `r`, or null. `slack` shrinks the
## rectangle so a start on its edge heading along or away from it does not count.
func _slab(r: Rect2, a: Vector2, delta: Vector2, slack := 0.0) -> Variant:
	var t0 := 0.0
	var t1 := 1.0
	var lo := r.position + Vector2(slack, slack)
	var hi := r.end - Vector2(slack, slack)
	for axis in 2:
		var o := a[axis]
		var d := delta[axis]
		if absf(d) < 0.000001:
			if o <= lo[axis] or o >= hi[axis]:
				return null
		else:
			var ta := (lo[axis] - o) / d
			var tb := (hi[axis] - o) / d
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return null
	return t0

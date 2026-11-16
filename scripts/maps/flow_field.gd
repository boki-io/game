class_name FlowField
extends RefCounted
## A walking-distance field over the arena on a 16 px grid, filled by a breadth-first search from the living
## Players' cells. A search is spread over physics frames (`step(budget)`) and the finished field replaces the
## live one in one go. The steering direction is not stored: `direction_at()` reads the 8 neighbours of a cell.
## Pure logic: it only needs an ObstacleMap (spec 0.6, section 6.6).

const CELL := 16.0
const GROW := 8.0  # a cell is blocked when its centre is inside an obstacle grown by this

var width := 0
var height := 0
## True while a search is running; `step()` advances it.
var searching := false
## Completed searches.
var completed := 0

var _map: ObstacleMap
var _blocked := PackedByteArray()
var _dist := PackedInt32Array()  # the live field: walking distance in cells, -1 where unreached
var _building := PackedInt32Array()
var _queue := PackedInt32Array()
var _head := 0
var _ready_field := false


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


## Whether `cell` is closed to walking: outside the playable area, or its centre inside an obstacle grown by 8 px.
## The sealed-area layout test uses this same function.
static func cell_blocked(map: ObstacleMap, cell: Vector2i) -> bool:
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	if not map.bounds.has_point(centre):
		return true
	return map.blocked(centre, GROW)


func setup(map: ObstacleMap) -> void:
	_map = map
	width = ceili(map.size.x / CELL)
	height = ceili(map.size.y / CELL)
	_blocked.resize(width * height)
	for y in height:
		for x in width:
			_blocked[y * width + x] = 1 if cell_blocked(map, Vector2i(x, y)) else 0
	_dist.resize(width * height)
	_dist.fill(-1)
	_building.resize(width * height)


func is_blocked(cell: Vector2i) -> bool:
	return not _in(cell) or _blocked[cell.y * width + cell.x] == 1


func has_field() -> bool:
	return _ready_field


## Walking distance in cells of the live field, or -1 when unreached.
func distance(cell: Vector2i) -> int:
	return _dist[cell.y * width + cell.x] if _in(cell) else -1


## Starts a search from the cells of `sources` (world positions). A source cell counts as free even inside the
## growth zone; if all its neighbours are blocked the nearest free cell is a source too.
func begin(sources: Array[Vector2]) -> void:
	_building.fill(-1)
	_queue.clear()
	_head = 0
	for pos in sources:
		var cell := cell_of(pos).clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
		_seed(cell, 0)
		if _blocked[cell.y * width + cell.x] == 1 and not _has_free_neighbour(cell):
			var near := _nearest_free(cell)
			if near.x >= 0:
				_seed(near, 1)
	searching = true


## Runs up to `budget` cell expansions of the current search; returns how many it did.
func step(budget: int) -> int:
	var done := 0
	while _head < _queue.size() and done < budget:
		var c := _queue[_head]
		_head += 1
		done += 1
		var d := _building[c] + 1
		var x := c % width
		var y := c / width
		if x > 0:
			_visit(c - 1, d)
		if x < width - 1:
			_visit(c + 1, d)
		if y > 0:
			_visit(c - width, d)
		if y < height - 1:
			_visit(c + width, d)
	if _head >= _queue.size():
		var finished := _building
		_building = _dist
		_dist = finished
		searching = false
		_ready_field = true
		completed += 1
	return done


## Unit step from `pos` toward the Player along the field: the neighbour with the lowest distance (a diagonal only
## when both side cells are free, so no corner cutting). ZERO when there is no field or no neighbour is better.
func direction_at(pos: Vector2) -> Vector2:
	if not _ready_field:
		return Vector2.ZERO
	var cell := cell_of(pos)
	if not _in(cell):
		return Vector2.ZERO
	var here := _dist[cell.y * width + cell.x]
	var best := here if here >= 0 else 1 << 30
	var best_step := Vector2i.ZERO
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := cell + Vector2i(dx, dy)
			if not _in(n):
				continue
			var nd := _dist[n.y * width + n.x]
			if nd < 0 or nd >= best:
				continue
			if dx != 0 and dy != 0 and (is_blocked(cell + Vector2i(dx, 0)) or is_blocked(cell + Vector2i(0, dy))):
				continue
			best = nd
			best_step = Vector2i(dx, dy)
	return Vector2(best_step).normalized()


func _in(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func _seed(cell: Vector2i, d: int) -> void:
	var c := cell.y * width + cell.x
	if _building[c] == -1:
		_building[c] = d
		_queue.append(c)


func _visit(c: int, d: int) -> void:
	if _building[c] == -1 and _blocked[c] == 0:
		_building[c] = d
		_queue.append(c)


func _has_free_neighbour(cell: Vector2i) -> bool:
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not is_blocked(cell + off):
			return true
	return false


func _nearest_free(cell: Vector2i) -> Vector2i:
	for ring in range(2, 8):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) == ring and not is_blocked(cell + Vector2i(dx, dy)):
					return cell + Vector2i(dx, dy)
	return Vector2i(-1, -1)

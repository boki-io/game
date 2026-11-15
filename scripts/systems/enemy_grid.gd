extends Node
## Autoload. Spatial hash of active enemies, rebuilt once per physics frame.
## Being an autoload, it runs before the scene's nodes, so enemies see a fresh grid.

const CELL := 32.0

var _enemies: Dictionary = {}  # Enemy -> true
var _cells: Dictionary = {}  # Vector2i -> Array[Enemy]


func register(enemy: Enemy) -> void:
	_enemies[enemy] = true


func unregister(enemy: Enemy) -> void:
	_enemies.erase(enemy)


## Forgets every enemy. Each scene's controller calls this at startup so nothing stale survives a scene change.
func clear() -> void:
	_enemies.clear()
	_cells.clear()


func _physics_process(_delta: float) -> void:
	_cells.clear()
	for e: Enemy in _enemies:
		var key := _cell_of(e.global_position)
		if _cells.has(key):
			_cells[key].append(e)
		else:
			_cells[key] = [e]


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


## All enemies within radius of pos (including any at pos itself).
func query(pos: Vector2, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var lo := _cell_of(pos - Vector2(radius, radius))
	var hi := _cell_of(pos + Vector2(radius, radius))
	var r2 := radius * radius
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var bucket: Array = _cells.get(Vector2i(cx, cy), [])
			for e: Enemy in bucket:
				# Skip enemies released since the grid was rebuilt this frame (killed earlier in the frame).
				if e.active and pos.distance_squared_to(e.global_position) <= r2:
					out.append(e)
	return out


## Push vector away from nearby enemies, for crowd separation. Looks at no more than `max_neighbors`
## enemies and starts each cell at a different offset per caller, so in a dense crowd the cost stays
## bounded (the plain query() is O(crowd size) per enemy, and a 300-strong clump makes that O(n^2)).
func separation(pos: Vector2, radius: float, exclude: Enemy, max_neighbors: int, offset: int) -> Vector2:
	var push := Vector2.ZERO
	var lo := _cell_of(pos - Vector2(radius, radius))
	var hi := _cell_of(pos + Vector2(radius, radius))
	var r2 := radius * radius
	var seen := 0
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var bucket: Array = _cells.get(Vector2i(cx, cy), [])
			var n := bucket.size()
			for k in n:
				var e: Enemy = bucket[(k + offset) % n]
				if e == exclude or not e.active:
					continue
				var away := pos - e.global_position
				var d2 := away.length_squared()
				if d2 > r2:
					continue
				var dist := sqrt(d2)
				if dist < 0.01:
					away = Vector2.from_angle(randf() * TAU)
					dist = 0.01
				push += away / dist * (1.0 - dist / radius)
				seen += 1
				if seen >= max_neighbors:
					return push.limit_length(1.0)
	return push.limit_length(1.0)


func nearest(pos: Vector2, max_radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in query(pos, max_radius):
		var d := pos.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

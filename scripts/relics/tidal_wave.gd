class_name TidalWave
extends RelicBehavior
## Tidal Wave (spec 1.0, section 4.1): every `cooldown` seconds a wave rolls `range` px along the aim, hitting each enemy
## once per pass and shoving it along the travel direction. Level 3 turns back over the same (wall-shortened) range for a
## second pass. It only casts when an enemy is near the aim line, and retries every RETRY seconds without spending the cooldown.

const RETRY := 0.25
const HIT_PADDING := 6.0  # an enemy's body, added to the wave's radius (as for projectiles)
const WALL_RADIUS := 16.0  # ObstacleMap only accepts up to this radius

var _cooldown_left := 0.0
var _retry_left := 0.0
var _waves: Array[Dictionary] = []
var _canvas: Node2D


func _ready() -> void:
	_canvas = Node2D.new()
	_canvas.name = "WaveCanvas"
	_canvas.top_level = true
	_canvas.z_index = 5
	_canvas.draw.connect(_draw_waves)
	add_child(_canvas)


func cooldown_fraction() -> float:
	return clampf(_cooldown_left / float(params().cooldown), 0.0, 1.0)


func set_level(new_level: int) -> void:
	super(new_level)
	_cooldown_left = minf(_cooldown_left, float(params().cooldown))


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_retry_left -= delta
	if _cooldown_left <= 0.0 and _retry_left <= 0.0:
		if _try_cast():
			_cooldown_left = float(params().cooldown)
		else:
			_retry_left = RETRY
	if not _waves.is_empty():
		for w in _waves:
			_step(w, delta)
		_waves = _waves.filter(func(w: Dictionary) -> bool: return not w.done)
		_canvas.queue_redraw()


## True when an enemy is within range + width / 2 of the player and within width / 2 + 6 of the aim line.
func _has_target(origin: Vector2, dir: Vector2) -> bool:
	var p := params()
	var half: float = float(p.width) / 2.0
	var length: float = p.range
	for e in EnemyGrid.query(origin, length + half + HIT_PADDING):
		var closest := Geometry2D.get_closest_point_to_segment(e.global_position, origin, origin + dir * length)
		if closest.distance_to(e.global_position) <= half + HIT_PADDING:
			return true
	return false


func _try_cast() -> bool:
	var origin := player.global_position
	var dir: Vector2 = player.player_input.aim_vector
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	if not _has_target(origin, dir):
		return false
	var p := params()
	var length: float = p.range
	var map := ObstacleMap.get_for(self)
	if map:
		length = map.ray_distance(origin, dir, length, WALL_RADIUS)
	_waves.append({origin = origin, dir = dir, length = length, dist = 0.0, back = false, hit = {}, done = false,
		returns = bool(p.get("returns", false)), width = float(p.width), speed = float(p.speed),
		damage = float(p.damage), knockback = float(p.knockback), age = 0.0})
	Audio.play(&"relic_wave")
	return true


func _step(w: Dictionary, delta: float) -> void:
	w.age += delta
	var travel: Vector2 = w.dir
	if w.back:
		travel = -travel
		w.dist -= w.speed * delta
	else:
		w.dist += w.speed * delta
	var pos: Vector2 = w.origin + w.dir * w.dist
	var reach: float = w.width / 2.0 + HIT_PADDING
	for e in EnemyGrid.query(pos, reach):
		var id := e.get_instance_id()
		if w.hit.has(id):
			continue
		w.hit[id] = true
		e.take_damage(dmg(w.damage))
		e.apply_knockback(travel * w.knockback)
	if not w.back and w.dist >= w.length:
		w.dist = w.length
		if w.returns:
			w.back = true
			w.hit.clear()
		else:
			w.done = true
	elif w.back and w.dist <= 0.0:
		w.done = true


func _draw_waves() -> void:
	var color: Color = data.color
	for w in _waves:
		var pos: Vector2 = w.origin + w.dir * w.dist
		var heading: float = (w.dir.angle() + (PI if w.back else 0.0))
		var radius: float = w.width / 2.0
		var fade := 0.9 - 0.3 * clampf(w.dist / maxf(w.length, 1.0), 0.0, 1.0)
		_canvas.draw_arc(pos, radius, heading - 1.0, heading + 1.0, 14, Color(color, fade), 3.0)
		_canvas.draw_arc(pos, radius * 0.7, heading - 0.8, heading + 0.8, 10, Color(color.lightened(0.5), fade * 0.7), 1.5)

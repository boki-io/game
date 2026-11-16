class_name PlayerProjectile
extends Node2D
## A pooled spell bolt fired by the player. Moves in code and hits through the enemy grid (like the
## Knight's attacks), so it needs no physics bodies. Each bolt damages an enemy once; pierce lets it
## continue through that many enemies. It passes over props and retires at the arena edge.
## The Archer's arrows (spec 1.1, section 5) add, through `opts`: a hit limit, a bounce from one enemy to the
## next, a ricochet off walls, pillars and the arena edge, an arrow look and Steady Aim damage.

const RADIUS := 4.0
const HIT_PADDING := 6.0  # added to the radius so edge-touching enemies are hit
const LIFETIME_SLACK := 0.5  # seconds beyond range / speed before a stuck bolt is retired
const DEFAULT_BOUNCE_REACH := 140.0
const OBSTACLE_RADIUS := 3.0  # the circle an arrow sweeps against walls and pillars

var active := false
var pool: PlayerProjectiles

var _dir := Vector2.RIGHT
var _speed := 0.0
var _damage := 0.0
var _range_left := 0.0
var _life := 0.0
var _pierce_left := 0
var _hit: Dictionary = {}
var _hits_left := 0  # > 0 when the arrow retires on its Nth distinct enemy instead of using pierce
var _bounces_left := 0
var _ricochet := false  # launched with bounces: reflects off obstacles and the playable edge
var _bounce_reach := DEFAULT_BOUNCE_REACH
var _arrow := false
var _steady := false
var _steady_full := SteadyAim.FULL_DISTANCE
var _launch := Vector2.ZERO
var _been_clear := false  # an arrow fired inside an obstacle ignores it until it has been clear once


## `opts` keys (all optional): `hits` (int, 0 = the pierce rule), `bounces` (int, 0), `bounce_reach` (px, 140),
## `arrow` (draw an arrow), `steady` (apply Steady Aim), `steady_full` (px, SteadyAim.FULL_DISTANCE).
func launch(pos: Vector2, dir: Vector2, speed: float, damage: float, range_px: float, pierce: int,
		opts: Dictionary = {}) -> void:
	global_position = pos
	_launch = pos
	_hits_left = int(opts.get(&"hits", 0))
	_bounces_left = int(opts.get(&"bounces", 0))
	_ricochet = _bounces_left > 0
	_bounce_reach = float(opts.get(&"bounce_reach", DEFAULT_BOUNCE_REACH))
	_arrow = bool(opts.get(&"arrow", false))
	_steady = bool(opts.get(&"steady", false))
	_steady_full = float(opts.get(&"steady_full", SteadyAim.FULL_DISTANCE))
	_been_clear = false
	_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_speed = speed
	_damage = damage
	_range_left = range_px
	_life = range_px / maxf(speed, 1.0) + LIFETIME_SLACK
	_pierce_left = pierce
	_hit.clear()
	rotation = _dir.angle()
	active = true
	visible = true
	set_physics_process(true)
	queue_redraw()


func retire() -> void:
	if not active:
		return
	active = false
	visible = false
	set_physics_process(false)
	pool.release(self)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	var prev := global_position
	global_position += _dir * step
	_range_left -= step
	_life -= delta
	if _range_left <= 0.0 or _life <= 0.0 or not Rect2(Vector2.ZERO, Vector2(Arena.world_size)).has_point(global_position):
		retire()
		return
	if _ricochet and not _reflect(prev):
		return
	var hits := EnemyGrid.query(global_position, RADIUS + HIT_PADDING)
	if hits.size() > 1:
		hits.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	for e in hits:
		if _hit.has(e):
			continue
		_hit[e] = true
		var dmg := _damage
		if _steady:
			dmg *= SteadyAim.multiplier(_launch.distance_to(e.global_position), _steady_full)
		e.take_damage(dmg)
		Audio.play(&"bolt_hit", -6.0)
		if _hits_left > 0:
			_hits_left -= 1
			if _hits_left <= 0:
				retire()
				return
			if _bounces_left > 0 and _bounce_to_next():
				return
		else:
			if _pierce_left <= 0:
				retire()
				return
			_pierce_left -= 1


## Turns towards the nearest enemy within the bounce reach that this arrow has not hit (and that no wall or
## pillar hides), spending a bounce. Returns false, changing nothing, when there is none.
func _bounce_to_next() -> bool:
	var best: Enemy = null
	var best_d2 := INF
	var map := ObstacleMap.get_for(self)
	for c in EnemyGrid.query(global_position, _bounce_reach):
		if _hit.has(c):
			continue
		var d2 := global_position.distance_squared_to(c.global_position)
		if d2 >= best_d2:
			continue
		if map != null and not map.segment_clear(global_position, c.global_position, OBSTACLE_RADIUS):
			continue
		best = c
		best_d2 = d2
	if best == null:
		return false
	_turn((best.global_position - global_position).normalized())
	return true


## Ricochet off an obstacle or the edge of the playable rectangle (the arena inset by the wall margin). `prev` is
## the position before this step. Returns false when the arrow retired (no bounce left).
func _reflect(prev: Vector2) -> bool:
	var margin := Arena.wall_margin
	var play := Rect2(Vector2(margin, margin), Vector2(Arena.world_size) - Vector2(margin, margin) * 2.0)
	var map := ObstacleMap.get_for(self)
	var pos := global_position
	var normal := Vector2.ZERO
	if not play.has_point(pos):
		if _been_clear or play.has_point(prev):
			if pos.x < play.position.x:
				normal.x += 1.0
			elif pos.x > play.end.x:
				normal.x -= 1.0
			if pos.y < play.position.y:
				normal.y += 1.0
			elif pos.y > play.end.y:
				normal.y -= 1.0
	elif map != null and map.blocked(pos, OBSTACLE_RADIUS):
		if _been_clear or not map.blocked(prev, OBSTACLE_RADIUS):
			normal = map.push_out(pos, OBSTACLE_RADIUS) - pos
			if normal.length_squared() < 0.0001:
				normal = -_dir
	else:
		_been_clear = true
		return true
	if normal == Vector2.ZERO:
		return true
	if _bounces_left <= 0:
		retire()
		return false
	global_position = prev
	_turn(_dir.bounce(normal.normalized()))
	return true


func _turn(dir: Vector2) -> void:
	_dir = dir
	rotation = dir.angle()
	_bounces_left -= 1
	Audio.play(&"arrow_bounce", -6.0)


func _draw() -> void:
	if _arrow:
		_draw_arrow()
		return
	# Drawn 8px above the feet plane the bolt travels in, at body height.
	var o := Vector2(0, -8).rotated(-rotation)
	draw_line(o + Vector2(-12, 0), o, Color(0.4, 0.8, 1.0, 0.3), 4.0)
	draw_line(o + Vector2(-7, 0), o, Color(0.6, 0.9, 1.0, 0.6), 2.5)
	draw_circle(o, 3.5, Color(0.35, 0.75, 1.0))
	draw_circle(o, 2.0, Color(0.9, 1.0, 1.0))


## A thin shaft with a head and fletching, 14 px long, at body height.
func _draw_arrow() -> void:
	var o := Vector2(0, -8).rotated(-rotation)
	var shaft := Color(0.85, 0.7, 0.45)
	draw_line(o + Vector2(-9, 0), o + Vector2(3, 0), shaft, 1.5)
	draw_colored_polygon(PackedVector2Array([o + Vector2(5, 0), o + Vector2(2, -2), o + Vector2(2, 2)]), Color(0.9, 0.92, 0.95))
	draw_line(o + Vector2(-9, 0), o + Vector2(-11, -2.5), Color(0.9, 0.3, 0.25), 1.0)
	draw_line(o + Vector2(-9, 0), o + Vector2(-11, 2.5), Color(0.9, 0.3, 0.25), 1.0)
	draw_line(o + Vector2(-7, 0), o + Vector2(-9, -2.5), Color(0.9, 0.3, 0.25), 1.0)
	draw_line(o + Vector2(-7, 0), o + Vector2(-9, 2.5), Color(0.9, 0.3, 0.25), 1.0)

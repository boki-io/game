class_name PlayerProjectile
extends Node2D
## A pooled spell bolt fired by the player. Moves in code and hits through the enemy grid (like the
## Knight's attacks), so it needs no physics bodies. Each bolt damages an enemy once; pierce lets it
## continue through that many enemies. It passes over props and retires at the arena edge.

const RADIUS := 4.0
const HIT_PADDING := 6.0  # added to the radius so edge-touching enemies are hit
const LIFETIME_SLACK := 0.5  # seconds beyond range / speed before a stuck bolt is retired

var active := false
var pool: PlayerProjectiles

var _dir := Vector2.RIGHT
var _speed := 0.0
var _damage := 0.0
var _range_left := 0.0
var _life := 0.0
var _pierce_left := 0
var _hit: Dictionary = {}


func launch(pos: Vector2, dir: Vector2, speed: float, damage: float, range_px: float, pierce: int) -> void:
	global_position = pos
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
	global_position += _dir * step
	_range_left -= step
	_life -= delta
	if _range_left <= 0.0 or _life <= 0.0 or not Rect2(Vector2.ZERO, Vector2(Arena.world_size)).has_point(global_position):
		retire()
		return
	var hits := EnemyGrid.query(global_position, RADIUS + HIT_PADDING)
	if hits.size() > 1:
		hits.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	for e in hits:
		if _hit.has(e):
			continue
		_hit[e] = true
		e.take_damage(_damage)
		Audio.play(&"bolt_hit", -6.0)
		if _pierce_left <= 0:
			retire()
			return
		_pierce_left -= 1


func _draw() -> void:
	# Drawn 8px above the feet plane the bolt travels in, at body height.
	var o := Vector2(0, -8).rotated(-rotation)
	draw_line(o + Vector2(-12, 0), o, Color(0.4, 0.8, 1.0, 0.3), 4.0)
	draw_line(o + Vector2(-7, 0), o, Color(0.6, 0.9, 1.0, 0.6), 2.5)
	draw_circle(o, 3.5, Color(0.35, 0.75, 1.0))
	draw_circle(o, 2.0, Color(0.9, 1.0, 1.0))

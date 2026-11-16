class_name OrbBelt
extends Node2D
## A ring of orbs that circles the player for a few seconds and damages enemies it sweeps through
## (Phase Shift's payoff once the phase ends). Hits use the enemy grid; each enemy can be hit at most
## once per HIT_COOLDOWN no matter how many orbs pass it. Storm Orbs (a relic) runs its own belt in endless
## mode (`start` with a duration of 0 or less), recoloured with `color` and reshaped with `set_shape`.

const ORB_RADIUS := 5.0
const HIT_PADDING := 6.0
const HIT_COOLDOWN := 0.5
const FADE_IN := 0.15
const FADE_OUT := 0.35
const BODY_HEIGHT := Vector2(0, -8)  # orbs are drawn at body height; hits happen in the feet plane

var active := false
## Base colour of the orbs (the default is Phase Shift's blue).
var color := Color(0.35, 0.7, 1.0)

var _count := 5
var _radius := 28.0
var _turns_per_second := 2.0
var _damage := 8.0
var _time_left := 0.0
var _total := 0.0
var _angle := 0.0
var _age := 0.0
var _endless := false
var _cooldowns: Dictionary = {}  # Enemy -> seconds until it can be hit again


func start(count: int, radius: float, turns_per_second: float, damage: float, duration: float) -> void:
	_count = count
	_radius = radius
	_turns_per_second = turns_per_second
	_damage = damage
	_time_left = duration
	_total = duration
	_endless = duration <= 0.0
	_age = 0.0
	_cooldowns.clear()
	active = true
	visible = true
	set_physics_process(true)
	queue_redraw()


## Changes the shape while running; hit cooldowns and the angle carry on.
func set_shape(count: int, radius: float, turns_per_second: float, damage: float) -> void:
	_count = count
	_radius = radius
	_turns_per_second = turns_per_second
	_damage = damage


## World position of orb `i` (feet plane, where hits happen).
func orb_position(i: int) -> Vector2:
	return global_position + _orb_offset(i)


func orb_count() -> int:
	return _count


func stop() -> void:
	active = false
	visible = false
	_cooldowns.clear()
	set_physics_process(false)


func _ready() -> void:
	stop()


func _physics_process(delta: float) -> void:
	_age += delta
	if not _endless:
		_time_left -= delta
		if _time_left <= 0.0:
			stop()
			return
	_angle += TAU * _turns_per_second * delta
	for e in _cooldowns.keys():
		if not is_instance_valid(e) or not e.active:
			_cooldowns.erase(e)
			continue
		_cooldowns[e] -= delta
		if _cooldowns[e] <= 0.0:
			_cooldowns.erase(e)
	for i in _count:
		var pos := global_position + _orb_offset(i)
		for e in EnemyGrid.query(pos, ORB_RADIUS + HIT_PADDING):
			if _cooldowns.has(e):
				continue
			_cooldowns[e] = HIT_COOLDOWN
			e.take_damage(_damage)
	queue_redraw()


func _orb_offset(i: int) -> Vector2:
	return Vector2.from_angle(_angle + TAU * i / _count) * _radius


func _draw() -> void:
	if not active:
		return
	var alpha := minf(_age / FADE_IN, 1.0)
	if not _endless:
		alpha = minf(minf((_total - _time_left) / FADE_IN, _time_left / FADE_OUT), 1.0)
	for i in _count:
		var p := _orb_offset(i) + BODY_HEIGHT
		var trail := Vector2.from_angle(_angle + TAU * i / _count - PI / 2.0) * 7.0
		draw_line(p, p + trail, Color(color.lightened(0.15), 0.35 * alpha), 3.0)
		draw_circle(p, ORB_RADIUS, Color(color, 0.9 * alpha))
		draw_circle(p, ORB_RADIUS - 2.0, Color(0.9, 1.0, 1.0, alpha))

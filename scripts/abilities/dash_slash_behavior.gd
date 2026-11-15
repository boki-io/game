class_name DashSlashBehavior
extends AbilityBehavior
## Short invulnerable dash toward the aim, damaging everything along the path,
## finishing with a small slash arc.

const PATH_WIDTH := 10.0

var _aim := Vector2.RIGHT
var _elapsed := 0.0
var _distance := 0.0
var _speed := 0.0
var _traveled := 0.0
var _final := false
var _last := Vector2.ZERO
var _hit: Dictionary = {}


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	_aim = aim
	_elapsed = 0.0
	_traveled = 0.0
	_final = false
	_hit.clear()
	var player := caster.player
	_last = player.global_position
	_distance = caster.value(d, &"range", d.range)
	_speed = _distance / d.duration
	player.velocity_override = aim * _speed
	player.override_active = true
	player.hurtbox.invulnerable = true
	player.face_towards(aim, d.duration + 0.15)


func update(delta: float) -> bool:
	var player := caster.player
	var pos := player.global_position
	_hit_path(_last, pos)
	_traveled += pos.distance_to(_last)
	_last = pos
	_elapsed += delta
	var fx := Effects.get_for(caster)
	if fx:
		fx.puff(pos + Vector2(0, -8), Color(0.7, 0.85, 1.0))
	if _final or _elapsed >= data.duration * 2.0:  # the 2x guard ends a dash blocked by a wall
		_finish_slash(pos, fx)
		return true
	# On the frame that would overshoot, step exactly the remaining distance.
	if delta > 0.0 and _distance - _traveled <= _speed * delta + 0.01:
		caster.player.velocity_override = _aim * maxf(_distance - _traveled, 0.0) / delta
		_final = true
	return false


func finish() -> void:
	var player := caster.player
	player.override_active = false
	player.hurtbox.invulnerable = false


func _hit_path(from: Vector2, to: Vector2) -> void:
	var damage := caster.damage_of(data)
	var mid := (from + to) / 2.0
	for e in EnemyGrid.query(mid, from.distance_to(to) / 2.0 + PATH_WIDTH + ENEMY_RADIUS):
		if _hit.has(e):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(e.global_position, from, to)
		if closest.distance_to(e.global_position) <= PATH_WIDTH:
			_hit[e] = true
			e.take_damage(damage)


func _finish_slash(pos: Vector2, fx: Effects) -> void:
	var arc := deg_to_rad(data.arc_degrees)
	var reach := caster.value(data, &"radius", data.radius)
	hit_arc(pos, _aim, reach, arc, caster.damage_of(data), _hit)
	if fx:
		fx.slash_arc(pos + Vector2(0, -8), _aim, reach, arc)

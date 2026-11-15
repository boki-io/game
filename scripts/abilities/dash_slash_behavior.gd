class_name DashSlashBehavior
extends AbilityBehavior
## Short invulnerable dash toward the aim, damaging everything along the path,
## finishing with a small slash arc.

const PATH_WIDTH := 10.0
const TRAIL_DURATION := 2.0
const TRAIL_INTERVAL := 0.25
const TRAIL_DAMAGE_RATIO := 0.2  # of dash damage, per tick, per upgrade level

var _aim := Vector2.RIGHT
var _elapsed := 0.0
var _distance := 0.0
var _speed := 0.0
var _traveled := 0.0
var _final := false
var _start := Vector2.ZERO
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
	_start = _last
	caster.play_sfx(d)


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
	_leave_trail(pos)
	caster.player.hurtbox.grant_grace(data.immunity_after)
	_push_back(pos)
	var arc := deg_to_rad(data.arc_degrees)
	var reach := caster.value(data, &"radius", data.radius)
	hit_arc(pos, _aim, reach, arc, caster.damage_of(data), _hit)
	if fx:
		fx.slash_arc(pos + Vector2(0, -8), _aim, reach, arc)


## Blade Trail: the dashed path keeps damaging enemies for 2s.
func _leave_trail(end: Vector2) -> void:
	var level := int(caster.stats.value(&"dash.trail", 0.0))
	if level <= 0 or _start.distance_to(end) < 1.0:
		return
	var zones := DamageZones.get_for(caster)
	if zones:
		var damage := caster.damage_of(data) * TRAIL_DAMAGE_RATIO * level
		zones.add_line(_start, end, PATH_WIDTH, damage, TRAIL_INTERVAL, int(TRAIL_DURATION / TRAIL_INTERVAL))


## Shoves enemies around the landing spot away so the player isn't left standing in a crowd.
func _push_back(pos: Vector2) -> void:
	if data.knockback <= 0.0:
		return
	var reach := caster.value(data, &"radius", data.radius)
	for e in EnemyGrid.query(pos, reach):
		var away: Vector2 = e.global_position - pos
		var dir := away.normalized() if away.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
		e.apply_knockback(dir * data.knockback)

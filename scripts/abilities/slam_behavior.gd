class_name SlamBehavior
extends AbilityBehavior
## Slam: a ground telegraph during the windup, then a heavy circle hit that knocks enemies back.
## The impact point is fixed when the cast starts, `range` px along the aim.

const MOVE_SCALE := 0.4  # walking speed during the windup
const KNOCKBACK_SPEED := 160.0  # enemies slide ~20px

var _elapsed := 0.0
var _center := Vector2.ZERO


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	_elapsed = 0.0
	var player := caster.player
	_center = player.global_position + aim * caster.value(d, &"range", d.range)
	player.speed_scale = MOVE_SCALE
	var fx := Effects.get_for(caster)
	if fx:
		fx.telegraph(_center, caster.value(d, &"radius", d.radius), d.windup)


func update(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < data.windup:
		return false
	_impact()
	return true


func finish() -> void:
	caster.player.speed_scale = 1.0


func _impact() -> void:
	var radius := caster.value(data, &"radius", data.radius)
	var hit: Dictionary = {}
	hit_circle(_center, radius, caster.damage_of(data), hit)
	for e: Enemy in hit:
		var away := e.global_position - _center
		var dir := away.normalized() if away.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
		e.apply_knockback(dir * KNOCKBACK_SPEED)
	var fx := Effects.get_for(caster)
	if fx:
		fx.ring(_center, radius)

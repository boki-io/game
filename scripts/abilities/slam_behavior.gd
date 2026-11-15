class_name SlamBehavior
extends AbilityBehavior
## Slam: a ground telegraph during the windup, then a heavy circle hit that knocks enemies back.
## The impact point is fixed when the cast starts, `range` px along the aim.
## Upgrades: Stunning Blow (slam.stun) and Shockwave (slam.shockwave, a second larger ring).

const MOVE_SCALE := 0.4  # walking speed during the windup
const KNOCKBACK_SPEED := 160.0  # enemies slide ~20px
const STUN_BASE := 0.5  # seconds, plus STUN_PER_LEVEL per upgrade level
const STUN_PER_LEVEL := 0.5
const SHOCKWAVE_DELAY := 0.2
const SHOCKWAVE_DAMAGE_RATIO := 0.5
const SHOCKWAVE_RADIUS_BASE := 1.4  # x slam radius, plus 0.1 per level
const SHOCKWAVE_KNOCKBACK := 120.0
const SHAKE_STRENGTH := 2.0
const SHAKE_TIME := 0.15

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
	var damage := caster.damage_of(data)
	var stun_level := int(caster.stats.value(&"slam.stun", 0.0))
	var hit: Dictionary = {}
	hit_circle(_center, radius, damage, hit)
	for e: Enemy in hit:
		var away := e.global_position - _center
		var dir := away.normalized() if away.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
		e.apply_knockback(dir * KNOCKBACK_SPEED)
		if stun_level > 0:
			e.stun(STUN_BASE + STUN_PER_LEVEL * stun_level)
	var fx := Effects.get_for(caster)
	if fx:
		fx.ring(_center, radius)
	caster.play_sfx(data)
	CameraFollow.shake(caster, SHAKE_STRENGTH, SHAKE_TIME)

	var shock_level := int(caster.stats.value(&"slam.shockwave", 0.0))
	if shock_level > 0:
		var zones := DamageZones.get_for(caster)
		if zones:
			zones.add_burst(_center, radius * (SHOCKWAVE_RADIUS_BASE + 0.1 * shock_level),
				damage * SHOCKWAVE_DAMAGE_RATIO, SHOCKWAVE_DELAY, SHOCKWAVE_KNOCKBACK)

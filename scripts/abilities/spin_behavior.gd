class_name SpinBehavior
extends AbilityBehavior
## Spin: hits everything within the radius once while the player moves slowly.
## With the spin_hits_twice flag, a second pass lands at the halfway point.

const MOVE_SCALE := 0.4  # walking speed while spinning
const TURNS := 2.0  # visual blade rotations

var _elapsed := 0.0
var _hit: Dictionary = {}
var _second_pass_done := false


func cast(c: AbilityCaster, _aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	_elapsed = 0.0
	_hit.clear()
	_second_pass_done = false
	caster.player.speed_scale = MOVE_SCALE


func update(delta: float) -> bool:
	var origin := caster.player.global_position
	var radius := caster.value(data, &"radius", data.radius)
	var damage := caster.damage_of(data)
	_elapsed += delta

	if caster.stats.has_flag(&"spin_hits_twice") and not _second_pass_done and _elapsed >= data.duration / 2.0:
		_second_pass_done = true
		_hit.clear()
	hit_circle(origin, radius, damage, _hit)

	var fx := Effects.get_for(caster)
	if fx and delta > 0.0:
		var angle := _elapsed / data.duration * TAU * TURNS
		fx.slash_arc(origin + Vector2(0, -8), Vector2.from_angle(angle), radius, deg_to_rad(70.0))
	return _elapsed >= data.duration


func finish() -> void:
	caster.player.speed_scale = 1.0

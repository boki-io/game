class_name SpinBehavior
extends AbilityBehavior
## Spin: hits everything within the radius once while the player moves slowly.
## Double Spin adds extra passes; each pass can hit every enemy again.

const MOVE_SCALE := 0.4  # walking speed while spinning
const TURNS := 2.0  # visual blade rotations

var _elapsed := 0.0
var _hit: Dictionary = {}
var _passes := 1
var _pass_index := 0


func cast(c: AbilityCaster, _aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	_elapsed = 0.0
	_hit.clear()
	_pass_index = 0
	_passes = 1 + int(caster.stats.value(&"spin.extra_passes", 0.0))
	caster.player.speed_scale = MOVE_SCALE
	caster.play_sfx(d)


func update(delta: float) -> bool:
	var origin := caster.player.global_position
	var radius := caster.value(data, &"radius", data.radius)
	_elapsed += delta

	var index := mini(int(_elapsed / (data.duration / _passes)), _passes - 1)
	if index != _pass_index:
		_pass_index = index
		_hit.clear()
	hit_circle(origin, radius, caster.damage_of(data), _hit)

	var fx := Effects.get_for(caster)
	if fx and delta > 0.0:
		var angle := _elapsed / data.duration * TAU * TURNS
		fx.slash_arc(origin + Vector2(0, -8), Vector2.from_angle(angle), radius, deg_to_rad(70.0))
	return _elapsed >= data.duration


func finish() -> void:
	caster.player.speed_scale = 1.0

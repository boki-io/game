class_name SlashBehavior
extends AbilityBehavior
## Instant arc in front of the player.


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	caster.play_sfx(d)
	var origin := caster.player.global_position
	var reach := caster.value(d, &"range", d.range)
	var arc := deg_to_rad(caster.value(d, &"arc_degrees", d.arc_degrees))
	hit_arc(origin, aim, reach, arc, caster.damage_of(d), {})
	var fx := Effects.get_for(caster)
	if fx == null:
		return
	if d.effect:
		fx.play_frames(d.effect, origin + Vector2(0, -8) + aim * d.effect_offset, aim.angle(), d.effect_scale)
	else:
		fx.slash_arc(origin + Vector2(0, -8), aim, reach, arc)

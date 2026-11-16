class_name ArrowBehavior
extends AbilityBehavior
## Archer's auto Arrow: instant. Fires one or more arrows along the aim, with Steady Aim applied on hit.
## Upgrades: Twin Arrow (arrow.extra), Piercing Arrow (arrow.pierce), Eagle Eye (arrow.range).

const DEFAULT_SPEED := 320.0  # px/s, when the data has no `speed` param


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var pool := PlayerProjectiles.get_for(caster)
	if pool == null:
		return
	var count := clampi(1 + int(caster.value(d, &"extra", 0.0)), 1, 4)
	var pierce := int(caster.value(d, &"pierce", 0.0))
	var damage := caster.damage_of(d)
	var reach := caster.value(d, &"range", d.range)
	var speed := d.param(&"speed", DEFAULT_SPEED)
	var opts := {
		&"arrow": true,
		&"steady": true,
		&"steady_full": caster.stats.value(&"steady.full", SteadyAim.FULL_DISTANCE),
	}
	var origin := caster.player.global_position
	var fired := false
	for angle: float in BoltBehavior.SPREADS[count]:
		fired = pool.fire(origin, aim.rotated(deg_to_rad(angle)), speed, damage, reach, pierce, opts) or fired
	if fired:  # at the projectile cap nothing is fired, so stay silent
		Audio.play(&"arrow_fire")

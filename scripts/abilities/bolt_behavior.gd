class_name BoltBehavior
extends AbilityBehavior
## Arcane Bolt: instant. Fires one or more spell bolts along the aim.
## Upgrades: Twin Bolt (bolt.extra), Piercing Bolt (bolt.pierce). Damage is read at the moment of firing.

const SPEED := 260.0  # px/s
## Fan angles in degrees for 1 to 4 bolts.
const SPREADS := {
	1: [0.0],
	2: [0.0, 10.0],
	3: [-10.0, 0.0, 10.0],
	4: [-15.0, -5.0, 5.0, 15.0],
}


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
	var origin := caster.player.global_position
	var fired := false
	for angle: float in SPREADS[count]:
		fired = pool.fire(origin, aim.rotated(deg_to_rad(angle)), SPEED, damage, reach, pierce) or fired
	if fired:  # at the projectile cap nothing is fired, so stay silent
		caster.play_sfx(d)

class_name DashShotBehavior
extends DashSlashBehavior
## Archer's Dash Shot: the Knight's dash toward the aim (invulnerable, no damage on the way), then a fan of
## arrows from the landing spot back the way the Archer came.
## Upgrades: Long Dash (dashshot.range), Wide Spray (dashshot.arrows), Double Dash (dashshot.chain).

const ARROW_RANGE := 180.0  # px, enough to reach Steady Aim's full distance


## The dash deals no damage.
func _hit_path(_from: Vector2, _to: Vector2) -> void:
	pass


## Instead of a slash: grace time, then the spray, centred on the opposite of the aim.
func _finish_slash(pos: Vector2, _fx: Effects) -> void:
	caster.player.hurtbox.grant_grace(data.immunity_after)
	var pool := PlayerProjectiles.get_for(caster)
	if pool == null:
		return
	var count := maxi(int(data.param(&"arrows", 7.0) + caster.value(data, &"arrows", 0.0)), 1)
	var speed := data.param(&"speed", 300.0)
	var damage := caster.damage_of(data)
	var opts := {
		&"arrow": true,
		&"steady": true,
		&"steady_full": caster.stats.value(&"steady.full", SteadyAim.FULL_DISTANCE),
	}
	var arc := data.arc_degrees
	var back := -_aim
	var fired := false
	for i in count:
		var angle := 0.0 if count == 1 else lerpf(-arc / 2.0, arc / 2.0, float(i) / float(count - 1))
		fired = pool.fire(pos, back.rotated(deg_to_rad(angle)), speed, damage, ARROW_RANGE, 0, opts) or fired
	if fired:
		Audio.play(&"arrow_fire")

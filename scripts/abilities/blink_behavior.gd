class_name BlinkBehavior
extends AbilityBehavior
## Blink: instant teleport along the aim, stopping at walls and props. Leaves a damaging burst
## where the Wizard was and grants a short immunity.
## Upgrades: Long Blink (blink.range), Rift (blink.rift, only on the first Blink of a chain),
## Double Blink (blink.chain, handled by the caster).

const MIN_TRAVEL := 8.0  # less room than this and the cast is rejected
const RIFT_INTERVAL := 0.5
const RIFT_TICKS := 5  # about 2s, first tick at once
const RIFT_RATIO := 0.25  # of Blink damage, per tick, per upgrade level
const RIFT_COLOR := Color(0.55, 0.45, 1.0)


func can_cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> bool:
	var motion := aim * c.value(d, &"range", d.range)
	var hit := c.player.move_and_collide(motion, true)  # test only: nothing moves
	var travel := motion.length() if hit == null else hit.get_travel().length()
	if travel < MIN_TRAVEL:
		fail_reason = &"blocked"
		return false
	return true


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var player := caster.player
	var origin := player.global_position
	player.move_and_collide(aim * caster.value(d, &"range", d.range))
	var destination := player.global_position

	var radius := caster.value(d, &"radius", d.radius)
	var damage := caster.damage_of(d)
	var hit: Dictionary = {}
	hit_circle(origin, radius, damage, hit)
	for e: Enemy in hit:
		var away := e.global_position - origin
		var dir := away.normalized() if away.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
		e.apply_knockback(dir * d.knockback)

	player.hurtbox.grant_grace(d.immunity_after)
	player.face_towards(aim, 0.25)

	var rift := int(caster.value(d, &"rift", 0.0))
	if rift > 0 and not caster.casting_follow_up:
		var zones := DamageZones.get_for(caster)
		if zones:
			zones.add_field(origin, radius, damage * RIFT_RATIO * rift, RIFT_INTERVAL, RIFT_TICKS, RIFT_COLOR)

	var fx := Effects.get_for(caster)
	if fx:
		fx.ring(origin, radius)
		fx.puff(origin + Vector2(0, -8), Color(0.6, 0.8, 1.0))
		fx.puff(destination + Vector2(0, -8), Color(1.0, 0.9, 0.5))
	caster.play_sfx(d)

class_name MeteorBehavior
extends AbilityBehavior
## Meteor Strike: fire and forget. Casting is instant: it drops a ground marker and schedules the
## blast through DamageZones, so the Wizard stays free to move and cast while it falls.
## Impact point, radius and damage are fixed at cast time.
## Upgrades: Bigger Blast (meteor.radius), Twin Meteor (meteor.extra), Scorched Earth (meteor.scorch).

const EXTRA_DELAY := 0.4  # each extra meteor lands this long after the previous one
const SCATTER := 50.0  # extra meteors land within this distance of the first
const SHAKE := Vector2(3.0, 0.2)  # strength px, seconds
const SCORCH_INTERVAL := 0.5
const SCORCH_TICKS := 7  # about 3s, first tick at the first impact
const SCORCH_RATIO := 0.04  # of Meteor damage, per tick, per upgrade level
const SCORCH_COLOR := Color(1.0, 0.45, 0.15)
const IMPACT_SOUND := preload("res://assets/audio/meteor_impact.wav")


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var zones := DamageZones.get_for(c)
	var fx := Effects.get_for(c)
	if zones == null:
		return
	var radius := c.value(d, &"radius", d.radius)
	var damage := c.damage_of(d)
	var count := 1 + int(c.value(d, &"extra", 0.0))
	var first := clamp_to_arena(c.player.global_position + aim * c.value(d, &"range", d.range))
	var extras := {"sfx": IMPACT_SOUND, "shake": SHAKE, "visual": &"meteor"}

	for i in count:
		var pos := first
		if i > 0:
			pos = clamp_to_arena(first + Vector2.from_angle(randf() * TAU) * randf_range(0.0, SCATTER))
		var delay := d.windup + EXTRA_DELAY * i
		if fx:
			fx.telegraph(pos, radius, delay, true)
		zones.add_burst(pos, radius, damage, delay, d.knockback, extras)

	var scorch := int(c.value(d, &"scorch", 0.0))
	if scorch > 0:
		zones.add_field(first, radius, damage * SCORCH_RATIO * scorch, SCORCH_INTERVAL, SCORCH_TICKS,
			SCORCH_COLOR, d.windup)
	c.play_sfx(d)  # the falling whistle; the impact sound plays from the burst

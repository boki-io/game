class_name ArrowRainBehavior
extends AbilityBehavior
## Arrow Rain: instant and fire and forget. Marks `zones` circles around the cursor (or the aim, on a pad) and
## schedules a damage field on each through DamageZones, so the Archer stays free while the arrows come down.
## The zones sit on a regular polygon far enough apart that no enemy stands in two of them.
## Upgrades: Wider Rain (arrow_rain.radius), Extra Zone (arrow_rain.extra), Lingering Rain (arrow_rain.ticks).

const GAP := 8.0  # adjacent zone centres are 2 * (radius + GAP) apart, more than the 2 * (radius + 6) DamageZones reaches
const FALL_TIME := 0.35  # the falling arrows are drawn for the last part of the windup
const COLOR := Color(0.95, 0.85, 0.5)


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var zones := DamageZones.get_for(c)
	if zones == null:
		return
	var fx := Effects.get_for(c)
	var origin := c.player.global_position
	var radius := c.value(d, &"radius", d.radius)
	var count := maxi(int(d.param(&"zones", 3.0)) + int(c.value(d, &"extra", 0.0)), 1)
	var ticks := int(d.param(&"ticks", 5.0)) + int(c.value(d, &"ticks", 0.0))
	var damage := c.damage_of(d)
	var center := clamp_to_arena(c.player.player_input.aim_point(c.value(d, &"range", d.range)))
	var towards := origin - center
	var start := towards.angle() if towards.length() > 0.5 else (-aim).angle()
	var ring := (radius + GAP) / sin(PI / count) if count > 1 else 0.0
	for i in count:
		var pos := center + Vector2.from_angle(start + TAU * i / count) * ring
		if fx:
			fx.telegraph(pos, radius, d.windup, true)
			_schedule_fall(c, fx, pos, radius, d.windup)
		zones.add_field(pos, radius, damage, d.param(&"interval", 0.3), ticks, COLOR, d.windup)
	if fx:
		fx.arrow_rise(origin)
	Audio.play(&"arrow_rain")


## Starts the falling arrows so that they land when the windup ends.
func _schedule_fall(c: AbilityCaster, fx: Effects, pos: Vector2, radius: float, windup: float) -> void:
	var life := minf(FALL_TIME, windup)
	var wait := windup - life
	if wait <= 0.0:
		fx.arrow_fall(pos, radius, life)
		return
	var id := fx.get_instance_id()  # by id: the scene may be gone when the timer fires
	c.get_tree().create_timer(wait).timeout.connect(func() -> void:
		var live := instance_from_id(id) as Effects
		if live:
			live.arrow_fall(pos, radius, life))

class_name PhaseBehavior
extends AbilityBehavior
## Phase Shift: instant to cast, then the Wizard is a ghost for `duration` seconds: unhittable and
## faster, and free to move and cast. The timed state lives on the Player (Player.start_phase), so
## the cast never blocks other abilities.
## Upgrades: Long Phase (phase.duration), Swift Phase (phase.speed_bonus), Ghost Touch (phase.touch).


func cast(c: AbilityCaster, _aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var duration := c.value(d, &"duration", d.duration)
	var speed_bonus := c.value(d, &"speed_bonus", d.speed_multiplier - 1.0)
	var touch_level := int(c.value(d, &"touch", 0.0))
	# Ghost Touch: `damage` is the per-level damage of each tick.
	var touch_damage := c.damage_of(d) * touch_level if touch_level > 0 else 0.0
	c.player.start_phase(duration, 1.0 + speed_bonus, touch_damage, d.immunity_after)
	var fx := Effects.get_for(c)
	if fx:
		fx.ring(c.player.global_position, 18.0)
	c.play_sfx(d)

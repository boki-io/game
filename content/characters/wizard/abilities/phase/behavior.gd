class_name PhaseBehavior
extends AbilityBehavior
## Phase Shift: instant to cast, then the Wizard is a ghost for `duration` seconds: unhittable and
## faster, and free to move and cast. When the phase ends, a belt of orbs circles the Wizard for a
## couple of seconds and damages enemies it sweeps through. The timed state lives on the Player
## (Player.start_phase), so the cast never blocks other abilities.
## Upgrades: Long Phase (phase.duration), Swift Phase (phase.speed_bonus), Ghost Touch (phase.touch),
## Orbital Ring (phase.orbs and phase.belt_time).

const BELT_ORBS := 5.0
const BELT_TIME := 2.0  # seconds, starting when the phase ends
const BELT_TURNS := 2.0  # revolutions per second
const TOUCH_RATIO := 0.75  # Ghost Touch tick damage as a share of the orb damage, per upgrade level


func cast(c: AbilityCaster, _aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var duration := c.value(d, &"duration", d.duration)
	var speed_bonus := c.value(d, &"speed_bonus", d.speed_multiplier - 1.0)
	var damage := c.damage_of(d)  # also used for the belt orbs, read now
	var touch_level := int(c.value(d, &"touch", 0.0))
	var belt := {
		"count": int(c.value(d, &"orbs", BELT_ORBS)),
		"radius": c.value(d, &"radius", d.radius),
		"turns": BELT_TURNS,
		"damage": damage,
		"duration": c.value(d, &"belt_time", BELT_TIME),
	}
	c.player.start_phase(duration, 1.0 + speed_bonus, damage * TOUCH_RATIO * touch_level, d.immunity_after, belt)
	var fx := Effects.get_for(c)
	if fx:
		fx.ring(c.player.global_position, 18.0)
	c.play_sfx(d)

class_name ThornNova
extends RelicBehavior
## Thorn Nova (spec 1.0, section 4.3): every `cooldown` seconds `thorns` thorns fly out evenly spaced and a bramble is
## dropped at the player's feet. The bramble slows what it covers and, from level 3, hurts it. The projectile pool is
## shared with the Wizard's bolts, so a full pool gives a short volley.

const SPEED := 200.0
const BRAMBLE_INTERVAL := 0.5
const SLOW_SECONDS := 0.75  # longer than the interval, so there is no gap between ticks

var _cooldown_left := 0.0


func cooldown_fraction() -> float:
	return clampf(_cooldown_left / float(params().cooldown), 0.0, 1.0)


func set_level(new_level: int) -> void:
	super(new_level)
	_cooldown_left = minf(_cooldown_left, float(params().cooldown))


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left > 0.0:
		return
	_cooldown_left = float(params().cooldown)
	_cast()


func _cast() -> void:
	var p := params()
	var origin := player.global_position
	var pool := PlayerProjectiles.get_for(self)
	if pool:
		var count: int = p.thorns
		for i in count:
			var dir := Vector2.from_angle(TAU * i / count)
			if not pool.fire(origin, dir, SPEED, dmg(float(p.damage)), float(p.range), 0):
				break  # the pool is full: a short volley is fine
	var zones := DamageZones.get_for(self)
	if zones:
		var ticks := int(roundf(float(p.bramble_life) / BRAMBLE_INTERVAL))
		zones.add_field(origin, float(p.bramble_radius), dmg(float(p.bramble_tick)), BRAMBLE_INTERVAL, ticks,
			data.color, 0.0, {slow = {factor = float(p.slow_factor), seconds = SLOW_SECONDS}})
	Audio.play(&"relic_nova")

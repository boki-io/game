class_name EnemyStatus
extends RefCounted
## The timed effects on one Enemy (spec 1.0 section 2): slow, freeze, vulnerable and burn. Numbers only, no nodes.
## The Enemy owns one, applies slow inside chase()/settle(), treats freeze like a stun and runs advance() every
## physics frame while `any_active` is set (an enemy with nothing on it does no status work at all).

const BURN_INTERVAL := 0.5

## True while any of the four is running; the Enemy skips every status call when it is false.
var any_active := false
## 1.0 when not slowed, otherwise the lowest factor applied (0.6 = 40% slower).
var slow_factor := 1.0
var slow_left := 0.0
var freeze_left := 0.0
var vulnerable_mult := 1.0
var vulnerable_left := 0.0
var burn_dps := 0.0
var burn_left := 0.0
var _burn_t := 0.0


func reset() -> void:
	any_active = false
	slow_factor = 1.0
	slow_left = 0.0
	freeze_left = 0.0
	vulnerable_mult = 1.0
	vulnerable_left = 0.0
	burn_dps = 0.0
	burn_left = 0.0
	_burn_t = 0.0


## The lowest factor wins, the time is the longest of the two.
func apply_slow(factor: float, seconds: float) -> void:
	if seconds <= 0.0:
		return
	slow_factor = factor if slow_left <= 0.0 else minf(slow_factor, factor)
	slow_left = maxf(slow_left, seconds)
	any_active = true


## The time is the longest. Also applies vulnerable `vulnerable` for the same seconds.
func apply_freeze(seconds: float, vulnerable: float) -> void:
	if seconds <= 0.0:
		return
	freeze_left = maxf(freeze_left, seconds)
	apply_vulnerable(vulnerable, seconds)
	any_active = true


## The highest multiplier wins, the time is the longest.
func apply_vulnerable(mult: float, seconds: float) -> void:
	if seconds <= 0.0 or mult <= 1.0:
		return
	vulnerable_mult = mult if vulnerable_left <= 0.0 else maxf(vulnerable_mult, mult)
	vulnerable_left = maxf(vulnerable_left, seconds)
	any_active = true


## The highest dps wins, the time is reset to `seconds`.
func ignite(dps: float, seconds: float) -> void:
	if seconds <= 0.0 or dps <= 0.0:
		return
	if burn_left <= 0.0:
		_burn_t = BURN_INTERVAL
		burn_dps = dps
	else:
		burn_dps = maxf(burn_dps, dps)
	burn_left = seconds
	any_active = true


## The damage multiplier `take_damage` applies right now.
func damage_multiplier() -> float:
	return vulnerable_mult if vulnerable_left > 0.0 else 1.0


## Counts every timer down and returns the burn damage due this frame (0 when none). A frame longer than one
## burn interval returns several ticks at once, so the total does not depend on the frame rate.
func advance(delta: float) -> float:
	var burn := 0.0
	if burn_left > 0.0:
		var span := minf(delta, burn_left)
		burn_left -= delta
		_burn_t -= span
		while _burn_t <= 0.0001:  # a little slack: float error must not cost the last tick
			burn += burn_dps * BURN_INTERVAL
			_burn_t += BURN_INTERVAL
	if slow_left > 0.0:
		slow_left -= delta
		if slow_left <= 0.0:
			slow_factor = 1.0
	if freeze_left > 0.0:
		freeze_left = maxf(freeze_left - delta, 0.0)
	if vulnerable_left > 0.0:
		vulnerable_left -= delta
		if vulnerable_left <= 0.0:
			vulnerable_mult = 1.0
	any_active = slow_left > 0.0 or freeze_left > 0.0 or vulnerable_left > 0.0 or burn_left > 0.0
	return burn

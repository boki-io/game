class_name FrostComet
extends RelicBehavior
## Stub: the real behavior comes in a later build step (spec 1.0, section 9).

var _cooldown_left := 0.0


func cooldown_fraction() -> float:
	return clampf(_cooldown_left / float(params().cooldown), 0.0, 1.0)

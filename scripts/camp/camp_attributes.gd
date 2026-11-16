class_name CampAttributes
extends RefCounted
## Applies camp attribute levels to a Stats (once, at Player creation) and sums Greed's coin chance (spec 0.7, 9).


## Writes the adds and scales of every attribute at its level into `stats`. Level 0 or unknown ids change nothing.
static func apply(stats: Stats, levels: Dictionary) -> void:
	for a in AttributeRegistry.all():
		var level: int = clampi(int(levels.get(a.id, 0)), 0, a.max_level)
		if level == 0:
			continue
		for key: StringName in a.adds:
			stats.add(key, a.adds[key] * level)
		for key: StringName in a.scales:
			stats.multiply(key, 1.0 + a.scales[key] * level)


## Sum of coin_chance x level over the attributes (a fraction, 0.14 at Greed 7).
static func coin_bonus(levels: Dictionary) -> float:
	var total := 0.0
	for a in AttributeRegistry.all():
		total += a.coin_chance * clampi(int(levels.get(a.id, 0)), 0, a.max_level)
	return total

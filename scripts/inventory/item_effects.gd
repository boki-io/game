class_name ItemEffects
extends RefCounted
## Applies worn items to a Stats (once, at Player creation), the way CampAttributes.apply does for attributes (spec 1.4).


## Adds `adds` and multiplies by `1 + scales` for every item.
static func apply(stats: Stats, items: Array[ItemData]) -> void:
	for item in items:
		for key: StringName in item.adds:
			stats.add(key, item.adds[key])
		for key: StringName in item.scales:
			stats.multiply(key, 1.0 + item.scales[key])

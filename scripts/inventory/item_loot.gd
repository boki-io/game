class_name ItemLoot
extends RefCounted
## Which item a drop holds (spec 1.5). Static and free of autoloads, so a test can seed it.


## The id of a random item that is neither in `owned` (unlocked) nor in `lying` (already on the ground), or &"" when none
## is left. A rating is drawn by `loot.weights` among the ratings that still have such an item (a rating with none is
## skipped, not re-rolled), then one of its candidates uniformly. `rng` makes the result reproducible.
static func pick(owned: Array, lying: Array, loot: LootData, rng: RandomNumberGenerator) -> StringName:
	var by_rating := {}
	for item in ItemRegistry.all():
		if item.id in owned or item.id in lying:
			continue
		if not by_rating.has(item.rating):
			by_rating[item.rating] = []
		by_rating[item.rating].append(item.id)
	var total := 0.0
	for rating: StringName in ItemData.RATINGS:
		if by_rating.has(rating):
			total += maxf(float(loot.weights.get(rating, 0.0)), 0.0)
	if total <= 0.0:
		return &""
	var roll := rng.randf() * total
	var chosen: StringName = &""
	for rating: StringName in ItemData.RATINGS:
		if not by_rating.has(rating):
			continue
		var w := maxf(float(loot.weights.get(rating, 0.0)), 0.0)
		if w <= 0.0:
			continue
		chosen = rating
		roll -= w
		if roll < 0.0:
			break
	var ids: Array = by_rating[chosen]
	return ids[rng.randi() % ids.size()]

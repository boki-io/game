extends SceneTree
## ItemLoot.pick (spec 1.5): the rating shares of 3000 seeded picks, owned and lying items never picked, a fully owned rating
## skipped with the shares rescaled, nothing left gives &"", and the same seed gives the same sequence.
## Run: godot --headless --path . --script tests/inventory/item_loot.gd

const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")
const Loot := preload("res://scripts/inventory/item_loot.gd")
const LootS := preload("res://scripts/inventory/loot_data.gd")

const PICKS := 3000

var _failed := false
var _loot


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_loot = LootS.new()
	var ratings := [&"standard", &"epic", &"legendary"]
	for r in ratings:
		for i in 4:
			var it = ItemDataS.new()
			it.id = StringName("%s_%d" % [r, i])
			it.rating = r
			Reg.test_items.append(it)
	_check(_loot.weights[&"standard"] == 70 and _loot.weights[&"epic"] == 25 and _loot.weights[&"legendary"] == 5, "default weights 70/25/5")
	_check(_loot.pick_distance == 14.0 and _loot.max_lying == 6, "default pick distance 14 and 6 lying")
	var file: Resource = load("res://content/items/loot.tres")
	_check(file != null and file.weights == _loot.weights and file.pick_distance == 14.0 and file.max_lying == 6, "loot.tres holds the defaults")

	var shares := _shares([], [], 1)
	_check(_near(shares[&"standard"], 0.70) and _near(shares[&"epic"], 0.25) and _near(shares[&"legendary"], 0.05), "shares within 3 points of 70/25/5: %s" % [shares])

	# Owned and lying items are never picked.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var owned := [&"standard_0", &"epic_1", &"legendary_2"]
	var lying := [&"standard_1", &"epic_2", &"legendary_3"]
	var bad := 0
	for i in PICKS:
		var id: StringName = Loot.pick(owned, lying, _loot, rng)
		if id in owned or id in lying or id == &"":
			bad += 1
	_check(bad == 0, "owned and lying items are never picked (%d bad)" % bad)

	# A fully owned rating is skipped; the shares rescale to 25/30 and 5/30.
	var all_standard: Array = []
	for i in 4:
		all_standard.append(StringName("standard_%d" % i))
	shares = _shares(all_standard, [], 3)
	_check(shares.get(&"standard", 0.0) == 0.0, "an owned rating is never returned")
	_check(_near(shares[&"epic"], 25.0 / 30.0) and _near(shares[&"legendary"], 5.0 / 30.0), "the shares rescale: %s" % [shares])
	# Fully lying counts the same.
	shares = _shares([], all_standard, 4)
	_check(shares.get(&"standard", 0.0) == 0.0, "a rating whose items all lie is skipped")

	# Everything owned or lying: nothing.
	var every: Array = []
	for it in Reg.test_items:
		every.append(it.id)
	_check(Loot.pick(every, [], _loot, rng) == &"", "everything owned gives &\"\"")
	_check(Loot.pick([], every, _loot, rng) == &"", "everything lying gives &\"\"")
	_check(Loot.pick(every.slice(0, 6), every.slice(6), _loot, rng) == &"", "owned plus lying covering everything gives &\"\"")

	# The same seed, the same sequence.
	var a := _sequence(99)
	var b := _sequence(99)
	var c := _sequence(100)
	_check(a == b, "the same seed gives the same sequence")
	_check(a != c, "another seed gives another sequence")

	Reg.test_items.clear()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _near(share: float, want: float) -> bool:
	return absf(share - want) <= 0.03


func _shares(owned: Array, lying: Array, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var counts := {}
	for i in PICKS:
		var id: StringName = Loot.pick(owned, lying, _loot, rng)
		var rating: StringName = Reg.find(id).rating
		counts[rating] = counts.get(rating, 0) + 1
	var out := {}
	for r in counts:
		out[r] = float(counts[r]) / PICKS
	return out


func _sequence(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for i in 40:
		out.append(Loot.pick([], [], _loot, rng))
	return out

extends SceneTree
## The 18 shipped items (spec 1.5 section 2): three per type (one of each rating), ids equal folder names, unique names,
## allowed stat keys and no mana, the table of the spec matches the data (stats, stat_text, relic), relics valid, distinct
## and only on legendaries (not the ring), bonuses rise with rating, flavour at most 40 characters, three rating colours.
## Run: godot --headless --path . --script tests/inventory/item_content.gd

const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")
const InventoryS := preload("res://scripts/inventory/inventory.gd")
const STAT_KEYS := [&"max_hp", &"damage", &"move_speed", &"pickup_radius", &"hp_regen", &"mana_regen", &"max_mana", &"auto_speed", &"cooldown"]
const MANA_KEYS := [&"max_mana", &"mana_regen"]
## id -> [slot, rating, relic_id, stat_text]
const TABLE := {
	"leather_cap": ["helmet", "standard", "", "+0.3 HP/s"],
	"warden_helm": ["helmet", "epic", "", "+0.6 HP/s, +10 max HP"],
	"stormcaller_crown": ["helmet", "legendary", "storm_orbs", "+1 HP/s, +20 max HP"],
	"padded_vest": ["chestplate", "standard", "", "+15 max HP"],
	"reinforced_mail": ["chestplate", "epic", "", "+30 max HP, +0.3 HP/s"],
	"thornmail": ["chestplate", "legendary", "thorn_nova", "+50 max HP, +0.5 HP/s"],
	"bone_charm": ["necklace", "standard", "", "+4% damage"],
	"amber_pendant": ["necklace", "epic", "", "+8% damage, +15% pickup range"],
	"frostfall_pendant": ["necklace", "legendary", "frost_comet", "+12% damage, +30% pickup range"],
	"copper_ring": ["ring", "standard", "", "+4% attack speed"],
	"silver_ring": ["ring", "epic", "", "+8% attack speed, +3% damage"],
	"ring_of_mastery": ["ring", "legendary", "", "+14% attack speed, +6% damage"],
	"cloth_trousers": ["pants", "standard", "", "-4% ability cooldowns"],
	"hardened_greaves": ["pants", "epic", "", "+10 max HP, -8% ability cooldowns"],
	"tidewalker_greaves": ["pants", "legendary", "tidal_wave", "+20 max HP, -12% ability cooldowns"],
	"worn_boots": ["shoes", "standard", "", "+4% move speed"],
	"swift_boots": ["shoes", "epic", "", "+8% move speed, +20% pickup range"],
	"emberstep_boots": ["shoes", "legendary", "fire_trail", "+12% move speed, -4% ability cooldowns"],
}

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## The absolute bonus of one stat key over adds and scales.
func _bonus(it, key: StringName) -> float:
	return absf(float(it.adds.get(key, 0.0))) + absf(float(it.scales.get(key, 0.0)))


func _init() -> void:
	await process_frame
	var items: Array = Reg.all()
	_check(items.size() == 18, "the registry holds 18 items: %d" % items.size())
	var ids := {}
	var names := {}
	var by_type := {}
	var relics := {}
	for it in items:
		var id := String(it.id)
		_check(it.resource_path == "res://content/items/%s/item.tres" % id, "item %s: id equals its folder name (%s)" % [id, it.resource_path])
		_check(not ids.has(id) and not names.has(it.display_name), "item %s: unique id and name" % id)
		ids[id] = true
		names[it.display_name] = true
		_check(it.slot in InventoryS.TYPES, "item %s: valid type" % id)
		_check(it.rating in ItemDataS.RATINGS, "item %s: valid rating" % id)
		if not by_type.has(it.slot):
			by_type[it.slot] = {}
		_check(not by_type[it.slot].has(it.rating), "item %s: one of each rating per type" % id)
		by_type[it.slot][it.rating] = it
		_check(it.description.length() <= 40, "item %s: flavour at most 40 characters (%d)" % [id, it.description.length()])
		_check(not it.adds.is_empty() or not it.scales.is_empty(), "item %s has a bonus" % id)
		for key in it.adds:
			_check(key in STAT_KEYS and not key in MANA_KEYS, "item %s: add key %s is allowed and not mana" % [id, key])
		for key in it.scales:
			_check(key in STAT_KEYS and not key in MANA_KEYS, "item %s: scale key %s is allowed and not mana" % [id, key])
		_check(TABLE.has(id), "item %s is in the spec table" % id)
		if TABLE.has(id):
			var row: Array = TABLE[id]
			_check(String(it.slot) == row[0] and String(it.rating) == row[1], "item %s: type and rating match the table" % id)
			_check(String(it.relic_id) == row[2], "item %s: relic matches the table (%s)" % [id, it.relic_id])
			_check(it.stat_text() == row[3], "item %s: stat_text is '%s', expected '%s'" % [id, it.stat_text(), row[3]])
		if it.relic_id != &"":
			_check(it.rating == &"legendary", "item %s: only a legendary grants a relic" % id)
			_check(RelicRegistry.find(it.relic_id) != null, "item %s: relic %s is registered" % [id, it.relic_id])
			_check(not relics.has(it.relic_id), "relic %s is granted by exactly one item" % it.relic_id)
			relics[it.relic_id] = true
	_check(by_type.size() == 6, "six types: %d" % by_type.size())
	_check(relics.size() == 5, "five granted relics: %d" % relics.size())
	var ring = Reg.find(&"ring_of_mastery")
	_check(ring != null and ring.relic_id == &"" and ring.rating == &"legendary", "the ring legendary grants nothing")
	for type in by_type:
		var row: Dictionary = by_type[type]
		_check(row.size() == 3, "type %s has three ratings" % type)
		if row.size() != 3:
			continue
		# The standard item's stat (its first key) rises standard < epic < legendary (an epic may add a stat the legendary
		# swaps for a relic, so the sum over all keys is not compared).
		var std = row[&"standard"]
		var key: StringName = (std.adds.keys() + std.scales.keys())[0]
		var b0 := _bonus(row[&"standard"], key)
		var b1 := _bonus(row[&"epic"], key)
		var b2 := _bonus(row[&"legendary"], key)
		_check(b0 < b1 and b1 < b2, "type %s: %s rises with rating (%s, %s, %s)" % [type, key, b0, b1, b2])
	var colors := {}
	for r in ItemDataS.RATINGS:
		colors[ItemDataS.rating_color(r)] = true
	_check(colors.size() == 3, "three distinct rating colours")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

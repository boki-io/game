extends SceneTree
## The inventory model (spec 1.4): the slot table, the pool, equipping rules (own slot, rings, replacing, moving, taking
## an item from another character, the no-ops), unequipping, the `changed` signal, per-character loadouts, ItemEffects, and
## the checks every shipped item must pass (none today). Nothing here is seeded.
## Run: godot --headless --path . --script tests/inventory/inventory_model.gd

const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")
const InventoryS := preload("res://scripts/inventory/inventory.gd")
const Effects := preload("res://scripts/inventory/item_effects.gd")
## Stat keys items may use (Stats has no registry of its own).
const STAT_KEYS := [&"max_hp", &"damage", &"move_speed", &"pickup_radius", &"hp_regen", &"mana_regen", &"max_mana", &"auto_speed", &"cooldown"]

var _failed := false
var _changes := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _item(id: String, slot: String, adds := {}, scales := {}) -> Resource:
	var it = ItemDataS.new()
	it.id = StringName(id)
	it.display_name = id.capitalize()
	it.slot = StringName(slot)
	it.adds = adds
	it.scales = scales
	return it


func _init() -> void:
	await process_frame
	var shipped := Reg.all().size()
	_content(shipped)
	for it in [_item("cap", "helmet"), _item("mail", "chestplate"), _item("pendant", "necklace"), _item("band", "ring"),
			_item("loop", "ring"), _item("stud", "ring"), _item("greaves", "pants"), _item("boots", "shoes"), _item("crown", "helmet")]:
		Reg.test_items.append(it)
	_slots()
	_pool()
	_equip()
	_rings()
	_characters()
	_unequip_and_signal()
	_effects()
	Reg.test_items.clear()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _fresh():
	var inv = InventoryS.new()
	for it in Reg.test_items:
		inv.unlock(it.id)
	_changes = 0
	inv.changed.connect(func() -> void: _changes += 1)
	return inv


## Every item in the registry (none ships in 1.4) passes these; the next PR's items are checked by them.
func _content(count: int) -> void:
	for it in Reg.all():
		_check(it.id != &"" and it.slot in InventoryS.TYPES, "item %s has an id and a valid slot type" % it.id)
		_check(it.description.length() <= 80, "item %s: description at most 80 characters" % it.id)
		for key in it.adds:
			_check(key in STAT_KEYS, "item %s: add key %s is a known stat" % [it.id, key])
		for key in it.scales:
			_check(key in STAT_KEYS, "item %s: scale key %s is a known stat" % [it.id, key])
	_check(count == 0, "no item ships in 1.4 (the next PR adds them): %d" % count)


func _slots() -> void:
	_check(InventoryS.SLOTS == [&"helmet", &"chestplate", &"necklace", &"ring_1", &"ring_2", &"pants", &"shoes"], "seven slots in screen order")
	_check(InventoryS.TYPES.size() == 6, "six item types")
	_check(InventoryS.slots_for(&"ring") == [&"ring_1", &"ring_2"], "a ring fits both ring slots")
	_check(InventoryS.slots_for(&"pants") == [&"pants"] and InventoryS.slots_for(&"nope").is_empty(), "other types fit their own slot, unknown none")


func _pool() -> void:
	var inv = InventoryS.new()
	_changes = 0
	inv.changed.connect(func() -> void: _changes += 1)
	_check(not inv.unlock(&"ghost") and _changes == 0, "an unknown id cannot be unlocked")
	_check(inv.unlock(&"boots") and inv.unlock(&"cap"), "known ids unlock")
	_check(not inv.unlock(&"cap") and inv.unlocked == [&"boots", &"cap"], "a duplicate is refused and the order is kept: %s" % [inv.unlocked])
	_check(_changes == 2, "unlock emits changed once per new item")
	_check(inv.equip(&"knight", &"mail") == &"", "a locked item cannot be worn")
	_check(inv.equip(&"knight", &"ghost") == &"", "an unknown item cannot be worn")


func _equip() -> void:
	var inv = _fresh()
	var expect := {&"cap": &"helmet", &"mail": &"chestplate", &"pendant": &"necklace", &"greaves": &"pants", &"boots": &"shoes"}
	for id in expect:
		_check(inv.equip(&"knight", id) == expect[id], "%s goes to %s" % [id, expect[id]])
	_check(inv.worn(&"knight", &"helmet").id == &"cap" and inv.worn(&"knight", &"shoes").id == &"boots", "worn() returns the items")
	_check(inv.worn_items(&"knight").size() == 5 and inv.worn_items(&"knight")[0].id == &"cap", "worn_items in slot order")
	_changes = 0
	_check(inv.equip(&"knight", &"cap") == &"helmet" and _changes == 0, "re-equipping a worn item is a no-op and returns its slot")
	_check(inv.equip(&"knight", &"cap", &"helmet") == &"helmet" and _changes == 0, "equipping into its own slot is a no-op")
	_check(inv.equip(&"knight", &"cap", &"shoes") == &"" and _changes == 0, "a slot that does not fit refuses and changes nothing")
	_check(inv.worn(&"knight", &"shoes").id == &"boots", "the refused equip left the shoes alone")
	# A second helmet replaces the first, which stays in the pool.
	_check(inv.equip(&"knight", &"crown") == &"helmet" and _changes == 1, "a helmet replaces the worn one")
	_check(inv.worn(&"knight", &"helmet").id == &"crown" and inv.is_unlocked(&"cap") and inv.wearer_of(&"cap") == &"", "the replaced item is back in the pool, unworn")


func _rings() -> void:
	var inv = _fresh()
	_check(inv.equip(&"knight", &"band") == &"ring_1", "the first ring takes ring_1")
	_check(inv.equip(&"knight", &"loop") == &"ring_2", "the second takes ring_2")
	_check(inv.equip(&"knight", &"band") == &"ring_1", "re-equipping a worn ring returns its slot")
	_changes = 0
	_check(inv.equip(&"knight", &"stud") == &"ring_1" and _changes == 1, "with both full a third ring replaces ring_1")
	_check(inv.worn(&"knight", &"ring_1").id == &"stud" and inv.worn(&"knight", &"ring_2").id == &"loop" and inv.wearer_of(&"band") == &"", "ring_2 is kept, the old ring_1 is unworn")
	# Moving a worn ring to a chosen slot.
	_check(inv.equip(&"knight", &"loop", &"ring_1") == &"ring_1", "an explicit slot moves a worn ring")
	_check(inv.worn(&"knight", &"ring_2") == null and inv.worn(&"knight", &"ring_1").id == &"loop" and inv.wearer_of(&"stud") == &"", "the moved ring left its old slot and displaced the other")
	_check(inv.equip(&"knight", &"band", &"helmet") == &"", "a ring does not fit the helmet slot")


func _characters() -> void:
	var inv = _fresh()
	inv.equip(&"knight", &"cap")
	inv.equip(&"wizard", &"mail")
	_check(inv.worn(&"wizard", &"helmet") == null and inv.worn(&"knight", &"chestplate") == null, "loadouts are per character")
	_check(inv.wearer_of(&"cap") == &"knight" and inv.wearer_of(&"mail") == &"wizard", "wearer_of")
	_changes = 0
	_check(inv.equip(&"wizard", &"cap") == &"helmet" and _changes == 1, "an item worn by another character moves to the new one")
	_check(inv.wearer_of(&"cap") == &"wizard" and inv.worn(&"knight", &"helmet") == null, "the first character no longer wears it")
	_check(inv.worn_state() == {&"wizard": {&"helmet": &"cap", &"chestplate": &"mail"}}, "worn_state lists non-empty loadouts: %s" % [inv.worn_state()])


func _unequip_and_signal() -> void:
	var inv = _fresh()
	inv.equip(&"knight", &"boots")
	_changes = 0
	_check(not inv.unequip(&"knight", &"helmet") and _changes == 0, "unequipping an empty slot is false and silent")
	_check(inv.unequip(&"knight", &"shoes") and _changes == 1, "unequip works and emits once")
	_check(inv.is_unlocked(&"boots") and inv.worn(&"knight", &"shoes") == null, "an unequipped item stays in the pool")
	inv.set_state([&"cap"], {&"knight": {&"helmet": &"cap"}})
	_check(_changes == 1 and inv.worn(&"knight", &"helmet").id == &"cap" and inv.unlocked == [&"cap"], "set_state replaces the contents without emitting")


func _effects() -> void:
	var stats := Node.new()
	stats.set_script(load("res://scripts/systems/stats.gd"))
	var items: Array = [_item("a", "helmet", {&"max_hp": 10.0}, {&"damage": 0.2}), _item("b", "shoes", {&"max_hp": 5.0}, {&"damage": 0.1, &"move_speed": -0.1})]
	var typed: Array[Resource] = []
	for it in items:
		typed.append(it)
	Effects.apply(stats, _as_items(items))
	_check(is_equal_approx(stats.value(&"max_hp", 100.0), 115.0), "adds sum: max_hp 100 -> %s" % stats.value(&"max_hp", 100.0))
	_check(is_equal_approx(stats.value(&"damage", 10.0), 10.0 * 1.2 * 1.1), "scales multiply: damage 10 -> %s" % stats.value(&"damage", 10.0))
	_check(is_equal_approx(stats.value(&"move_speed", 90.0), 81.0), "a negative scale lowers: move_speed 90 -> %s" % stats.value(&"move_speed", 90.0))
	var none := Node.new()
	none.set_script(load("res://scripts/systems/stats.gd"))
	Effects.apply(none, _as_items([]))
	_check(none.value(&"max_hp", 100.0) == 100.0, "no items change nothing")
	stats.free()
	none.free()


## An Array[ItemData] from loose items (the parameter is typed; the test cannot name ItemData without the class cache).
func _as_items(items: Array) -> Array:
	return Array(items, TYPE_OBJECT, &"Resource", ItemDataS)

extends SceneTree
## Equipped items change a hero's stats (spec 1.4): a Player created with `equipment` gets the adds and scales (max HP,
## speed), stacked with camp attributes; one without gets nothing; a run's player and the hub's player get the loadout of
## their own character from GameSession.inventory and never another's.
## Run: godot --headless --path . --script tests/inventory/inventory_stats.gd

const SG := preload("res://scripts/systems/save_game.gd")
const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")

var _failed := false
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _item(id: String, slot: String, adds := {}, scales := {}) -> Resource:
	var it = ItemDataS.new()
	it.id = StringName(id)
	it.slot = StringName(slot)
	it.adds = adds
	it.scales = scales
	return it


func _character(id: StringName):
	for c in CharacterRegistry.all():
		if c.id == id:
			return c
	return null


func _init() -> void:
	await process_frame
	await process_frame
	_F = load("res://tests/fixture.gd")
	SG.override_path = ""  # nothing is written to the player's save
	Reg.test_items.append(_item("tough_cap", "helmet", {&"max_hp": 25.0}))
	Reg.test_items.append(_item("swift_boots", "shoes", {}, {&"move_speed": 0.1}))
	Reg.test_items.append(_item("mage_hat", "helmet", {&"max_hp": 7.0}))
	var inv = root.get_node("GameSession").inventory
	inv.set_state([], {})
	for id in [&"tough_cap", &"swift_boots", &"mage_hat"]:
		inv.unlock(id)
	inv.equip(&"knight", &"tough_cap")
	inv.equip(&"knight", &"swift_boots")
	inv.equip(&"wizard", &"mage_hat")

	await _direct()
	await _run()
	await _hub()
	inv.set_state([], {})
	Reg.test_items.clear()
	SG.override_path = null
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## A Player built the way the creators do it, with and without `equipment`, and with attributes too.
func _direct() -> void:
	var knight = _character(&"knight")
	var base_hp: float = knight.max_hp
	var inv = root.get_node("GameSession").inventory
	var holder := Node2D.new()
	root.add_child(holder)
	var bare = load("res://scenes/player.tscn").instantiate()
	bare.character = knight
	holder.add_child(bare)
	await process_frame
	_check(is_equal_approx(bare.health.max_health, base_hp), "no equipment: max HP is the character's (%s)" % bare.health.max_health)
	_check(is_equal_approx(bare.stats.value(&"move_speed", 100.0), 100.0), "no equipment: no speed bonus")

	var worn = load("res://scenes/player.tscn").instantiate()
	worn.character = knight
	worn.equipment = Array(inv.worn_items(&"knight"), TYPE_OBJECT, &"Resource", ItemDataS)
	holder.add_child(worn)
	await process_frame
	_check(is_equal_approx(worn.health.max_health, base_hp + 25.0), "equipment: max HP +25 (%s)" % worn.health.max_health)
	_check(is_equal_approx(worn.stats.value(&"move_speed", 100.0), 110.0), "equipment: move speed x1.1 (%s)" % worn.stats.value(&"move_speed", 100.0))

	var both = load("res://scenes/player.tscn").instantiate()
	both.character = knight
	both.attribute_levels = {&"toughness": 2}
	both.equipment = Array(inv.worn_items(&"knight"), TYPE_OBJECT, &"Resource", ItemDataS)
	holder.add_child(both)
	await process_frame
	_check(both.health.max_health > worn.health.max_health, "equipment stacks with camp attributes (%s > %s)" % [both.health.max_health, worn.health.max_health])
	holder.free()
	await process_frame


## main.tscn's player wears the loadout of the character of the run.
func _run() -> void:
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	var p = _F.player()
	_check(p.equipment.size() == 2 and p.equipment[0].id == &"tough_cap", "the Knight's run player wears the Knight's items")
	_check(is_equal_approx(p.health.max_health, p.character.max_hp + 25.0), "and has the +25 max HP (%s)" % p.health.max_health)
	main.queue_free()
	await process_frame
	paused = false
	main = _F.start_run(self, &"wizard")
	await _F.frames(self, 2)
	p = _F.player()
	_check(p.equipment.size() == 1 and p.equipment[0].id == &"mage_hat", "the Wizard's run player wears the Wizard's items only")
	_check(is_equal_approx(p.health.max_health, p.character.max_hp + 7.0), "the Wizard has +7 max HP, not the Knight's +25 (%s)" % p.health.max_health)
	main.queue_free()
	await process_frame
	paused = false


## The hub's player (walk mode as a character) wears that character's loadout.
func _hub() -> void:
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(0.5).timeout
	for i in hub.characters.size():
		if hub.characters[i].id == &"knight":
			hub._enter_walk(i, Vector2(480, 200), true)
	await create_timer(0.3).timeout
	var p = hub.player
	_check(p != null and p.equipment.size() == 2, "the hub's Knight wears the Knight's items")
	_check(p != null and is_equal_approx(p.health.max_health, p.character.max_hp + 25.0), "and has the +25 max HP in the hub (%s)" % (p.health.max_health if p else -1.0))
	hub.queue_free()
	await process_frame

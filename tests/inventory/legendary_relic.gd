extends SceneTree
## A worn legendary item grants a relic for the whole run in an extra slot (spec 1.5, section 4): PlayerRelics.grant,
## Player._ready, the roller rule, RunProgress.restore, the HUD slots; and pickup_radius reaching the collector.
## Run: godot --headless --path . --script tests/inventory/legendary_relic.gd

const SG := preload("res://scripts/systems/save_game.gd")
const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")

var _failed := false
var _holder: Node2D
var _LUR: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _item(id: String, slot: String, relic := "", adds := {}, scales := {}) -> Resource:
	var it = ItemDataS.new()
	it.id = StringName(id)
	it.slot = StringName(slot)
	it.relic_id = StringName(relic)
	it.adds = adds
	it.scales = scales
	return it


func _equip(items: Array) -> Array:
	return Array(items, TYPE_OBJECT, &"Resource", ItemDataS)


## A Player in the tree (not hub mode unless asked) wearing `items`.
func _player(items: Array, hub := false) -> Node:
	var p = load("res://scenes/player.tscn").instantiate()
	p.character = CharacterRegistry.all()[0]
	p.hub_mode = hub
	p.equipment = _equip(items)
	_holder.add_child(p)
	await process_frame
	return p


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _init() -> void:
	await process_frame
	await process_frame
	SG.override_path = ""  # nothing is written to the player's save
	var F: GDScript = load("res://tests/fixture.gd")
	_LUR = load("res://scripts/relics/level_up_roller.gd")
	_holder = Node2D.new()
	root.add_child(_holder)
	var trail = _item("trail_hat", "helmet", "fire_trail")
	var orbs = _item("orb_cape", "cape", "storm_orbs")
	var ring = _item("plain_ring", "ring")
	var pendant = _item("range_pendant", "pendant", "", {}, {&"pickup_radius": 0.15})
	Reg.test_items.append_array([trail, orbs, ring, pendant])

	# Pickup range reaches the collector.
	var p = await _player([pendant])
	_check(is_equal_approx(p.collector._shape.radius, 48.0 * 1.15), "pickup_radius item: collector radius 48 x 1.15 (%s)" % p.collector._shape.radius)
	p.free()
	p = await _player([])
	_check(is_equal_approx(p.collector._shape.radius, 48.0), "no item: collector radius 48")
	p.free()

	# Grants at creation.
	p = await _player([trail])
	_check(p.relics.owns(&"fire_trail") and p.relics.level_of(RelicRegistry.find(&"fire_trail")) == 1, "granted relic owned at level 1")
	_check(p.relics.slot_of(&"fire_trail") == 0, "in slot 0")
	_check(p.relics.slots == 5 and p.relics.free_slots() == 4, "slots 5, free 4 (%d, %d)" % [p.relics.slots, p.relics.free_slots()])
	_check(p.relics.granted == [&"fire_trail"], "granted lists it")
	var b = p.relics.behavior_of(&"fire_trail")
	_check(b != null and b.get_parent() == p.relics, "the Fire Trail behavior is a child of the relics node")
	_check(not p.relics.grant(RelicRegistry.find(&"fire_trail")) and p.relics.slots == 5, "granting an owned relic does nothing")
	p.free()

	p = await _player([])
	_check(p.relics.slots == 4 and p.relics.granted.is_empty() and p.relics.levels.is_empty(), "no legendary: 4 slots, nothing granted")
	p.free()
	p = await _player([ring, pendant])
	_check(p.relics.slots == 4 and p.relics.levels.is_empty(), "items without relic_id grant nothing")
	p.free()
	p = await _player([trail], true)
	_check(p.relics.levels.is_empty() and p.relics.slots == 4 and p.relics.granted.is_empty(), "hub player gets no relic")
	p.free()

	p = await _player([trail, orbs])
	_check(p.relics.slots == 6 and p.relics.granted.size() == 2 and p.relics.free_slots() == 4, "two legendaries: six slots, four free")
	_check(p.relics.slot_of(&"fire_trail") == 0 and p.relics.slot_of(&"storm_orbs") == 1, "in equipment order")
	p.free()

	# Raising and cards.
	p = await _player([trail])
	var fire = RelicRegistry.find(&"fire_trail")
	_check(p.relics.add_or_raise(fire) and p.relics.add_or_raise(fire) and p.relics.level_of(fire) == 3, "raised to 3 through add_or_raise")
	_check(not p.relics.add_or_raise(fire), "no raise past 3")
	p.free()
	p = await _player([trail])
	var raised := false
	for card in _LUR.roll(p, 50, _rng(1)):
		if card.is_relic and card.title == fire.display_name:
			_check(card.from_level == 1 and card.to_level == 2, "the roller offers the granted relic as an upgrade")
			card.apply.call()
			raised = true
	_check(raised and p.relics.level_of(fire) == 2, "a roller card raises it")
	for card in _LUR.roll(p, 50, _rng(2)):
		_check(not (card.is_relic and card.from_level == 0 and card.title == fire.display_name), "never a new-relic card for it")
	# Four more relics picked: five passives, no new-relic card.
	for id in [&"storm_orbs", &"thorn_nova", &"tidal_wave", &"frost_comet"]:
		p.relics.add_or_raise(RelicRegistry.find(id))
	_check(p.relics.levels.size() == 5 and p.relics.free_slots() == 0, "five passives with four picked")
	var any_new := false
	for card in _LUR.roll(p, 50, _rng(3)):
		if card.is_relic and card.from_level == 0:
			any_new = true
	_check(not any_new, "no new-relic card with all slots full")
	p.free()

	# First-level-up guarantee with a granted relic worn.
	p = await _player([trail])
	for s in 30:
		var cards = _LUR.roll(p, 3, _rng(s))
		var has_new := false
		for c in cards:
			if c.is_relic and c.from_level == 0:
				has_new = true
		_check(has_new, "seed %d: a new relic among the first three cards with a legendary worn" % s)
	p.free()

	# Carry-over.
	p = await _player([trail, orbs])
	var RP: GDScript = load("res://scripts/systems/run_progress.gd")
	var storm = RelicRegistry.find(&"storm_orbs")
	p.relics.add_or_raise(fire)
	p.relics.add_or_raise(fire)
	p.relics.add_or_raise(RelicRegistry.find(&"thorn_nova"))
	var snap: Dictionary = RP.capture(p)
	var p2 = await _player([trail, orbs])
	RP.restore(p2, snap)
	_check(p2.relics.level_of(fire) == 3, "restore: granted relic back at level 3")
	_check(p2.relics.level_of(storm) == 1, "restore: a granted relic at saved level 1 does not end above it (%d)" % p2.relics.level_of(storm))
	_check(p2.relics.levels.keys() == p.relics.levels.keys(), "restore: same order (%s)" % [p2.relics.levels.keys()])
	_check(p2.relics.slots == 6 and p2.relics.granted.size() == 2, "restore keeps the slot count")
	p.free()
	p2.free()

	# HUD: slot count and the gold outline.
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var rp = F.player()
	var hud = main.get_node("UI/Hud")
	rp.relics.grant(fire)
	rp.relics.add_or_raise(RelicRegistry.find(&"thorn_nova"))
	_check(rp.relics.slots == 5, "run player: five slots, the HUD loops relics.slots")
	_check(hud.relic_ring_color(0) == Color("ffd866"), "granted slot has the gold outline")
	_check(hud.relic_ring_color(1) == Color(RelicRegistry.find(&"thorn_nova").color, 0.9), "a picked relic keeps its colour ring")
	var view := Vector2(640, 360)
	_check(hud.relic_slot_rect(4, view).end.y < 360.0, "slot 4 fits on screen")
	main.queue_free()
	await process_frame
	paused = false

	_holder.free()
	Reg.test_items.clear()
	SG.override_path = null
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

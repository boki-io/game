extends SceneTree
## CampShop: the cost table, buying, undo, reset and the gold-plus-spent invariant; GameSession's thin API on top.
## Run: godot --headless --path . --script tests/camp/camp_shop.gd

const SEED_COUNT := 30
const COSTS := [40, 60, 90, 135, 203, 304, 456]

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var attrs := AttributeRegistry.all()
	_check(attrs.size() == 8, "eight attributes")
	var total := 0
	for a in attrs:
		var sum := 0
		for n in range(1, 8):
			_check(CampShop.cost(a, n) == COSTS[n - 1], "%s cost of level %d" % [a.id, n])
			sum += CampShop.cost(a, n)
		_check(sum == 1288, "%s total 1288" % a.id)
		total += sum
	_check(total == 10304, "all attributes cost 10304")

	var a: AttributeData = attrs[0]
	var s := CampShop.make_state(39, {})
	_check(not CampShop.can_buy(s, a) and not CampShop.buy(s, a), "cannot buy with 39 gold")
	_check(s.gold == 39 and CampShop.level_of(s, a) == 0, "failed buy changes nothing")
	s.gold = 40
	_check(CampShop.buy(s, a) and s.gold == 0 and CampShop.level_of(s, a) == 1, "buy level 1 for 40")
	s.gold = 100000
	for i in 6:
		_check(CampShop.buy(s, a), "buy level %d" % (i + 2))
	_check(CampShop.level_of(s, a) == 7 and CampShop.next_cost(s, a) == -1, "max level 7, no next cost")
	var before: int = s.gold
	_check(not CampShop.buy(s, a) and s.gold == before, "no buy at max")
	_check(CampShop.undo(s, a) and s.gold == before + 456 and CampShop.level_of(s, a) == 6, "undo refunds 456")
	var z := CampShop.make_state(0, {})
	_check(not CampShop.undo(z, a), "undo at level 0 fails")
	var refund := CampShop.reset_all(s)
	_check(refund == 40 + 60 + 90 + 135 + 203 + 304 and CampShop.spent(s) == 0, "reset refunds the total")
	_check(s.gold == 100040, "gold fully restored after reset (level 1 was paid before gold was set to 100000)")

	for seed_value in SEED_COUNT:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var start := rng.randi_range(0, 12000)
		var st := CampShop.make_state(start, {})
		for step in 300:
			var attr: AttributeData = attrs[rng.randi_range(0, attrs.size() - 1)]
			var roll := rng.randi_range(0, 9)
			if roll < 5:
				CampShop.buy(st, attr)
			elif roll < 9:
				CampShop.undo(st, attr)
			else:
				CampShop.reset_all(st)
			if st.gold + CampShop.spent(st) != start or st.gold < 0:
				_check(false, "seed %d step %d: invariant broken" % [seed_value, step])
				break
			for x in attrs:
				var lv := CampShop.level_of(st, x)
				if lv < 0 or lv > x.max_level:
					_check(false, "seed %d: level out of range" % seed_value)

	# GameSession API
	var gs: Node = get_root().get_node("GameSession")
	var changes := [0]
	gs.attributes_changed.connect(func() -> void: changes[0] += 1)
	gs.gold = 100
	gs.attribute_levels = {}
	_check(gs.level_of(&"might") == 0, "level_of starts at 0")
	_check(gs.buy_attribute(&"might") and gs.gold == 60 and gs.level_of(&"might") == 1, "session buy")
	_check(gs.buy_attribute(&"might") and gs.gold == 0 and gs.spent_total() == 100, "second buy, spent_total")
	_check(not gs.buy_attribute(&"might") and not gs.buy_attribute(&"nope"), "poor and unknown ids fail")
	_check(gs.undo_attribute(&"might") and gs.gold == 60 and gs.level_of(&"might") == 1, "session undo")
	_check(not gs.undo_attribute(&"fury"), "undo at 0 fails")
	gs.reset_attributes()
	_check(gs.gold == 100 and gs.spent_total() == 0 and gs.level_of(&"might") == 0, "session reset")
	_check(changes[0] == 4, "attributes_changed emitted per change (got %d)" % changes[0])
	gs.gold = 0
	gs.attribute_levels = {}
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

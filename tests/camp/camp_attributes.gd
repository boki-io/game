extends SceneTree
## The attribute data: totals at levels 0, 1 and 7 through CampAttributes.apply, display text against the data.
## (The in-play checks - Player, cooldowns, Recovery, Greed in the director - are added with build step 4.)
## Run: godot --headless --path . --script tests/camp/camp_attributes.gd

var _failed := false

# id -> [stats key, base, total at level 1, total at level 7]; max_hp and the rest use a base so adds show too.
const EXPECT := {
	&"toughness": [[&"max_hp", 100.0, 108.0, 156.0]],
	&"recovery": [[&"hp_regen", 0.0, 0.4, 2.8]],
	&"might": [[&"damage", 1.0, 1.03, 1.21]],
	&"fury": [[&"auto_speed", 1.0, 1.04, 1.28]],
	&"haste": [[&"cooldown", 1.0, 0.97, 0.79]],
	&"agility": [[&"move_speed", 90.0, 92.7, 108.9]],
	&"focus": [[&"max_mana", 100.0, 105.0, 135.0], [&"mana_regen", 8.0, 8.4, 10.8]],
	&"greed": [],
}


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _init() -> void:
	await process_frame
	var ids: Array[StringName] = []
	for a in AttributeRegistry.all():
		ids.append(a.id)
	_check(ids == [&"toughness", &"recovery", &"might", &"fury", &"haste", &"agility", &"focus", &"greed"],
		"registry order is the spec order")
	for a in AttributeRegistry.all():
		_check(a.max_level == 7 and a.base_cost == 40 and is_equal_approx(a.cost_growth, 1.5), "%s cost data" % a.id)
		_check(not a.display_name.is_empty() and not a.description.is_empty(), "%s has text" % a.id)
		for level in [0, 1, 7]:
			var stats := Stats.new()
			CampAttributes.apply(stats, {a.id: level})
			for row in EXPECT[a.id]:
				var want: float = row[1] if level == 0 else (row[2] if level == 1 else row[3])
				var got := stats.value(row[0], row[1])
				_check(_near(got, want), "%s %s at level %d: %s, want %s" % [a.id, row[0], level, got, want])
			# Nothing else is touched: every key of every other attribute stays at its base.
			for other in EXPECT:
				if other == a.id:
					continue
				for row in EXPECT[other]:
					_check(_near(stats.value(row[0], row[1]), row[1]), "%s level %d leaves %s alone" % [a.id, level, row[0]])
			var coin := CampAttributes.coin_bonus({a.id: level})
			var want_coin: float = 0.02 * level if a.id == &"greed" else 0.0
			_check(_near(coin, want_coin), "%s coin bonus at level %d: %s" % [a.id, level, coin])
			stats.free()
		_check_display(a)
	# Levels combine and unknown ids and out-of-range levels are harmless.
	var s := Stats.new()
	CampAttributes.apply(s, {&"toughness": 7, &"might": 7, &"bogus": 3, &"fury": 99})
	_check(_near(s.value(&"max_hp", 100.0), 156.0) and _near(s.value(&"damage", 1.0), 1.21), "levels combine")
	_check(_near(s.value(&"auto_speed", 1.0), 1.28), "level clamped to max")
	_check(_near(CampAttributes.coin_bonus({&"greed": 7}), 0.14), "greed 7 gives 14 points")
	_check(_near(CampAttributes.coin_bonus({}), 0.0), "no levels, no bonus")
	s.free()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## display_values must equal the per-level numbers in adds / scales / coin_chance (percent for scales and coins).
func _check_display(a: AttributeData) -> void:
	var want: Array[float] = []
	for key: StringName in a.adds:
		want.append(a.adds[key])
	for key: StringName in a.scales:
		want.append(absf(a.scales[key]) * 100.0)
	if a.coin_chance != 0.0:
		want.append(a.coin_chance * 100.0)
	_check(a.display_values.size() == want.size(), "%s display_values count" % a.id)
	for i in mini(want.size(), a.display_values.size()):
		_check(_near(a.display_values[i], want[i]), "%s display_values[%d] %s vs %s" % [a.id, i, a.display_values[i], want[i]])
	_check(a.summary.contains("{0}") and a.summary.contains("{%d}" % (a.display_values.size() - 1)), "%s summary placeholders" % a.id)
	_check(("-" if a.id == &"haste" else "+") in a.summary, "%s summary sign" % a.id)
	_check(not a.describe(0).contains("{") and not a.describe(7).contains("{"), "%s describe fills every placeholder" % a.id)
	match a.id:
		&"toughness": _check(a.describe(7) == "+56 max HP", "toughness text 7: " + a.describe(7))
		&"focus": _check(a.describe(7) == "+35 max mana, +2.8 mana/s", "focus text 7: " + a.describe(7))
		&"haste": _check(a.describe(1) == "-3% cooldowns", "haste text 1: " + a.describe(1))
		&"greed": _check(a.describe(7) == "+14% coin chance", "greed text 7: " + a.describe(7))

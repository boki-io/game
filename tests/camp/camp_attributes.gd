extends SceneTree
## The attribute data: totals at levels 0, 1 and 7 through CampAttributes.apply, display text against the data.
## Then the in-play effects: cooldowns, Recovery, Agility, Might, the hub Player and Greed in the director.
## Run: godot --headless --path . --script tests/camp/camp_attributes.gd

var _failed := false
var _F: GDScript

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
	await _check_play()
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


## A Knight run with `levels` in GameSession; the previous scene is freed first.
func _start(levels: Dictionary) -> Node:
	if current_scene:
		current_scene.free()
		current_scene = null
		await process_frame
	root.get_node("GameSession").attribute_levels = levels
	var main: Node = _F.start_run(self, &"knight")
	await physics_frame
	return main


func _check_play() -> void:
	_F = load("res://tests/fixture.gd")
	var gs: Node = root.get_node("GameSession")
	var levels := {&"haste": 7, &"fury": 7, &"toughness": 7, &"focus": 7, &"might": 7, &"agility": 7}

	# A Player with no levels is exactly as before.
	var main := await _start({})
	var p = _F.player()
	var base_hp = p.health.max_health
	_check(_near(p.stats.value(&"max_hp", p.max_hp), 100.0) and _near(base_hp, 100.0), "no levels: Knight 100 HP")
	_check(_near(p.caster.cooldown_of(p.caster.ability_q), p.caster.ability_q.cooldown), "no levels: Q cooldown unchanged")
	_check(_near(p.caster.cooldown_of(p.caster.ability_auto), 0.6), "no levels: auto cooldown unchanged")
	_check(_near(main.spawn_director.coin_bonus, 0.0), "no levels: no coin bonus")
	p.player_input.move_vector = Vector2.RIGHT
	await physics_frame
	_check(_near(p.velocity.length(), 90.0), "no levels: speed 90, got %s" % p.velocity.length())
	_check(_near(p.health.max_health, 100.0) and _near(p.mana.base_max, p.character.max_mana), "no levels: max mana base")

	# With levels: HP, mana, cooldowns, speed, damage.
	main = await _start(levels)
	p = _F.player()
	var c = p.caster
	_check(_near(p.health.max_health, 156.0) and _near(p.health.current, 156.0), "Toughness 7: 156 HP at full health")
	_check(_near(p.mana.max_mana(), p.character.max_mana + 35.0), "Focus 7: +35 mana")
	for slot in [&"q", &"e", &"r"]:
		var d = c.slot_data(slot)
		_check(_near(c.cooldown_of(d), d.cooldown * 0.79), "Haste 7 on %s: %s" % [slot, c.cooldown_of(d)])
	var auto = c.ability_auto
	_check(_near(c.cooldown_of(auto), 0.6 / 1.28), "Fury 7 divides the auto cooldown, ignores Haste: %s" % c.cooldown_of(auto))
	# Stacks with a per-ability upgrade (Spin Cyclone: spin.cooldown x0.8).
	_F.upgrade(p, "spin_cyclone")
	_check(_near(c.cooldown_of(c.ability_e), 2.0 * 0.8 * 0.79), "Haste stacks with spin_cyclone: %s" % c.cooldown_of(c.ability_e))
	_F.upgrade(p, "slash_speed")
	_check(_near(c.cooldown_of(auto), 0.6 * 0.85 / 1.28), "Fury stacks with slash_speed: %s" % c.cooldown_of(auto))
	# Might x Power multiply.
	_check(_near(c.damage_of(auto), 0.0 + c.value(auto, &"damage", auto.damage) * 1.21), "Might 7 on damage_of")
	_F.upgrade(p, "damage")
	_check(_near(p.stats.value(&"damage", 1.0), 1.21 * 1.1), "Might x Power multiply: %s" % p.stats.value(&"damage", 1.0))
	# Agility.
	p.player_input.move_vector = Vector2.RIGHT
	await physics_frame
	_check(_near(p.velocity.length(), 108.9), "Agility 7: speed 108.9, got %s" % p.velocity.length())
	p.player_input.move_vector = Vector2.ZERO

	# Recovery: heals over time, stops at max, nothing when dead.
	main = await _start({&"recovery": 7, &"greed": 7})
	_check(_near(main.spawn_director.coin_bonus, 0.14), "main sets the director's coin bonus from Greed 7")
	p = _F.player()
	p.health.take_damage(50.0)
	var hp = p.health.current
	await _F.seconds(self, 1.0)
	_check(absf((p.health.current - hp) - 2.8) < 0.15, "Recovery 7 heals about 2.8 in 1 s: %s" % (p.health.current - hp))
	p.health.take_damage(0.0)
	p.health.heal(1000.0)
	var emitted := [0]
	p.health.changed.connect(func(_a: float, _b: float) -> void: emitted[0] += 1)
	await _F.seconds(self, 0.2)
	_check(_near(p.health.current, p.health.max_health) and emitted[0] == 0, "Recovery stops at max and does not emit")
	p.health.take_damage(p.health.max_health)  # dies
	await physics_frame
	_check(p.dead and p.health.current == 0.0, "player died")
	await _F.seconds(self, 0.5)
	_check(p.health.current == 0.0, "Recovery does not revive")

	# RunProgress.restore re-reads the combined stats: attribute HP plus the upgrade, at full health.
	main = await _start({&"toughness": 7, &"focus": 7})
	p = _F.player()
	load("res://scripts/systems/run_progress.gd").restore(p, {level = 3, xp = 0, upgrades = {&"max_hp": 1}})
	_check(_near(p.health.max_health, 176.0) and _near(p.health.current, 176.0), "restore keeps the attribute HP and adds the upgrade: %s" % p.health.max_health)

	# Hub Player: the bonuses and still infinite mana, no damage-taking changes.
	gs.attribute_levels = {&"toughness": 7, &"might": 7}
	if current_scene:
		current_scene.free()
		current_scene = null
		await process_frame
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	for i in 90:
		await physics_frame
	hub._focus(0, true)
	for i in 20:
		await physics_frame
	var e := InputEventAction.new()
	e.action = &"hub_confirm"
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	e = InputEventAction.new()
	e.action = &"hub_confirm"
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame
	await physics_frame
	var hp_player = _F.player()
	_check(hp_player.hub_mode and hp_player.mana.infinite, "hub Player has infinite mana")
	_check(_near(hp_player.stats.value(&"damage", 1.0), 1.21), "hub Player has Might")
	_check(_near(hp_player.health.max_health, hp_player.character.max_hp + 56.0), "hub Player has Toughness")
	gs.attribute_levels = {}

	# Director coin chance: Greed adds to the stage's chance and clamps to 1.
	main = await _start({})
	var sd = main.spawn_director
	sd.stage.currency = 0.0
	for bonus in [0.0, 0.14, 5.0]:
		sd.coin_bonus = bonus
		var coins := 0
		seed(7)
		for i in 400:
			if randf() < clampf(sd.stage.coin_chance() + sd.coin_bonus, 0.0, 1.0):
				coins += 1
		var want := clampf(0.25 + bonus, 0.0, 1.0)
		_check(absf(coins / 400.0 - want) < 0.08, "coin rate with bonus %s: %s" % [bonus, coins / 400.0])
	# Through the real death path: bonus 5 always drops, bonus 0 with currency -100 never does.
	sd.stage.currency = -100.0
	sd.coin_bonus = 5.0
	var before := _count_coins(main)
	for i in 10:
		var en = _F.spawn_enemy(main, "grunt", Vector2(100 + i, 100), 1.0, true)
		sd._on_enemy_died(en)
	_check(_count_coins(main) - before == 10, "bonus above 1 clamps to a certain drop: %d" % (_count_coins(main) - before))
	sd.coin_bonus = 0.0
	before = _count_coins(main)
	for i in 10:
		var en = _F.spawn_enemy(main, "grunt", Vector2(100 + i, 100), 1.0, true)
		sd._on_enemy_died(en)
	_check(_count_coins(main) == before, "currency -100 and no bonus: no coins")


func _count_coins(main: Node) -> int:
	var n := 0
	for ch in main.get_node("Pickups").get_children():
		if ch.get_script() != null and ch.get_script().get_global_name() == &"Coin" and ch.visible:
			n += 1
	return n

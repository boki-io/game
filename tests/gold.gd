extends SceneTree
## Gold: coin drop chance (25% + the stage's gold, clamped), drops, collection through the XPCollector, persistence.
## Run: godot --headless --path . --script tests/gold.gd

const StageDataScript := preload("res://scripts/stages/stage_data.gd")
var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _coins(main: Node) -> int:
	var n := 0
	for c in main.get_node("Pickups").get_children():
		if c.get_script() == load("res://scripts/systems/coin.gd") and c.visible:
			n += 1
	return n


func _kill_some(main: Node, count: int) -> void:
	for i in count:
		var e = load("res://tests/fixture.gd").spawn_enemy(main, "grunt", Vector2(100, 100), 1.0, true)
		main.spawn_director.alive += 1
		main.spawn_director._on_enemy_died(e)


func _init() -> void:
	await process_frame
	var s = StageDataScript.new()
	var cases := {-100: 0.0, -30: 0.0, -25: 0.0, -5: 0.20, 0: 0.25, 10: 0.35, 20: 0.45, 75: 1.0, 100: 1.0, 500: 1.0}
	for gold in cases:
		s.currency = gold
		_check(is_equal_approx(s.coin_chance(), cases[gold]), "gold %d -> chance %.2f (got %.2f)" % [gold, cases[gold], s.coin_chance()])
	# Every rolled value from the tier ranges stays inside 0..100%.
	for gold in range(-5, 25, 5):
		s.currency = gold
		_check(s.coin_chance() >= 0.0 and s.coin_chance() <= 1.0, "chance in range for %d" % gold)

	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var gold_before: int = root.get_node("GameSession").gold

	var always = StageDataScript.new()
	always.currency = 100
	main.spawn_director.apply_stage(always)
	_kill_some(main, 20)
	_check(_coins(main) == 20, "100%% chance: every kill drops a coin (%d)" % _coins(main))
	var never = StageDataScript.new()
	never.currency = -100
	main.spawn_director.apply_stage(never)
	_kill_some(main, 20)
	_check(_coins(main) == 20, "0%% chance: no new coins (%d)" % _coins(main))

	# A mob with no XP drop drops no coin even at 100%.
	main.spawn_director.apply_stage(always)
	var no_xp = load("res://data/enemies/grunt.tres").duplicate()
	no_xp.xp_drop = 0
	main.spawn_director._pools[no_xp] = []
	main.spawn_director.alive_by_type[no_xp.id] += 1
	var dummy = F.spawn_enemy(main, "grunt", Vector2(100, 100), 1.0, true)
	dummy.data = no_xp
	main.spawn_director._on_enemy_died(dummy)
	_check(_coins(main) == 20, "a mob with xp_drop 0 drops no coin")

	# The player's collector pulls coins in and they add to GameSession.gold.
	var p = F.player()
	for c in main.get_node("Pickups").get_children():
		if c.visible and c.get_script() == load("res://scripts/systems/coin.gd"):
			c.global_position = p.global_position + Vector2(20, 0)
	await F.seconds(self, 1.5)
	_check(root.get_node("GameSession").gold - gold_before == 20, "20 coins collected add 20 gold (got %d)" % (root.get_node("GameSession").gold - gold_before))
	_check(_coins(main) == 0, "collected coins are released to the pool")
	# Reuse: the pool hands the same Coin out again.
	var count_nodes: int = main.get_node("Pickups").get_child_count()
	main.get_node("Pickups").spawn_coin(Vector2(200, 200))
	_check(main.get_node("Pickups").get_child_count() == count_nodes, "pooled coin is reused")

	main.queue_free()
	await process_frame
	_check(root.get_node("GameSession").gold >= 20, "gold survives the run ending")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

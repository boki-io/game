extends SceneTree
## The run purse and banking: coins go to run_gold, and the death screen, abandon and victory each bank it once and
## set last_reward; take_reward returns it once; nothing is banked on complete_stage; the HUD and summary use run_gold.
## Run: godot --headless --path . --script tests/camp/camp_gold.gd

const SG := preload("res://scripts/systems/save_game.gd")

var _failed := false
var _gs: Node
var _loaded: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _on_scene(scene_path: String) -> void:
	_loaded.append(scene_path)


func _init() -> void:
	await process_frame
	SG.override_path = ""  # never write a real save
	_gs = root.get_node("GameSession")
	_gs.scene_hook = _on_scene
	var F: GDScript = load("res://tests/fixture.gd")
	var knight: CharacterData = CharacterRegistry.all()[0]
	_gs.gold = 100
	_gs.last_reward = 0

	# new_run empties the purse; a coin raises run_gold and not gold.
	_gs.run_gold = 9
	_gs.new_run(knight, 5)
	_check(_gs.run_gold == 0, "new_run: purse is 0")
	_check(not "run_start_gold" in _gs, "run_start_gold is gone")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var coin: Node = main.get_node("Pickups").spawn_coin(F.player().global_position)
	await F.frames(self, 4)
	_check(_gs.run_gold == 1 and _gs.gold == 100, "a coin raises run_gold, not gold (run %d, gold %d)" % [_gs.run_gold, _gs.gold])

	# The HUD draws run_gold (text source), and the victory summary uses it.
	_gs.run_gold = 12
	_gs.new_run(knight, 5)
	_gs.run_gold = 12
	_gs.complete_stage()
	_check(_gs.run_gold == 12 and _gs.gold == 100 and _gs.last_reward == 0, "nothing is banked on complete_stage")
	_gs.current_column = 2
	_loaded.clear()
	_gs.finish_run()
	_check(_gs.run_summary.gold_earned == 12, "summary gold_earned is the purse")
	_check(_gs.gold == 112 and _gs.run_gold == 0 and _gs.last_reward == 12, "finish_run banks once, after the summary")
	_check(_loaded.is_empty(), "finish_run does not change scene")
	_gs.go_to_hub()
	_check(_gs.gold == 112 and _gs.last_reward == 12 and _loaded == [_gs.HUB], "go_to_hub after banking banks nothing more")
	_check(_gs.take_reward() == 12 and _gs.take_reward() == 0, "take_reward returns the reward once")

	# Abandon banks and goes to the hub.
	_gs.new_run(knight, 6)
	_gs.run_gold = 7
	_loaded.clear()
	_gs.abandon_run()
	_check(_gs.gold == 119 and _gs.run_gold == 0 and _gs.last_reward == 7 and _loaded == [_gs.HUB], "abandon banks the purse and goes to the hub")
	_gs.take_reward()

	# last_reward accumulates over several bankings.
	_gs.run_gold = 3
	_gs.bank_run()
	_gs.run_gold = 4
	_check(_gs.bank_run() == 4 and _gs.last_reward == 7, "last_reward accumulates")
	_check(_gs.bank_run() == 0 and _gs.gold == 126, "an empty purse banks nothing")
	_gs.take_reward()

	# The death screen banks when it appears, shows the reward, and the later fail_run banks nothing more.
	main.run_manager.kills = 3
	_gs.new_run(knight, 8)
	_gs.run_gold = 15
	var end: Control = main.get_node("UI/EndScreen")
	end.run_manager = main.run_manager
	end.show_result(0)
	_check(_gs.gold == 141 and _gs.run_gold == 0 and _gs.last_reward == 15, "death screen banks the purse")
	_check(end._stats.text.contains("Gold earned  15"), "death screen shows 'Gold earned 15': " + end._stats.text)
	end._return_to_hub()
	_check(_gs.gold == 141 and _gs.last_reward == 15, "the button banks nothing more")
	_check(_gs.take_reward() == 15, "take_reward after death")

	# The victory screen shows the summary's number.
	_gs.new_run(knight, 9)
	_gs.run_gold = 21
	_gs.current_column = 2
	_gs.finish_run()
	end.show_result(1)
	_check(end._stats.text.contains("Gold earned  21"), "victory screen shows 'Gold earned 21'")
	_gs.take_reward()

	main.queue_free()
	paused = false
	await process_frame
	_gs.scene_hook = Callable()
	_gs.gold = 0
	_gs.run_gold = 0
	_gs.last_reward = 0
	SG.override_path = null
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

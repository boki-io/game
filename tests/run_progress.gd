extends SceneTree
## GameSession's path state and the progress a run carries between stages (spec 6, 7, 9.4).
## Run: godot --headless --path . --script tests/run_progress.gd

var _failed := false
var _loaded: Array[String] = []
var _gs: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _on_scene(path: String) -> void:
	_loaded.append(path)


## A run scene for the current GameSession stage (column + row), with the spawner off.
func _stage(F: GDScript, column_row: int) -> Node:
	_gs.current_row = column_row
	_gs.current_stage = _gs.path.stage_at(_gs.current_column, column_row)
	return F.start_run(self, _gs.character.id)


func _init() -> void:
	await process_frame
	_gs = root.get_node("GameSession")
	_gs.scene_hook = _on_scene
	var F: GDScript = load("res://tests/fixture.gd")
	var knight: CharacterData = CharacterRegistry.all()[0]
	var gold_start: int = _gs.gold

	# Starting a run: a path, column 0, all 3 stages available.
	_gs.new_run(knight, 7)
	_check(_gs.path != null and _gs.path_seed == 7 and _gs.current_column == 0, "new run: path, seed, column 0")
	_check(_gs.available_rows() == [0, 1, 2], "column 1: all 3 stages available")
	_check(_gs.run_progress == null and _gs.run_kills == 0, "new run: no progress, no kills")
	_check(not _gs.is_last_stage(), "column 1 is not the last stage")
	_check(_gs.last_character == knight, "last_character is set")

	# Play column 1 (middle), gain levels and upgrades, win.
	var main: Node = _stage(F, 1)
	await F.frames(self, 2)
	var p = F.player()
	var base_hp: float = p.health.max_health
	p.xp.add(40)  # several levels (the level-up menu is queued but main.gd connects its own queue)
	var level: int = p.xp.level
	var xp: int = p.xp.xp
	_check(level > 1, "the test Player gained levels (%d)" % level)
	F.upgrade(p, "max_hp")
	F.upgrade(p, "max_hp")
	F.upgrade(p, "damage")
	p.relics.add_or_raise(load("res://data/relics/storm_orbs.tres"))
	p.relics.add_or_raise(load("res://data/relics/tidal_wave.tres"))
	p.relics.add_or_raise(load("res://data/relics/tidal_wave.tres"))
	var hp_max: float = p.health.max_health
	_check(hp_max > base_hp, "max_hp upgrade raised the maximum")
	main.run_manager.kills = 42
	p.health.take_damage(30.0)
	_loaded.clear()
	_gs.complete_stage()
	_check(_loaded == [_gs.SELECT], "winning column 1 loads the select screen")
	_check(_gs.beaten == [1] and _gs.current_column == 1 and _gs.current_stage == null, "column advanced, stage recorded")
	_check(_gs.run_kills == 42, "the stage's kills are added to run_kills")
	_check(_gs.run_progress != null and _gs.run_progress.level == level and _gs.run_progress.xp == xp, "progress saved")
	_check(_gs.run_progress.upgrades.get(&"max_hp", 0) == 2, "upgrade levels saved")
	_check(_gs.run_progress.relics == {&"storm_orbs": 1, &"tidal_wave": 2}, "relic levels saved")
	main.free()
	paused = false  # the real scene change unpauses; the stand-in hook does not
	await process_frame

	# Column 2: only the stages connected to the beaten middle stage.
	var rows: Array = _gs.available_rows()
	_check(rows.size() == 2 and rows.has(1), "column 2: two options, including the middle")
	var stages: Array = _gs.available_stages()
	_check(stages.size() == 2 and stages[0] == _gs.path.stage_at(1, rows[0]), "available_stages matches the rows")

	# Next Player: level, XP and upgrades restored, HP full at the upgraded maximum, no level-up menu.
	main = _stage(F, rows[0])
	await F.frames(self, 2)
	p = F.player()
	_check(p.xp.level == level and p.xp.xp == xp, "level %d and XP %d carried over (got %d / %d)" % [level, xp, p.xp.level, p.xp.xp])
	_check(p.upgrades.levels.get(&"max_hp", 0) == 2 and p.upgrades.levels.get(&"damage", 0) == 1, "upgrade levels carried")
	_check(p.relics.levels == {&"storm_orbs": 1, &"tidal_wave": 2} and p.relics.levels.keys() == [&"storm_orbs", &"tidal_wave"], "relics carried, in slot order")
	_check(is_equal_approx(p.health.max_health, hp_max), "HP maximum includes the carried upgrades (%f vs %f)" % [p.health.max_health, hp_max])
	_check(is_equal_approx(p.health.current, p.health.max_health), "HP starts full")
	_check(is_equal_approx(p.mana.current, p.mana.max_mana()), "mana starts full")
	_check(not main.get_node("UI/LevelUpMenu").active, "no level-up menu opens on restore")
	_check(not paused, "the game is not paused after restore")
	_check(main.run_manager.kills == 0 and main.run_manager.elapsed == 0.0, "a fresh stage clock and kill count")

	# Win column 2, then the final stage.
	main.run_manager.kills = 10
	_gs.complete_stage()
	main.free()
	paused = false  # the real scene change unpauses; the stand-in hook does not
	await process_frame
	_check(_gs.current_column == 2 and _gs.is_last_stage(), "column 3 is the last stage")
	_check(_gs.available_rows() == [0], "column 3: only the final stage")
	_check(_gs.run_kills == 52, "kills accumulate over stages (%d)" % _gs.run_kills)
	main = _stage(F, 0)
	await F.frames(self, 2)
	main.run_manager.kills = 5
	_gs.run_gold += 7
	_loaded.clear()
	_gs.finish_run()
	_check(_gs.run_summary.stages_cleared == 3, "summary: 3 stages cleared")
	_check(_gs.run_summary.kills == 57, "summary: total kills 57 (got %d)" % _gs.run_summary.kills)
	_check(_gs.run_summary.gold_earned == 7, "summary: gold earned this run")
	_check(_gs.gold == gold_start + 7 and _gs.run_gold == 0, "finish_run banks the purse after the summary")
	_check(_gs.run_summary.level == level, "summary: final level")
	_check(_gs.path == null and _gs.run_progress == null and _gs.current_stage == null, "finish_run clears the run")
	_check(_loaded.is_empty(), "finish_run does not change scene itself")
	main.free()
	paused = false  # the real scene change unpauses; the stand-in hook does not
	await process_frame

	# Death and abandon clear the run and go to the hub; the purse is banked.
	for ending in ["fail_run", "abandon_run"]:
		_gs.new_run(knight, 11)
		_gs.run_progress = {level = 3, xp = 1, upgrades = {}}
		_gs.beaten.append(0)
		_gs.current_column = 1
		_loaded.clear()
		_gs.run_gold = 3
		_gs.call(ending)
		_check(_gs.run_gold == 0, ending + " empties the purse")
		_check(_loaded == [_gs.HUB], ending + " goes to the hub")
		_check(_gs.path == null and _gs.current_stage == null and _gs.run_progress == null, ending + " clears the run")
		_check(_gs.current_column == 0 and _gs.beaten.is_empty(), ending + " resets the column")
	_check(_gs.gold == gold_start + 7 + 3 * 2, "banked gold survives the end of a run (got %d)" % (_gs.gold - gold_start))

	# A new run starts again at column 1 with a new path and no progress, and the purse is empty.
	_gs.new_run(knight, 99)
	_check(_gs.current_column == 0 and _gs.run_progress == null and _gs.run_gold == 0, "new run starts clean")
	_check(_gs.has_method("restart_run") == false, "restart_run is gone")

	_gs.scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

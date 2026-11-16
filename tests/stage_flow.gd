extends SceneTree
## Run flow in the arena: a win shows "Stage cleared" for 2 s and loads the select screen, a pending level-up delays
## it, the last stage shows victory, death shows the death screen, and the pause menu asks before abandoning.
## Run: godot --headless --path . --script tests/stage_flow.gd

var _failed := false
var _loaded: Array[String] = []
var _gs: Node
var _fader: Node
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	await process_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame


## A run scene for column `column` of seed 3's path with the clock about to hit 300 s.
func _stage(column: int) -> Node:
	_gs.new_run(CharacterRegistry.all()[0], 3)
	_gs.current_column = column
	for i in column:
		_gs.beaten.append(1)
	_gs.current_row = 0
	_gs.current_stage = _gs.path.stage_at(column, 0)
	var main: Node = _F.start_run(self, _gs.character.id)
	main.run_manager.running = true
	main.spawn_director.set_physics_process(false)
	main.run_manager.elapsed = 299.9
	return main


func _buttons(node: Node) -> Array:
	return node.find_children("*", "Button", true, false).map(func(b) -> String: return b.text)


func _init() -> void:
	await process_frame
	await process_frame
	_gs = root.get_node("GameSession")
	_fader = root.get_node("SceneFader")
	_F = load("res://tests/fixture.gd")
	_gs.scene_hook = func(p: String) -> void: _loaded.append(p)
	for i in 200:
		if not _fader.busy:
			break
		await physics_frame

	# Win in column 1: the banner shows (the game paused), 2 s later the select screen loads.
	var main := _stage(0)
	var banner: Control = main.get_node("UI/StageBanner")
	await _F.seconds(self, 0.3)
	_check(banner.visible and paused, "banner shown and the game paused after the win")
	_check(_loaded.is_empty(), "the select screen does not load at once")
	await _press(&"pause")
	_check(not main.get_node("UI/PauseMenu").visible, "the pause menu cannot open during the banner")
	var t0 := Time.get_ticks_msec()
	while _loaded.is_empty() and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	var waited := (Time.get_ticks_msec() - t0) / 1000.0
	_check(_loaded == [_gs.SELECT], "the select screen loads")
	_check(waited > 1.3 and waited < 2.6, "after about 2 s (%.2f s left)" % waited)
	_check(_gs.current_column == 1 and _gs.beaten == [0], "the win was recorded")
	_check(_buttons(main.get_node("UI/EndScreen")).size() == 1, "no end screen buttons other than Return to Hub")
	main.free()
	paused = false
	_loaded.clear()

	# A level-up pending at the 300 s mark delays the banner until the menu is closed.
	main = _stage(0)
	banner = main.get_node("UI/StageBanner")
	var menu = main.get_node("UI/LevelUpMenu")
	_F.player().xp.add(8)  # opens the level-up menu
	await _F.seconds(self, 0.3)
	_check(menu.active, "the level-up menu is open")
	_check(not banner.visible, "the banner waits behind the level-up menu")
	menu._pick(0)
	await _F.seconds(self, 0.2)
	await process_frame
	_check(not menu.active and banner.visible, "the banner appears once the menu closes")
	_check(_F.player().xp.level == 2, "no level was lost")
	main.free()
	paused = false
	await process_frame
	_loaded.clear()

	# Win in column 3: victory with the run summary, no banner, Return to Hub only.
	main = _stage(2)
	main.run_manager.kills = 12
	await _F.seconds(self, 0.3)
	var end: Control = main.get_node("UI/EndScreen")
	_check(end.visible and not main.get_node("UI/StageBanner").visible, "victory screen, no banner")
	_check(_buttons(end) == ["Return to Hub"], "victory has Return to Hub only")
	var text := ""
	for l in end.find_children("*", "Label", true, false):
		text += l.text + "\n"
	_check(text.contains("Victory") and text.contains("3 of 3") and text.contains("Total kills  12"), "victory shows the summary: " + text)
	_check(_gs.path == null, "finish_run cleared the path")
	for b in end.find_children("*", "Button", true, false):
		b.pressed.emit()
	_check(_loaded == [_gs.HUB], "Return to Hub on victory loads the hub")
	main.free()
	paused = false
	_loaded.clear()
	await process_frame

	# Death: the death screen shows the stage reached; Return to Hub is the only button and discards the path.
	main = _stage(1)
	main.run_manager.running = true
	main.run_manager.elapsed = 10.0
	main.run_manager.kills = 4
	_F.player().health.take_damage(1000.0)
	await _F.seconds(self, 1.6)
	end = main.get_node("UI/EndScreen")
	_check(end.visible, "death screen shown after the delay")
	text = ""
	for l in end.find_children("*", "Label", true, false):
		text += l.text + "\n"
	_check(text.contains("You died") and text.contains("Stage reached  2") and text.contains("Kills in this stage  4"), "death screen shows stage and kills: " + text)
	_check(_buttons(end) == ["Return to Hub"], "no Restart button on death")
	for b in end.find_children("*", "Button", true, false):
		b.pressed.emit()
	_check(_loaded == [_gs.HUB] and _gs.path == null, "death: hub, path discarded")
	main.free()
	paused = false
	_loaded.clear()
	await process_frame

	# The pause menu's Return to Hub asks first.
	main = _stage(1)
	main.run_manager.elapsed = 5.0
	await _F.frames(self, 2)
	var pause = main.get_node("UI/PauseMenu")
	await _press(&"pause")
	_check(pause.visible and _buttons(pause).has("Return to Hub") and not _buttons(pause).has("Restart"), "pause menu: Return to Hub, no Restart")
	var ret: Button
	for b in pause.find_children("*", "Button", true, false):
		if b.text == "Return to Hub":
			ret = b
	var prompt = pause.get_node_or_null("AbandonPrompt")
	_check(prompt != null and not prompt.visible, "the prompt starts closed")
	ret.pressed.emit()
	_check(prompt.visible and _loaded.is_empty() and _gs.path != null, "Return to Hub opens the prompt, nothing happens yet")
	await _press(&"pause")
	_check(not prompt.visible and pause.visible, "Esc closes the prompt, the pause menu stays")
	ret.pressed.emit()
	for b in prompt.find_children("*", "Button", true, false):
		if b.text == "Yes":
			b.pressed.emit()
	_check(_loaded == [_gs.HUB] and _gs.path == null, "Yes abandons: hub, path discarded")
	main.free()
	paused = false

	# Run directly from the editor (no path): a win ends in victory and never tries to load a select screen.
	_loaded.clear()
	_gs.path = null
	_gs.current_stage = null
	_gs.run_progress = null
	main = _F.start_run(self, &"knight")
	main.run_manager.running = true
	main.run_manager.elapsed = 299.9
	await _F.seconds(self, 0.3)
	_check(main.get_node("UI/EndScreen").visible and _loaded.is_empty(), "standalone arena: victory, no select screen")
	main.free()
	paused = false

	_gs.scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

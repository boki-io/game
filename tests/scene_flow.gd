extends SceneTree
## Scene changes: hub -> run -> hub -> run, the Arena size in each, the game unpaused after every change,
## input blocked while fading, and the hub pause menu opening on the first Esc.
## Run: godot --headless --path . --script tests/scene_flow.gd

var _failed := false
var _session: Node
var _fader: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _wait_idle() -> void:
	for i in 300:
		await physics_frame
		if not _fader.busy and current_scene != null:
			return
	_check(false, "fade finished")


func _scene_name() -> String:
	return current_scene.name if current_scene else ""


func _init() -> void:
	await process_frame
	await process_frame
	_session = root.get_node("GameSession")
	_fader = root.get_node("SceneFader")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _wait_idle()
	_check(root.get_node("SceneFader").busy == false, "boot fade-in ends")

	# Esc in the hub opens the pause menu (Continue, Exit) without crashing, and Esc closes it.
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	await process_frame
	_check(hub.get_node("UI/PauseMenu").visible, "Esc opens the hub pause menu")
	_check(paused, "hub pause menu pauses the tree")
	_check(not _has_button(hub.get_node("UI/PauseMenu"), "Return to Hub"), "hub pause menu has no Return to Hub")
	esc.pressed = false
	Input.parse_input_event(esc)
	esc = InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	await process_frame
	_check(not hub.get_node("UI/PauseMenu").visible and not paused, "Esc again resumes")

	var knight: CharacterData = CharacterRegistry.all()[0]
	_session.start_run(knight)
	_check(_fader.busy, "fade starts at once")
	paused = true  # a fade that starts while paused must still unpause at the scene change
	await _wait_idle()
	_check(_scene_name() == "Main", "run scene loaded")
	_check(Arena.world_size == Vector2i(1600, 896), "run uses the default arena size")
	_check(not paused, "unpaused in the run")
	_check(root.get_node("PlayerRegistry").players.size() == 1, "one Player in the run")
	_check(_has_button(current_scene.get_node("UI/PauseMenu"), "Return to Hub"), "run pause menu has Return to Hub")

	_session.go_to_hub()
	await _wait_idle()
	_check(_scene_name() == "Hub", "hub scene loaded")
	_check(Arena.world_size == Vector2i(960, 560), "hub arena size is not stale")
	var players = root.get_node("PlayerRegistry").players
	_check(players.size() == 1 and players[0].character == knight, "back in the hub as the Knight")
	_check(current_scene.mode == current_scene.Mode.WALK, "return lands in walk mode")
	_check(players[0].global_position.y > 60.0 and players[0].global_position.y < 100.0, "below the door")
	for i in 90:
		await physics_frame
	_check(_scene_name() == "Hub", "the return does not re-enter the run")

	_session.restart_run()
	await _wait_idle()
	_check(_scene_name() == "Main" and Arena.world_size == Vector2i(1600, 896), "restart loads a run at full size")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _has_button(node: Node, text: String) -> bool:
	for child in node.find_children("*", "Button", true, false):
		if (child as Button).text == text:
			return true
	return false

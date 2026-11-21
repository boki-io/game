extends SceneTree
## The blue stage door in the hub: dark in browse mode, lit in walk mode, set apart from the gold door and the chest, and walking
## into it starts the original three-stage run (a new path, then the select screen) without touching the overworld; coming back
## from it puts the hero below that door.
## Run: godot --headless --path . --script tests/hub_stage_door.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _init() -> void:
	await process_frame
	await process_frame
	var gs := root.get_node("GameSession")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _wait(60)
	var chars := CharacterRegistry.all()
	var sd = hub.stage_door
	_check(not sd.is_open, "the stage door is dark while browsing")
	_check(sd.position.x > hub.door.position.x + 100.0 and sd.position.x > hub.CHEST_POS.x + 60.0, "the stage door is to the right of the door and the chest")
	_check(sd.lit_color.b > sd.lit_color.r and sd.lit_color.b > 0.9 and hub.door.lit_color.b < 0.6, "the stage door is blue, the other one gold")

	hub._focus(0, true)
	await _wait(20)
	var e := InputEventAction.new()
	e.action = &"hub_confirm"
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(2)
	e = InputEventAction.new()
	e.action = &"hub_confirm"
	e.pressed = false
	Input.parse_input_event(e)
	await _wait(5)
	_check(hub.mode == hub.Mode.WALK and sd.is_open and hub.door.is_open, "both doors are lit in walk mode")

	var visited := []
	gs.scene_hook = func(path: String) -> void: visited.append(path)
	var p = root.get_node("PlayerRegistry").players[0]
	await _wait(60)
	p.global_position = Vector2(sd.position.x, 80)
	await _wait(3)
	p.global_position = Vector2(sd.position.x, 30)
	await _wait(10)
	_check(visited == [gs.SELECT], "walking into the blue door opens the select screen (%s)" % [visited])
	_check(gs.path != null and gs.last_character == chars[0] and gs.last_door == &"stages", "with a new path, the character and the door remembered")
	_check(gs.journey == null or gs.dungeon == null, "no dungeon run")

	gs.scene_hook = Callable()
	hub.queue_free()
	await process_frame
	paused = false

	# Back in the hub the hero stands below the blue door.
	var hub2: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub2)
	current_scene = hub2
	await _wait(10)
	var q = root.get_node("PlayerRegistry").players[0]
	_check(hub2.mode == hub2.Mode.WALK and absf(q.global_position.x - hub2.stage_door.position.x) < 2.0, "coming back from the stages puts the hero below the blue door")
	gs.last_door = &"overworld"
	gs.last_character = null
	hub2.queue_free()
	await process_frame

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

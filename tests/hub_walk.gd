extends SceneTree
## Hub walk mode: choosing spawns exactly one Player with infinite mana, the door lights up, interact near a
## pedestal goes back to browsing and wipes pending meteors and bolts, the same key press cannot choose and
## interact, and walking into the door starts a run.
## Run: godot --headless --path . --script tests/hub_walk.gd

var _failed := false
var _session: Node
var _fader: Node
var _players: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _action(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _init() -> void:
	await process_frame
	await process_frame
	_session = root.get_node("GameSession")
	_fader = root.get_node("SceneFader")
	_players = root.get_node("PlayerRegistry")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _wait(90)
	var chars := CharacterRegistry.all()

	# Choose the Wizard with the real input action.
	hub._focus(1, true)
	await _wait(20)
	await _action(&"hub_confirm")
	_check(hub.mode == hub.Mode.WALK, "walk mode after confirm")
	_check(_players.players.size() == 1, "exactly one Player")
	var p = _players.players[0]
	_check(p.character == chars[1] and p.hub_mode, "a hub-mode Wizard")
	_check(hub.door.is_open, "the door is lit")
	_check(not hub.panel.visible, "the info panel closed")
	_check(not hub.pedestals[1].get_child(0).visible, "the Wizard's pedestal figure is hidden")
	_check(hub.pedestals[0].get_child(0).visible, "the other figure is shown")
	_check(not p.hurtbox.invulnerable, "no invulnerability is used in the hub")

	# Infinite mana, normal cooldowns.
	var mana = p.mana.current
	p.player_input.aim_vector = Vector2.RIGHT
	p.player_input.ability_pressed.emit(&"r")  # a meteor, pending for 0.7s
	await physics_frame
	_check(p.mana.current >= mana, "casting does not reduce mana")
	_check(p.caster.cooldowns[&"r"] > 0.0, "cooldowns still run")
	_check(not hub.get_node("World/Zones")._zones.is_empty(), "the meteor is pending")

	# interact is ignored away from the pedestals ...
	await _wait(20)  # past the mode lockout
	p.global_position = Vector2(480, 150)
	await _wait(2)
	await _action(&"interact")
	_check(hub.mode == hub.Mode.WALK, "interact does nothing away from a pedestal")
	_check(not hub.prompt.visible, "no prompt away from a pedestal")

	# ... and works next to one, whichever pedestal it is, returning to the character being played.
	p.global_position = hub.pedestals[0].position + Vector2(0, 20)
	await _wait(3)
	_check(hub.prompt.visible, "the prompt shows near a pedestal")
	await _action(&"interact")
	_check(hub.mode == hub.Mode.BROWSE, "interact returns to browse mode")
	_check(hub.focus_index == 1, "the character being played is focused")
	_check(_players.players.is_empty(), "the Player is gone at once")
	_check(hub.pedestals[1].get_child(0).visible, "the figure is back")
	_check(not hub.door.is_open, "the door is dark again")
	_check(hub.panel.visible, "the panel is back")
	_check(hub.get_node("World/Zones")._zones.is_empty(), "the pending meteor was cleared")

	# interact right after a confirm is ignored (one F press cannot do both).
	await _wait(20)
	hub._focus(0, true)
	await _action(&"hub_confirm")
	_check(hub.mode == hub.Mode.WALK and _players.players.size() == 1, "chose the Knight, still exactly one Player")
	p = _players.players[0]
	_check(p.character == chars[0], "the Knight")
	p.global_position = hub.pedestals[0].position + Vector2(0, 20)
	hub._lockout = 0.2
	await _action(&"interact")
	_check(hub.mode == hub.Mode.WALK, "interact inside the lockout is ignored")

	# The door starts a run.
	await _wait(20)
	p.global_position = Vector2(480, 80)
	await _wait(3)
	p.global_position = Vector2(480, 30)
	await _wait(5)
	_check(_fader.busy, "walking into the door starts the fade")
	await _wait(120)
	_check(current_scene.name == "Select" and _session.last_character == chars[0], "the door opens the select screen")
	_check(_session.path != null and _session.current_column == 0, "a new path starts at column 1")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## Hub browse mode: pedestals, focus with the input actions, the info panel's numbers against the data
## files, a mouse click on a pedestal, and Choose starting a run exactly once.
## Run: godot --headless --path . --script tests/hub_browse.gd

var _failed := false

# In a --script SceneTree the autoloads are added after _init, so a script that names one cannot compile
# until the first frame. This test therefore reaches autoloads through the root and loads project scripts
# (the info panel, which uses UiKit and Audio) at runtime instead of naming their classes.
var _session: Node
var _fader: Node
var _players: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _key(action: StringName, pressed: bool = true) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func _init() -> void:
	await process_frame
	await process_frame
	_session = root.get_node("GameSession")
	_fader = root.get_node("SceneFader")
	_players = root.get_node("PlayerRegistry")
	var panel_script: GDScript = load("res://scripts/ui/hub_info_panel.gd")
	_session.last_character = null
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	for i in 90:  # let the first-boot fade finish
		await physics_frame
	_check(not _fader.busy, "fade finished")
	var chars := CharacterRegistry.all()
	_check(hub.pedestals.size() == chars.size(), "one pedestal per character")
	_check(Arena.world_size == Vector2i(960, 560), "hub world size is 960x560")
	_check(hub.pedestals[0].position == Vector2(410, 380) and hub.pedestals[1].position == Vector2(550, 380),
		"pedestals at x=410 and x=550 on y=380")
	_check(hub.mode == hub.Mode.BROWSE and _players.players.is_empty(), "browse mode has no Player")
	_check(not hub.door.is_open, "door starts closed")

	var panel: Control = hub.panel
	for i in chars.size():
		hub._focus(i, true)
		await process_frame
		var c: CharacterData = chars[i]
		_check(panel.name_label.text == c.display_name, "%s name shown" % c.display_name)
		_check(panel.stats_label.text == panel_script.stats_text(c), "%s stats line" % c.display_name)
		_check("%s" % panel_script.num(c.max_hp) in panel.stats_label.text, "%s shows its HP" % c.display_name)
		_check(panel.trait_label.text == panel_script.trait_text(c), "%s trait line" % c.display_name)
		var abilities := [c.ability_auto, c.ability_q, c.ability_e, c.ability_r]
		_check(panel.ability_stat_labels.size() == 4, "%s shows four abilities" % c.display_name)
		for j in mini(abilities.size(), panel.ability_stat_labels.size()):
			var a: AbilityData = abilities[j]
			var line: String = panel.ability_stat_labels[j].text
			_check(("Cooldown %ss" % panel_script.num(a.cooldown)) in line, "%s cooldown" % a.display_name)
			_check(("Damage %s" % panel_script.num(a.damage)) in line, "%s damage" % a.display_name)

	hub._focus(0, true)
	_key(&"hub_right")
	await process_frame
	_key(&"hub_right", false)
	_check(hub.focus_index == 1, "hub_right focuses the next pedestal")
	_key(&"hub_right")
	await process_frame
	_key(&"hub_right", false)
	_check(hub.focus_index == 0, "hub_right wraps")
	_key(&"hub_left")
	await process_frame
	_key(&"hub_left", false)
	_check(hub.focus_index == 1, "hub_left wraps back")
	for i in 30:
		await physics_frame
	_check(absf(hub.camera.global_position.x - (550.0)) < 1.0, "camera glides to the focused pedestal")

	# Mouse click on the first pedestal (world to screen through the canvas transform).
	var screen: Vector2 = hub.get_viewport().get_canvas_transform() * (hub.pedestals[0].global_position + Vector2(0, -14))
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = screen
		click.global_position = screen
		Input.parse_input_event(click)
		await physics_frame
		await physics_frame
	_check(hub.focus_index == 0, "clicking a pedestal focuses it")

	# Choose starts exactly one run.
	_session.last_character = null
	hub._confirm()
	hub._confirm()
	_check(_session.last_character == chars[0], "Choose sets the character")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

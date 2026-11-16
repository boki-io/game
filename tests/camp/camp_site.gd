extends SceneTree
## The camp in the hub: it exists at CAMP_POS and is clear of the training area, pedestals, sign and door lane,
## decor keeps off its reserved rect, interact near it opens the camp screen (walk mode only), interact near a
## pedestal still goes back to browse, the prompt text near each target, and the lockout.
## Run: godot --headless --path . --script tests/camp/camp_site.gd

var _failed := false


class StubScreen:
	extends Control
	var opened := 0

	func open() -> void:
		opened += 1


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
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _wait(60)
	var cp: Vector2 = hub.CAMP_POS
	var rect := Rect2(cp.x - 50.0, cp.y - 45.0, 100.0, 80.0)

	# The camp exists, drawn under the Player, with no collider or click area.
	var site: Node2D = hub.camp_site
	_check(site != null and site.get_parent() == hub.get_node("World"), "CampSite is a child of World")
	_check(site.position == cp and site.z_index == -1, "at CAMP_POS with z_index -1")
	_check(site.get_child_count() == 0 and not (site is CollisionObject2D), "no collider, no click area")

	# Clear of everything else.
	_check(not rect.intersects(hub.TRAINING_AREA), "clear of the training area")
	for p in hub.pedestals:
		_check(not rect.intersects(Rect2(p.position + Vector2(-34, -60), Vector2(68, 90))), "clear of a pedestal")
	_check(not rect.intersects(Rect2(hub.SIGN_POS.x - 70.0, hub.SIGN_POS.y - 30.0, 140.0, 50.0)), "clear of the sign")
	_check(not rect.intersects(Rect2(hub.door.position.x - 24.0, 0.0, 48.0, 110.0)), "clear of the door lane")
	_check(hub.reserved_areas().has(rect), "the camp rect is reserved")
	for d in hub.get_node("World/Decor").get_children():
		_check(not rect.has_point(d.position), "decor off the camp rect")
	for p in hub.pedestals:
		_check(p.position.distance_to(cp) > hub.INTERACT_RADIUS + hub.CAMP_RADIUS, "a pedestal is not in range of the camp")

	var stub := StubScreen.new()
	hub.camp_screen = stub
	hub._open_camp()
	_check(stub.opened == 1, "_open_camp calls open()")
	stub.opened = 0

	# Browse mode: nothing, even standing nowhere near anything.
	_check(hub.mode == hub.Mode.BROWSE, "starts in browse mode")
	await _action(&"interact")
	_check(stub.opened == 0 and hub.mode == hub.Mode.BROWSE, "interact does nothing in browse mode")
	_check(not hub.prompt.visible, "no prompt in browse mode")

	# Walk mode.
	await _action(&"hub_confirm")
	_check(hub.mode == hub.Mode.WALK, "walk mode")
	var p = root.get_node("PlayerRegistry").players[0]
	await _wait(20)  # past the lockout
	p.global_position = cp + Vector2(0, 20)
	await _wait(3)
	_check(hub.prompt.visible and hub.prompt.text == "F: Camp", "prompt 'F: Camp' near the camp")
	await _action(&"interact")
	_check(stub.opened == 1 and hub.mode == hub.Mode.WALK, "interact near the camp opens it")

	# Lockout applies.
	stub.opened = 0
	hub._lockout = 0.2
	await _action(&"interact")
	_check(stub.opened == 0, "interact inside the lockout is ignored")
	await _wait(20)

	# Just outside CAMP_RADIUS: nothing.
	p.global_position = cp + Vector2(hub.CAMP_RADIUS + 4.0, 0)
	await _wait(3)
	_check(not hub.prompt.visible, "no prompt outside CAMP_RADIUS")
	await _action(&"interact")
	_check(stub.opened == 0, "interact outside CAMP_RADIUS does nothing")

	# No camp screen assigned: harmless.
	hub.camp_screen = null
	p.global_position = cp
	await _wait(3)
	await _action(&"interact")
	_check(hub.mode == hub.Mode.WALK, "interact near the camp with no screen does nothing")

	# Near a pedestal: its own text, and interact goes back to browse.
	hub.camp_screen = stub
	p.global_position = hub.pedestals[0].position + Vector2(0, 20)
	await _wait(3)
	_check(hub.prompt.visible and hub.prompt.text == "F: Change character", "prompt 'F: Change character' near a pedestal")
	await _action(&"interact")
	_check(hub.mode == hub.Mode.BROWSE and stub.opened == 0, "interact near a pedestal still returns to browse")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

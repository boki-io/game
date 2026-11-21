extends SceneTree
## The chest in the hub (spec 1.4): it stands right of the door with the 32x32 art, clear of everything else in the room
## (door trigger, torches, camp, pedestals, training area, decor); its interaction zone overlaps no other; the prompt
## reads "F: Inventory" within reach in walk mode only; the interact action calls the inventory screen once, after the
## lockout; closing it with a change rebuilds the hub player. The screen is a stub here (tests/inventory/inventory_screen.gd
## tests the real one).
## Run: godot --headless --path . --script tests/inventory/hub_chest.gd

const STUB_SOURCE := """extends Control
signal closed(changed)
var opens := []
func open(character) -> void:
	opens.append(character)
	get_tree().paused = true
func close(changed := false) -> void:
	get_tree().paused = false
	closed.emit(changed)
"""

var _failed := false
var _hub: Node


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
	_hub = load("res://scenes/hub.tscn").instantiate()
	root.add_child(_hub)
	current_scene = _hub
	await _wait(90)
	_layout()
	await _interaction()
	_hub.queue_free()
	await process_frame
	paused = false
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _layout() -> void:
	var hub := _hub
	var chest = hub.chest
	_check(chest != null and chest.position == hub.CHEST_POS and chest.get_parent() == hub.get_node("World"), "the chest is in World at CHEST_POS")
	_check(chest.sprite.texture.get_width() == 32 and chest.sprite.texture.get_height() == 32, "its art is the 32x32 chest")
	_check(chest.sprite.offset == Vector2(-16, -27) and not chest.sprite.centered, "its origin is the base of the opaque pixels")
	var door: Node2D = hub.door
	_check(hub.CHEST_POS.x >= door.position.x + 80.0, "the chest is right of the door (x %s, door %s)" % [hub.CHEST_POS.x, door.position.x])
	var frame := Rect2(hub.CHEST_POS - Vector2(16, 27), Vector2(32, 32))
	var trigger := Rect2(door.position.x - 24.0, hub.WALL_BAND, 48.0, 24.0)
	_check(not frame.intersects(trigger), "the sprite is off the door trigger")
	_check(frame.position.y >= hub.WALL_BAND, "the sprite is below the wall band")
	for torch_x in [door.position.x - 44.0, door.position.x + 44.0]:
		_check(not frame.has_point(Vector2(torch_x, 9.0)), "the sprite does not cover the torch at %s" % torch_x)
	_check(not frame.intersects(hub.TRAINING_AREA), "the sprite is off the training area")
	_check(hub.CAMP_POS.distance_to(hub.CHEST_POS) > hub.CAMP_RADIUS + hub.CHEST_RADIUS, "the camp and chest zones do not overlap")
	for p in hub.pedestals:
		_check(p.position.distance_to(hub.CHEST_POS) > hub.INTERACT_RADIUS + hub.CHEST_RADIUS, "the chest zone does not reach a pedestal")
	_check(hub.CHEST_POS.distance_to(Vector2(hub.SIGN_POS)) > 100.0, "the chest is far from the sign")
	# The door's trigger is out of the chest's reach: a circle of CHEST_RADIUS around the base misses the rectangle.
	var nearest := Vector2(clampf(hub.CHEST_POS.x, trigger.position.x, trigger.end.x), clampf(hub.CHEST_POS.y, trigger.position.y, trigger.end.y))
	_check(nearest.distance_to(hub.CHEST_POS) > hub.CHEST_RADIUS, "the chest zone does not reach the door trigger")
	var rect := Rect2(hub.CHEST_POS.x - 24.0, hub.CHEST_POS.y - 40.0, 48.0, 56.0)
	_check(hub.reserved_areas().has(rect), "reserved_areas() holds the chest's rectangle")
	for d in hub.get_node("World/Decor").get_children():
		_check(not rect.grow(24.0).has_point(d.position), "decor at %s is within 24 px of the chest" % d.position)
	# Back from a run the player stands below the door, out of the chest's reach.
	var back := Vector2(door.position.x, hub.WALL_BAND + hub.SPAWN_BELOW_DOOR + door.SIZE.y)
	_check(back.distance_to(hub.CHEST_POS) > hub.CHEST_RADIUS, "the spot below the door is out of reach of the chest (%.0f px)" % back.distance_to(hub.CHEST_POS))


func _interaction() -> void:
	var hub := _hub
	var stub := Control.new()
	var script := GDScript.new()
	script.source_code = STUB_SOURCE
	script.reload()
	stub.set_script(script)
	hub.get_node("UI").add_child(stub)
	hub.inventory_screen = stub
	stub.closed.connect(hub._on_inventory_closed)

	# Browse mode: nothing to interact with.
	_check(hub.mode == hub.Mode.BROWSE and hub._interact_target() == &"", "browse mode: no interaction")
	hub._focus(0, true)
	await _wait(10)
	await _action(&"hub_confirm")
	_check(hub.mode == hub.Mode.WALK, "walk mode after choosing")
	var p = hub.player
	p.global_position = hub.CHEST_POS + Vector2(0, 10)
	await _wait(3)
	_check(hub._interact_target() == &"chest" and hub.prompt.visible and hub.prompt.text == "F: Inventory", "near the chest the prompt reads F: Inventory (%s)" % hub.prompt.text)
	# Inside the lockout after the mode change nothing opens (the lockout is 0.2 s; the 13 frames above were about 0.2 s, so set it).
	hub._lockout = 0.2
	await _action(&"interact")
	_check(stub.opens.is_empty(), "interact inside the lockout opens nothing")
	await _wait(20)
	await _action(&"interact")
	_check(stub.opens.size() == 1 and stub.opens[0] == hub.characters[hub.focus_index], "interact opens the screen once, with the character being played")
	_check(paused, "the stub paused the tree")
	# Closing without a change keeps the player; with a change it is rebuilt.
	var before: int = hub.player.get_instance_id()
	stub.close(false)
	await _wait(3)
	_check(hub.player.get_instance_id() == before, "closing without a change keeps the hub player")
	_check(hub._lockout > 0.0, "closing sets the lockout")
	await _wait(20)
	hub.player.global_position = hub.CHEST_POS + Vector2(0, 10)
	await _action(&"interact")
	stub.close(true)
	await _wait(3)
	_check(hub.player.get_instance_id() != before and hub.player.global_position.distance_to(hub.CHEST_POS + Vector2(0, 10)) < 2.0, "closing with a change rebuilds the player in place")
	# Away from the chest: no prompt.
	hub.player.global_position = Vector2(480, 200)
	await _wait(3)
	_check(hub._interact_target() == &"" and not hub.prompt.visible, "away from everything: no prompt")

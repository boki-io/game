extends SceneTree
## The circle iris (spec v0.9 section 4): a scene change closes the iris on the first player (the screen centre with none), changes scene
## and opens it again, `busy` true from the call until the opening ends; the first boot starts closed; the opening focus waits for the
## camera; the rect is hidden when open. Beats are added in a later step.
## Run: godot --headless --path . --script tests/iris_transition.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var fader = root.get_node("SceneFader")
	var FaderScript: GDScript = load("res://scripts/systems/scene_fader.gd")  # at run time: it names the autoloads
	var F: GDScript = load("res://tests/fixture.gd")

	# Let the boot opening finish, then check the open state: busy false, the rect hidden, the hole at least the farthest corner.
	for i in 120:
		await physics_frame
		if not fader.busy:
			break
	_check(not fader.busy and not fader._wipe.visible and fader._wipe.is_open(), "after boot the iris is open and hidden")
	var probe = FaderScript.Iris.new()
	probe.center = Vector2.ZERO
	_check(is_equal_approx(probe.r_max(), Vector2(640, 360).length()), "r_max from a corner is the diagonal, got %s" % probe.r_max())
	probe.center = Vector2(320, 180)
	_check(is_equal_approx(probe.r_max(), Vector2(320, 180).length()), "r_max from the centre is half the diagonal")
	probe.free()

	# A second fader: the first boot starts fully closed, busy, and opens by itself.
	var boot = FaderScript.new()
	root.add_child(boot)
	_check(boot.busy and boot._wipe.radius == 0.0 and boot._wipe.visible, "a boot starts closed, busy and visible")
	for i in 120:
		await physics_frame
		if not boot.busy:
			break
	_check(not boot.busy and boot._wipe.is_open() and not boot._wipe.visible, "and opens by itself")
	boot.queue_free()

	# The focus: no player is the screen centre; a player is its screen position, dead or alive.
	_check(fader._focus().is_equal_approx(fader._wipe.view_size() / 2.0), "no player: the screen centre")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 5)
	var p = F.player()
	var cam = main.get_node("Camera")
	var expected: Vector2 = cam.get_viewport().get_canvas_transform() * (p.global_position + Vector2(0, -8))
	_check(fader._focus().is_equal_approx(expected), "the focus is the player's screen position")
	p.health.take_damage(1e9)
	await F.frames(self, 2)
	_check(p.dead and fader._focus().is_equal_approx(expected), "and still is when the player is dead")
	p.dead = false  # alive again so the scene change below is an ordinary one
	# The settled focus waits for a physics frame and a process frame (the camera places itself in _physics_process).
	var physics_before := Engine.get_physics_frames()
	var settled: Vector2 = await fader._settle_focus()
	_check(Engine.get_physics_frames() > physics_before and settled.is_equal_approx(fader._focus()), "the opening focus waits a physics frame")

	# A scene change: busy from the call, the hole closes to 0, the scene changes, it opens to r_max, busy ends with the opening.
	var scene := Node2D.new()
	scene.name = "Before"
	root.add_child(scene)
	main.queue_free()
	current_scene = scene
	await process_frame
	fader.fade_to_scene("res://scenes/coin.tscn")
	_check(fader.busy and fader._wipe.mouse_filter == Control.MOUSE_FILTER_STOP, "busy and blocking the mouse as soon as the fade starts")
	await physics_frame
	await physics_frame
	_check(fader._wipe.visible, "the rect is shown once the hole starts to close")
	var min_radius := 9999.0
	var max_after := 0.0
	var saw_new_scene := false
	for i in 300:
		await physics_frame
		min_radius = minf(min_radius, fader._wipe.radius)
		if current_scene != null and current_scene != scene:
			saw_new_scene = true
			max_after = maxf(max_after, fader._wipe.radius)
		if not fader.busy and saw_new_scene:
			break
	_check(min_radius <= 1.0, "the hole closed to within 1 px of 0, min %s" % min_radius)
	_check(saw_new_scene, "the scene changed")
	_check(not fader.busy and fader._wipe.is_open() and not fader._wipe.visible, "after the opening: busy false, open and hidden")
	_check(max_after > 100.0, "the hole opened again after the change, max %s" % max_after)
	_check(fader._wipe.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the rect ignores the mouse when open")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

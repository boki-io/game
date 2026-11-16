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

	await _beat_tests(fader, F)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _beat_tests(fader, F: GDScript) -> void:
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 5)
	var p = F.player()
	var screen = fader._focus()

	# The layers: the beat layer has the UI layers' value and a lower sibling index than the UI of the run and of the hub.
	var beat_layer: CanvasLayer = fader._beat.get_parent()
	var wipe_layer: CanvasLayer = fader._wipe.get_parent()
	_check(beat_layer.layer == main.get_node("UI").layer and beat_layer.layer == 1, "the beat layer has the UI layer's value")
	_check(wipe_layer.layer == 100 and beat_layer.get_index() < main.get_node("UI").get_index(), "the beat layer is a lower sibling than the run's UI, the wipe is on top")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	_check(beat_layer.get_index() < hub.get_node("UI").get_index(), "and than the hub's UI")
	hub.free()
	_check(fader._beat.mouse_filter == Control.MOUSE_FILTER_IGNORE and fader._flash_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the beats ignore the mouse")

	# iris_hold: a hole of the given radius around the dead player, busy untouched, kept until released.
	p.health.take_damage(1e9)
	await F.frames(self, 2)
	fader.iris_hold(70.0, 0.7)
	await F.seconds(self, 1.0)
	_check(not fader.busy, "iris_hold does not set busy")
	_check(absf(fader._beat.radius - 70.0) <= 1.0 and fader._beat.visible, "a hole of radius 70 is left, got %s" % fader._beat.radius)
	_check(fader._beat.center.is_equal_approx(fader._focus()), "centred on the dead player")
	# It works while the tree is paused (the tweens belong to SceneFader, which ignores pause).
	get_root().get_tree().paused = true
	fader.iris_release()
	fader.iris_hold(40.0, 0.3)
	for i in 30:
		await physics_frame
	get_root().get_tree().paused = false
	_check(absf(fader._beat.radius - 40.0) <= 1.0, "the beat runs while the tree is paused, got %s" % fader._beat.radius)
	fader.iris_release()
	_check(fader._beat.is_open() and not fader._beat.visible, "iris_release snaps it open and hides it")

	# flash: a colour that fades to nothing over its time and hides itself.
	fader.flash(Color(1.0, 0.92, 0.6, 0.4), 0.3)
	_check(fader._flash_rect.visible and absf(fader._flash_rect.color.a - 0.4) < 0.01, "the flash starts at its colour")
	await F.seconds(self, 0.5)
	_check(not fader._flash_rect.visible and fader._flash_rect.color.a < 0.01, "and fades to 0 and hides")
	_check(not fader.busy, "flash does not set busy")

	# A wipe after a beat starts from the hole's size and centre, not from a full screen; the beat is released once the new scene is up.
	fader.iris_hold(70.0, 0.2)
	await F.seconds(self, 0.5)
	var hole_center: Vector2 = fader._beat.center
	var scene := Node2D.new()
	scene.name = "After"
	root.add_child(scene)
	main.queue_free()
	current_scene = scene
	await process_frame
	fader.fade_to_scene("res://scenes/coin.tscn")
	_check(fader._wipe.center.is_equal_approx(hole_center) and fader._wipe.radius <= 70.0 + 0.01, "the wipe starts from the death hole, radius %s" % fader._wipe.radius)
	for i in 300:
		await physics_frame
		if not fader.busy and current_scene != scene:
			break
	_check(fader._beat.is_open() and not fader._beat.visible, "the beat is released after the scene change")

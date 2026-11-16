extends SceneTree
## HUD relic slots (spec 1.0, section 6): slot rects, the 0.3 s flash timer. Pixels are not tested.
## Run: godot --headless --path . --script tests/relic_hud.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var H: GDScript = load("res://scripts/ui/hud.gd")
	var view := Vector2(640, 360)
	var r0: Rect2 = H.relic_slot_rect(0, view)
	_check(r0 == Rect2(612, 36, 22, 22), "slot 0 rect (%s)" % r0)
	_check(H.relic_slot_rect(3, view).end.y == 136.0, "the column ends at y 136")
	_check(H.relic_slot_rect(1, view).position.y - r0.end.y == 4.0, "gap of 4")
	_check(r0.position.y > 24.0, "starts below the kills and gold rows")

	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var p = F.player()
	var hud = main.get_node("UI/Hud")
	_check(hud.relic_flash_left(0) == 0.0, "no flash at the start")
	p.relics.add_or_raise(RelicRegistry.find(&"thorn_nova"))
	p.relics.add_or_raise(RelicRegistry.find(&"storm_orbs"))
	_check(hud.relic_flash_left(0) > 0.0 and hud.relic_flash_left(1) > 0.0, "gaining a relic flashes its slot")
	_check(hud.relic_flash_left(2) == 0.0, "other slots do not flash")
	await F.seconds(self, 0.5)
	_check(hud.relic_flash_left(0) == 0.0 and hud.relic_flash_left(1) == 0.0, "the flash ends after 0.3 s")
	p.relics.add_or_raise(RelicRegistry.find(&"thorn_nova"))
	_check(is_equal_approx(hud.relic_flash_left(0), H.FLASH_TIME) or hud.relic_flash_left(0) > 0.2, "a raise flashes again")
	p.relics.add_or_raise(RelicRegistry.find(&"fire_trail"), false)
	_check(hud.relic_flash_left(2) == 0.0, "restoring without a flash does not flash")
	main.queue_free()
	await process_frame
	paused = false
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

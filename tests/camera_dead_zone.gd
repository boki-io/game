extends SceneTree
## Camera dead zone: small moves leave the camera still, a big move pulls it along until the player sits on the
## dead zone's edge (smoothing settles), the camera stays inside the arena, and a fresh run starts centred on the player.
## Run: godot --headless --path . --script tests/camera_dead_zone.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 10)
	var p = F.player()
	var cam = main.get_node("Camera")
	var zone: Vector2 = cam.get_viewport_rect().size * 0.5 * Vector2(cam.dead_zone_x, cam.dead_zone_y)
	var anchor: Vector2 = p.global_position - Vector2(0, 12)
	_check(cam.global_position.distance_to(anchor) <= 1.0, "a fresh run starts centred on the player")

	# Inside the dead zone: the camera does not move.
	var before: Vector2 = cam.global_position
	p.global_position += Vector2(zone.x * 0.8, 0)
	await F.seconds(self, 1.0)
	_check(cam.global_position == before, "camera still while the player stays inside the dead zone")

	# Far outside: after settling the player sits on the edge of the dead zone, not the centre.
	p.global_position += Vector2(200, 0)
	await F.seconds(self, 3.0)
	var off: float = (p.global_position - Vector2(0, 12) - cam.global_position).x
	_check(absf(off - zone.x) <= 1.5, "player ends on the dead zone edge (offset %.1f, zone %.1f)" % [off, zone.x])

	# Smoothing: right after a jump the camera has not caught up yet.
	p.global_position += Vector2(150, 0)
	await F.frames(self, 2)
	_check(cam.global_position.x < p.global_position.x - zone.x - 20.0, "camera eases rather than snapping")

	# Arena edge: the camera never shows past the limits.
	p.global_position = Vector2(Arena.world_size) - Vector2(4, 4)
	await F.seconds(self, 4.0)
	var half: Vector2 = cam.get_viewport_rect().size * 0.5
	_check(cam.global_position.x <= Arena.world_size.x - half.x + 0.5, "camera stops at the right wall")
	_check(cam.global_position.y <= Arena.world_size.y - half.y + 0.5, "camera stops at the bottom wall")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

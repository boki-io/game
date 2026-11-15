extends SceneTree
## The hub's cave: the rock band is solid on all four sides (the Player stops at its inner edge), the door still
## triggers, decor stays off the reserved areas and is limited, and the floor and decor are identical on every load.
## Run: godot --headless --path . --script tests/hub_cave.gd

const BAND := 16.0
const PLAYER_BODY := 10.0  # the collision circle: centre 5px above the feet, radius 5

var _failed := false
var _players: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _floor_hash(hub: Node) -> int:
	var ground: TileMapLayer = hub.get_node("World/Ground")
	var cells := []
	for c in ground.get_used_cells():
		cells.append([c, ground.get_cell_atlas_coords(c)])
	return hash(cells)


func _decor_signature(hub: Node) -> Array:
	var out := []
	for d in hub.get_node("World/Decor").get_children():
		out.append([d.kind, d.variant, d.position])
	return out


func _init() -> void:
	await process_frame
	await process_frame
	_players = root.get_node("PlayerRegistry")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _wait(90)
	var size := Vector2(960, 560)
	_check(hub.get_node("Arena").wall_band == int(BAND), "the hub's rock band is 16px")

	# Decor: limited, clear of everything reserved, deterministic.
	var decor: Array = hub.get_node("World/Decor").get_children()
	_check(decor.size() > 0 and decor.size() <= 60, "decor count is 1..60 (%d)" % decor.size())
	for d in decor:
		for r in hub.reserved_areas():
			_check(not r.grow(24.0).has_point(d.position), "decor at %s is within 24px of a reserved area" % d.position)
		_check(Rect2(Vector2(BAND, BAND), size - Vector2(BAND, BAND) * 2.0).has_point(d.position), "decor at %s is inside the walls" % d.position)
	var layout_a := HubDecor.layout(size, BAND, hub.reserved_areas())
	var layout_b := HubDecor.layout(size, BAND, hub.reserved_areas())
	_check(layout_a == layout_b, "the decor layout is seeded")

	var hash_a := _floor_hash(hub)
	var sig_a := _decor_signature(hub)
	var hub2: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub2)
	await _wait(3)
	_check(_floor_hash(hub2) == hash_a, "the floor is identical on every load")
	_check(_decor_signature(hub2) == sig_a, "the decor is identical on every load")
	hub2.queue_free()
	await _wait(3)
	current_scene = hub

	# Walls: walk into each side and stop at the band's inner edge.
	hub._focus(0, true)
	await _wait(20)
	hub._confirm()
	await _wait(5)
	var p = _players.players[0]
	var tries := {
		"north": [Vector2(300, 60), Vector2(0, -80)],
		"south": [Vector2(300, 500), Vector2(0, 80)],
		"west": [Vector2(60, 300), Vector2(-80, 0)],
		"east": [Vector2(900, 300), Vector2(80, 0)],
	}
	for side in tries:
		p.global_position = tries[side][0]
		p.move_and_collide(tries[side][1])
		var pos: Vector2 = p.global_position
		match side:
			"north":
				_check(pos.y >= BAND + PLAYER_BODY - 0.5, "north rock band is solid (y=%.1f)" % pos.y)
			"south":
				_check(pos.y <= size.y - BAND + 0.5, "south rock band is solid (y=%.1f)" % pos.y)
			"west":
				_check(pos.x >= BAND + 5.0 - 0.5, "west rock band is solid (x=%.1f)" % pos.x)
			"east":
				_check(pos.x <= size.x - BAND - 5.0 + 0.5, "east rock band is solid (x=%.1f)" % pos.x)

	# The door still triggers at the band's inner edge.
	await _wait(20)
	p.global_position = Vector2(480, 80)
	await _wait(3)
	p.global_position = Vector2(480, 30)
	await _wait(5)
	_check(root.get_node("SceneFader").busy, "the door triggers just inside the rock band")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## The run's cave arena: the freestanding rock walls (varied lengths, seeded, clear of the start and of each other),
## solid for the Player, enemies kept inside the rock band, and the layout the same on every run.
## Run: godot --headless --path . --script tests/arena_cave.gd

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
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await _wait(3)
	var p = F.player()
	var size := Vector2(1600, 896)
	_check(Arena.world_size == Vector2i(1600, 896), "the run arena is full size")
	_check(main.get_node("Arena").wall_band == 16, "the run has the 16px rock band")

	var walls: Array[Rect2] = main.rock_walls
	var lengths := {}
	for w in walls:
		lengths[maxf(w.size.x, w.size.y)] = true
		_check(minf(w.size.x, w.size.y) == 16.0, "wall %s is 16px thick" % w)
		_check(Rect2(Vector2(16, 16), size - Vector2(32, 32)).encloses(w), "wall %s is inside the rock band" % w)
		_check(not w.intersects(Rect2(size / 2.0 - Vector2(110, 110), Vector2(220, 220))), "wall %s keeps the start clear" % w)
	_check(walls.size() >= 8, "at least 8 walls (%d)" % walls.size())
	_check(lengths.size() >= 4, "at least 4 different lengths (%d)" % lengths.size())
	for i in walls.size():
		for j in range(i + 1, walls.size()):
			_check(not walls[i].grow(40.0).intersects(walls[j]), "walls %d and %d leave a passage" % [i, j])
	var again := CaveWall.layout(size, 16.0, [Rect2(size / 2.0 - Vector2(110, 110), Vector2(220, 220))])
	_check(again == walls, "the wall layout is seeded")

	# Solid for the Player: walk into the first wall from its south side.
	var w: Rect2 = walls[0]
	var from := Vector2(w.get_center().x, w.end.y + 40.0)
	p.global_position = from
	p.move_and_collide(Vector2(0, -80.0))
	var horizontal := w.size.x > w.size.y
	if horizontal:
		_check(p.global_position.y >= w.end.y + 9.5, "the Player cannot walk through a wall (y=%.1f, wall bottom %.1f)" % [p.global_position.y, w.end.y])

	# Enemies stay out of the rock band.
	p.global_position = size / 2.0
	var e = F.spawn_enemy(main, "grunt", Vector2(3, 3), 1000.0)
	await _wait(5)
	_check(e.global_position.x >= 16.0 and e.global_position.y >= 16.0, "an enemy is kept out of the rock band (%s)" % e.global_position)

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

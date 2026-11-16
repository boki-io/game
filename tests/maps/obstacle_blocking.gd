extends SceneTree
## Walls and pillars block enemies (spec 0.6, 6.6): push-out and sliding, knockback, going round a wall, the director's
## spawn rule, the flow field's search budget, the Ranged and Dasher line-of-sight rules, the stuck failsafe, hysteresis
## at a corner, and the hub (no ObstacleMap) unchanged. Obstacles are placed by hand in the default arena.
## Run: godot --headless --path . --script tests/maps/obstacle_blocking.gd

const SEED_COUNT := 30
const ObstacleMapT := preload("res://scripts/maps/obstacle_map.gd")  # compiles without the autoloads
const FLOW_CELL := 16.0

var _failed := false
var F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## A run with the spawner off, the legacy walls and pillars removed, and exactly `walls` and `pillars` in the way
## (real CaveWall colliders for shots and the Player, and the ObstacleMap for enemies). The Player stands at
## `player_pos`, cannot be hurt and does not auto-attack.
func _world(walls: Array[Rect2], pillars: Array[Vector2], player_pos: Vector2) -> Node:
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	for n in main.get_node("World/Props").get_children():
		n.free()
	for n in main.get_children():
		if n.is_in_group(&"obstacles"):
			n.remove_from_group(&"obstacles")
			main.remove_child(n)
			n.free()
	for r in walls:
		var w := CaveWall.new()
		main.get_node("World/Props").add_child(w)
		w.setup(r)
	var map = _map(walls, pillars)
	main.add_child(map)
	main.spawn_director.obstacles = map
	var p = F.player()
	p.hurtbox.invulnerable = true
	p.caster.set_physics_process(false)
	p.global_position = player_pos
	await F.frames(self, 2)
	return main


func _map(walls: Array[Rect2], pillars: Array[Vector2]) -> Node:
	var map := ObstacleMapT.new()
	var pad := Vector2(22, 22)
	var size := Vector2(1600, 896)
	map.setup(walls, pillars, size, Rect2(pad, size - pad * 2.0))
	return map


func _end(main: Node) -> void:
	main.queue_free()
	await F.frames(self, 3)


func _spawn(main: Node, id: String, pos: Vector2) -> Node:
	var e = F.spawn_enemy(main, id, pos, 1000.0)
	e.director = main.spawn_director
	return e


func _clear_all(e, map: Node) -> bool:
	return not map.blocked(e.global_position, e.data.hitbox_radius - 0.05)


func _init() -> void:
	await process_frame
	await process_frame
	F = load("res://tests/fixture.gd")
	await _test_geometry()
	await _test_driven_into()
	await _test_round_wall()
	await _test_ranged()
	await _test_dasher()
	await _test_spawn_rule()
	await _test_flow_field()
	await _test_stuck()
	await _test_hysteresis()
	await _test_hub()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _test_geometry() -> void:
	var walls: Array[Rect2] = [Rect2(100, 100, 200, 16)]
	var pillars: Array[Vector2] = [Vector2(500, 506)]  # circle centre (500, 500), radius 6
	var m = _map(walls, pillars)
	_check(m.blocked(Vector2(200, 108), 7.0), "a point inside a wall is blocked")
	_check(not m.blocked(Vector2(200, 130), 7.0), "a point 14 px below a wall is free for r=7")
	_check(m.blocked(Vector2(200, 120), 7.0), "r=7 at 4 px below the wall overlaps")
	var out = m.push_out(Vector2(200, 120), 7.0)
	_check(is_equal_approx(out.y, 123.0) and out.x == 200.0, "push_out leaves the wall by the shortest way (%s)" % out)
	out = m.push_out(Vector2(200, 108), 7.0)  # centre inside: nearest edge is the top (8 px) or bottom (8 px)
	_check(not m.blocked(out, 6.99), "push_out from inside ends outside")
	out = m.push_out(Vector2(505, 500), 7.0)
	_check(absf(out.distance_to(Vector2(500, 500)) - 13.0) < 0.1, "push_out of a pillar to r + 6")
	_check(m.push_out(Vector2(800, 800), 7.0) == Vector2(800, 800), "a free point does not move")
	_check(not m.segment_clear(Vector2(200, 50), Vector2(200, 200), 2.0), "a segment through a wall is not clear")
	_check(m.segment_clear(Vector2(50, 50), Vector2(400, 50), 2.0), "a segment past a wall is clear")
	_check(not m.segment_clear(Vector2(400, 500), Vector2(600, 500), 2.0), "a segment through a pillar is not clear")
	_check(not m.segment_clear(Vector2(200, 90), Vector2(400, 90), 12.0), "a fat segment grazing a wall is blocked")
	_check(absf(m.ray_distance(Vector2(200, 200), Vector2.UP, 140.0, 7.0) - 77.0) < 0.1,
		"ray_distance stops at the wall grown by the radius (%s)" % m.ray_distance(Vector2(200, 200), Vector2.UP, 140.0, 7.0))
	_check(m.ray_distance(Vector2(200, 200), Vector2.DOWN, 140.0, 7.0) == 140.0, "ray_distance in the open is the cap")
	m.free()


## Each type driven into a wall and a pillar ends outside; 45 degrees into a long wall slides along it; knockback stops.
func _test_driven_into() -> void:
	var walls: Array[Rect2] = [Rect2(700, 300, 16, 320)]
	var pillars: Array[Vector2] = [Vector2(500, 506)]
	var main = await _world(walls, pillars, Vector2(900, 450))  # near: a far Player would teleport them back
	var map = main.spawn_director.obstacles
	for id in ["grunt", "ranged", "dasher"]:
		var e = _spawn(main, id, Vector2(690, 450))
		e.stun(10.0)
		var start: Vector2 = e.global_position
		for i in 60:  # 1 s of being shoved right and down at 45 degrees
			e.apply_knockback(Vector2(150, 150))
			await F.frames(self, 1)
			_check(_clear_all(e, map), "%s never inside the wall" % id)
		_check(e.global_position.x <= 700.0 - e.data.hitbox_radius + 0.1, "%s stays left of the wall" % id)
		_check(e.global_position.y - start.y >= 20.0, "%s slid %.0f px along the wall" % [id, e.global_position.y - start.y])
		e.queue_free()
		# Into the pillar head on.
		var q = _spawn(main, id, Vector2(470, 500))
		q.stun(10.0)
		for i in 60:
			q.apply_knockback(Vector2(200, 0))
			await F.frames(self, 1)
			_check(_clear_all(q, map), "%s never inside the pillar" % id)
		q.queue_free()
	# A single knockback into a wall stops at it.
	var k = _spawn(main, "grunt", Vector2(660, 450))
	k.stun(10.0)
	k.apply_knockback(Vector2(600, 0))
	await F.seconds(self, 1.0)
	_check(is_equal_approx(k.global_position.x, 700.0 - 7.0) or k.global_position.x < 693.0 and _clear_all(k, map),
		"knockback stops at the wall (x=%.1f)" % k.global_position.x)
	await _end(main)


## A grunt behind a long wall comes round the open end; 20 grunts all arrive.
func _test_round_wall() -> void:
	var walls: Array[Rect2] = [Rect2(780, 250, 16, 400)]
	var pillars: Array[Vector2] = []
	var main = await _world(walls, pillars, Vector2(900, 450))
	var map = main.spawn_director.obstacles
	var e = _spawn(main, "grunt", Vector2(700, 450))
	var crossed_ok := true
	var crossed := false
	var arrived := false
	var prev_x: float = e.global_position.x
	for i in 60 * 30:
		await F.frames(self, 1)
		if not _clear_all(e, map):
			crossed_ok = false
		var x: float = e.global_position.x
		if prev_x < 788.0 and x >= 788.0:
			crossed = true
			var y: float = e.global_position.y
			_check(y < 250.0 or y > 650.0, "the grunt crossed the wall line at the open end (y=%.0f)" % y)
		prev_x = x
		if e.global_position.distance_to(F.player().global_position) < 16.0:
			arrived = true
			break
	_check(crossed_ok, "the grunt was never inside the wall")
	_check(crossed and arrived, "a grunt behind a wall reaches the Player (crossed=%s arrived=%s)" % [crossed, arrived])
	e.queue_free()
	var crowd := []
	for i in 20:
		crowd.append(_spawn(main, "grunt", Vector2(640 + (i % 5) * 20, 330 + (i / 5) * 90)))
	var all_there := false
	for i in 60 * 40:
		await F.frames(self, 1)
		all_there = true
		for g in crowd:
			if g.global_position.distance_to(F.player().global_position) > 40.0:
				all_there = false
				break
		if all_there:
			break
	_check(all_there, "20 grunts behind a lane wall all reach the Player")
	await _end(main)


func _shots(main: Node) -> int:
	return get_first_node_in_group(&"projectiles")._live


func _test_ranged() -> void:
	var walls: Array[Rect2] = [Rect2(780, 250, 16, 400)]
	var pillars: Array[Vector2] = []
	var main = await _world(walls, pillars, Vector2(900, 450))
	var e = _spawn(main, "ranged", Vector2(700, 450))
	var fired := false
	for i in 60 * 2:
		await F.frames(self, 1)
		fired = fired or _shots(main) > 0
	_check(not fired, "a Ranged enemy behind a wall fires nothing")
	_check(e.brain._state == 0, "...and walks (APPROACH) instead of holding")
	e.obstacles = _map([] as Array[Rect2], [] as Array[Vector2])  # the wall is gone
	main.add_child(e.obstacles)
	e.global_position = Vector2(780, 450)
	for i in 60 * 5:
		await F.frames(self, 1)
		fired = fired or _shots(main) > 0
		if fired:
			break
	_check(fired, "...and fires once the line is clear")
	e.queue_free()
	await F.seconds(self, 1.5)
	# A shot into the wall vanishes on it.
	var pool = get_first_node_in_group(&"projectiles")
	pool.fire(Vector2(700, 442), Vector2.RIGHT, 200.0, 1.0, 5.0)
	await F.seconds(self, 1.0)
	_check(pool._live == 0, "a shot vanishes on a wall (live=%d)" % pool._live)
	await _end(main)
	# HOLD -> APPROACH when the line is lost, back to HOLD when it returns.
	var open: Array[Rect2] = []
	main = await _world(open, [] as Array[Vector2], Vector2(760, 450))
	var r = _spawn(main, "ranged", Vector2(700, 450))
	await F.seconds(self, 0.3)
	_check(r.brain._state == 1, "a Ranged enemy in range with a clear line holds")
	var blocked_map = _map([Rect2(720, 300, 16, 300)] as Array[Rect2], [] as Array[Vector2])
	main.add_child(blocked_map)
	var clear_map = r.obstacles
	r.obstacles = blocked_map
	await F.seconds(self, 0.2)
	_check(r.brain._state == 1, "it still holds 0.2 s after losing the line (margin 0.3 s)")
	await F.seconds(self, 0.3)
	_check(r.brain._state == 0, "it approaches after 0.3 s without a line")
	r.obstacles = clear_map
	await F.seconds(self, 0.2)
	_check(r.brain._state == 1, "it holds again when the line is back and it is in range")
	await _end(main)


func _test_dasher() -> void:
	# The lane is cut at a wall behind the Player and the dash never ends inside it.
	var walls: Array[Rect2] = [Rect2(800, 300, 16, 300)]
	var main = await _world(walls, [] as Array[Vector2], Vector2(760, 450))
	var map = main.spawn_director.obstacles
	var d = _spawn(main, "dasher", Vector2(700, 450))
	var data = d.data
	var shortest := 999.0
	var inside := false
	var max_x := 0.0
	for i in 60 * 3:
		await F.frames(self, 1)
		if d.brain._state == 1 or d.brain._state == 2:
			shortest = minf(shortest, d.brain._lane.length)
		inside = inside or not _clear_all(d, map)
		max_x = maxf(max_x, d.global_position.x)
	_check(shortest < data.dash_distance - 20.0, "the lane is shortened at the wall (length %.0f of %.0f)" % [shortest, data.dash_distance])
	_check(absf(shortest - (800.0 - 7.0 - 700.0)) < 3.0, "...to the wall grown by its radius (%.1f)" % shortest)
	_check(not inside, "a Dasher is never inside a wall, dash included")
	_check(max_x <= 800.0 - 7.0 + 0.1, "it stopped at the wall (x=%.1f)" % max_x)
	await _end(main)
	# No line of sight: no AIM.
	var between: Array[Rect2] = [Rect2(730, 300, 16, 300)]
	main = await _world(between, [] as Array[Vector2], Vector2(780, 450))
	var e = _spawn(main, "dasher", Vector2(690, 450))
	var aimed := false
	for i in 40:
		await F.frames(self, 1)
		aimed = aimed or e.brain._state == 1
	_check(not aimed, "a Dasher without a clear line never starts to aim")
	await _end(main)


func _test_spawn_rule() -> void:
	# A dense, hand-made layout (rows of walls and pillars) like the Bone Warren's.
	var walls: Array[Rect2] = []
	for row in range(4):
		for col in range(3):
			walls.append(Rect2(160 + col * 440 + (row % 2) * 120, 160 + row * 200, 200, 16))
	var pillars: Array[Vector2] = [Vector2(400, 330), Vector2(1100, 530)]
	var main = await _world(walls, pillars, Vector2(800, 450))
	var map = main.spawn_director.obstacles
	var d = main.spawn_director
	var bad := 0
	var made := 0
	for s in SEED_COUNT:
		seed(s)
		for i in 100:
			var around := Vector2(randf_range(100, 1500), randf_range(100, 800))
			var pos: Variant = d.ring_position(around)
			if pos != null:
				made += 1
				if map.blocked(pos, 6.99):
					bad += 1
	_check(made > 0 and bad == 0, "spawn/teleport positions never inside an obstacle (%d of %d)" % [bad, made])
	# Forced: a candidate in a wall is pushed out, not lost.
	var big: Array[Rect2] = [Rect2(0, 0, 1600, 896)]
	var solid = _map(big, [] as Array[Vector2])
	d.obstacles = solid
	_check(d.ring_position(Vector2(800, 450)) != null, "with every candidate blocked a position is still returned")
	await _end(main)
	solid.free()


func _test_flow_field() -> void:
	var walls: Array[Rect2] = []
	for row in range(4):
		for col in range(3):
			walls.append(Rect2(160 + col * 440 + (row % 2) * 120, 160 + row * 200, 200, 16))
	var main = await _world(walls, [] as Array[Vector2], Vector2(800, 450))
	var map = main.spawn_director.obstacles
	await F.seconds(self, 0.6)
	var flow = map.flow()
	_check(flow.has_field() and map.searches_started == 1, "one search for a Player that has not moved (%d)" % map.searches_started)
	var unreached := 0
	var not_falling := 0
	for y in flow.height:
		for x in flow.width:
			var cell := Vector2i(x, y)
			if flow.is_blocked(cell):
				continue
			var d: int = flow.distance(cell)
			if d < 0:
				unreached += 1
				continue
			if d > 0:
				var dir: Vector2 = flow.direction_at((Vector2(cell) + Vector2(0.5, 0.5)) * FLOW_CELL)
				var n := cell + Vector2i(roundi(dir.x), roundi(dir.y))
				if dir == Vector2.ZERO or flow.distance(n) < 0 or flow.distance(n) >= d:
					not_falling += 1
	_check(unreached == 0, "a path exists from every free cell (%d unreached)" % unreached)
	_check(not_falling == 0, "distances fall toward the Player (%d cells do not)" % not_falling)
	# Moving inside the same cell starts nothing; entering another cell does, but not within 0.25 s.
	F.player().global_position = Vector2(802, 452)
	await F.seconds(self, 0.5)
	_check(map.searches_started == 1, "no new search while the Player stays in its cell (%d)" % map.searches_started)
	F.player().global_position = Vector2(850, 450)
	await F.seconds(self, 0.5)
	_check(map.searches_started == 2, "a new cell starts one new search (%d)" % map.searches_started)
	F.player().global_position = Vector2(900, 450)
	await F.frames(self, 2)
	F.player().global_position = Vector2(950, 450)
	await F.frames(self, 3)
	_check(map.searches_started == 3, "a second cell change within 0.25 s starts nothing (%d)" % map.searches_started)
	await F.seconds(self, 0.5)
	_check(map.searches_started == 4, "...until the interval has passed (%d)" % map.searches_started)
	_check(map.max_frame_expansions <= 1000, "no frame did more than 1000 expansions (%d)" % map.max_frame_expansions)
	_check(map.max_frame_expansions > 0, "the budget was actually used")
	# A Player 6 px from a wall still gets a field.
	var side: Array[Rect2] = [Rect2(700, 300, 16, 300)]
	var m2 = _map(side, [] as Array[Vector2])
	var f2 = m2.flow()
	f2.begin([Vector2(694, 450)] as Array[Vector2])
	while f2.searching:
		f2.step(1000)
	var reached := 0
	for i in f2.width * f2.height:
		if f2.distance(Vector2i(i % f2.width, i / f2.width)) >= 0:
			reached += 1
	_check(reached > 1000, "a Player 6 px from a wall gets a non-empty field (%d cells)" % reached)
	m2.free()
	await _end(main)


func _test_stuck() -> void:
	# A grunt sealed in a pocket asks to move and cannot: it is recycled after 3 s.
	var pocket: Array[Rect2] = [Rect2(440, 400, 120, 16), Rect2(440, 500, 120, 16), Rect2(440, 400, 16, 116), Rect2(544, 400, 16, 116)]
	var main = await _world(pocket, [] as Array[Vector2], Vector2(800, 450))
	var g = _spawn(main, "grunt", Vector2(500, 458))
	await F.seconds(self, 2.0)
	_check(Rect2(456, 416, 88, 84).has_point(g.global_position), "the sealed grunt is still in its pocket before 3 s")
	await F.seconds(self, 4.5)  # a 3 s window ends while it walks to the pocket wall; the next one finds it stuck
	_check(g.global_position.distance_to(Vector2(500, 458)) > 100.0, "...and recycled after 3 s of being stuck")
	g.queue_free()
	# A holding Ranged enemy, a stunned enemy and a Dasher in AIM are never recycled.
	var r = _spawn(main, "ranged", Vector2(750, 450))
	var s = _spawn(main, "grunt", Vector2(500, 458))
	s.stun(9.0)
	await F.seconds(self, 4.5)
	_check(r.global_position.distance_to(Vector2(750, 450)) < 30.0, "a holding Ranged enemy is not recycled")
	_check(s.global_position.distance_to(Vector2(500, 458)) < 5.0, "a stunned enemy is not recycled")
	var d = _spawn(main, "dasher", Vector2(700, 450))
	await F.frames(self, 4)
	_check(d.brain._state == 1 and not d.brain.asks_to_move(), "a Dasher in AIM asks for no movement")
	await _end(main)


func _test_hysteresis() -> void:
	# Around the end of a wall the straight/flow choice must hold for 0.5 s once it switches to flow.
	var walls: Array[Rect2] = [Rect2(780, 300, 16, 300)]
	var main = await _world(walls, [] as Array[Vector2], Vector2(900, 450))
	var e = _spawn(main, "grunt", Vector2(700, 450))
	var on_since := -1
	var worst := 999
	var switches := 0
	var was: bool = e._on_flow
	for i in 60 * 14:
		await F.frames(self, 1)
		var now: bool = e._on_flow
		if now != was:
			switches += 1
			if now:
				on_since = i
			elif on_since >= 0:
				worst = mini(worst, i - on_since)
			was = now
		if e.global_position.distance_to(F.player().global_position) < 16.0:
			break
	_check(worst >= 29, "flow mode lasts at least 0.5 s once entered (shortest %d frames, %d switches)" % [worst, switches])
	_check(switches >= 2, "the grunt did use the flow field (%d switches)" % switches)
	await _end(main)


func _test_hub() -> void:
	var main: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await F.frames(self, 3)
	_check(get_nodes_in_group(&"obstacles").is_empty(), "the hub has no ObstacleMap")
	var any_enemy := false
	for n in main.find_children("*", "Node2D", true, false):
		if n.has_method("apply_knockback"):
			any_enemy = true
			_check(n.obstacles == null, "a hub dummy has no obstacles")
	_check(any_enemy, "the hub has dummies to check")
	main.queue_free()
	paused = false
	await F.frames(self, 3)

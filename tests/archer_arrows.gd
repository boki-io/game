extends SceneTree
## Archer arrows (spec 1.1, sections 5 and 6 and the target point of 4.4): `fire` without `opts` as before, the
## bounce from enemy to enemy, the ricochet off walls, pillars and the arena edge, the hub (no ObstacleMap),
## Steady Aim, `PlayerInput.target_point` and the shared cap.
## Run: godot --headless --path . --script tests/archer_arrows.gd

const SEED_COUNT := 30
const MAX_LIVE := 40  # PlayerProjectiles.MAX_LIVE (not named here: it uses an autoload)
const SteadyAimScript := preload("res://scripts/characters/steady_aim.gd")
const DMG := 10.0

var _failed := false
var _main: Node
var _p
var _F: GDScript
var _c := Vector2.ZERO  # the player's position: the middle of the arena


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	root.get_node("GameSession").scene_hook = func(_path: String) -> void: pass
	_F = load("res://tests/fixture.gd")
	_statics()
	await _plain()
	await _enemy_bounce()
	await _walls()
	await _pillar()
	await _edge()
	await _hub()
	await _steady()
	await _cap()
	await _seeds()
	root.get_node("GameSession").scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## A fresh run with an empty obstacle map; the player stands in the middle and does not shoot.
func _begin() -> void:
	if _main:
		_main.free()
		paused = false
		await process_frame
	_main = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	_p = _F.player()
	_p.caster.set_physics_process(false)
	_c = _p.global_position
	_map([], [])


func _map(walls: Array[Rect2], pillars: Array[Vector2]) -> void:
	var map := ObstacleMap.get_for(_main)
	if map == null:
		map = ObstacleMap.new()
		_main.add_child(map)
	map.setup(walls, pillars, map.size, map.bounds)


func _pool():
	return _main.get_tree().get_first_node_in_group(&"player_projectiles")


func _enemy(offset: Vector2):
	return _F.spawn_enemy(_main, "grunt", _c + offset, 50.0, true)


func _arrow():
	for a in _pool().get_children():
		if a.active:
			return a
	return null


## Fires one arrow with the Archer's usual options plus `extra`; returns the projectile.
func _shoot(offset: Vector2, dir: Vector2, extra: Dictionary = {}, speed := 300.0, range_px := 700.0):
	var opts := {&"hits": 3, &"bounces": 3, &"arrow": true}
	opts.merge(extra, true)
	_pool().clear()
	_check(_pool().fire(_c + offset, dir, speed, DMG, range_px, 0, opts), "fire accepted")
	return _arrow()


func _lost(e) -> float:
	return e.health.max_health - e.health.current


func _wait(frames: int) -> void:
	await _F.frames(self, frames)


func _statics() -> void:
	var S = SteadyAimScript
	_check(is_equal_approx(S.multiplier(0.0), 1.0), "steady: 1.0 below the minimum")
	_check(is_equal_approx(S.multiplier(40.0), 1.0), "steady: 1.0 at 40 px")
	_check(is_equal_approx(S.multiplier(100.0), 1.15), "steady: 1.15 at 100 px")
	_check(is_equal_approx(S.multiplier(160.0), 1.3), "steady: 1.3 at 160 px")
	_check(is_equal_approx(S.multiplier(400.0), 1.3), "steady: 1.3 beyond")
	_check(is_equal_approx(S.multiplier(80.0, 80.0), 1.3), "steady: a shorter full distance is reached sooner")
	_check(is_equal_approx(S.multiplier(60.0, 80.0), 1.0 + 0.3 * 0.5), "steady: linear towards a shorter full distance")
	_check(S.new().active == false, "steady: active is false")
	var T: GDScript = load("res://scripts/player/player_input.gd")  # uses an autoload: not a preload
	var o := Vector2(100, 100)
	_check(T.target_point(o, Vector2(150, 100), true, Vector2.DOWN, 240.0).is_equal_approx(Vector2(150, 100)), "target: the mouse inside the range")
	_check(T.target_point(o, Vector2(1000, 100), true, Vector2.DOWN, 240.0).is_equal_approx(Vector2(340, 100)), "target: the mouse clamped to the range")
	_check(T.target_point(o, Vector2(1000, 100), false, Vector2.DOWN, 240.0).is_equal_approx(Vector2(100, 340)), "target: aim * range without the mouse")
	_check(T.target_point(o, Vector2(1000, 100), false, Vector2.LEFT, 80.0).is_equal_approx(Vector2(20, 100)), "target: aim * range, other range")


## `fire` without opts: pierce 1 hits two enemies and ends, props are passed, no steady, no bounce.
func _plain() -> void:
	await _begin()
	var a = _enemy(Vector2(80, 0))
	var b = _enemy(Vector2(120, 0))
	var c = _enemy(Vector2(160, 0))
	await _wait(2)
	_check(_pool().fire(_c, Vector2.RIGHT, 300.0, DMG, 400.0, 1), "plain: fired")
	await _wait(120)
	_check(is_equal_approx(_lost(a), DMG) and is_equal_approx(_lost(b), DMG), "plain: pierce 1 hits two enemies for the damage")
	_check(_lost(c) == 0.0 and _arrow() == null, "plain: the third is spared and the bolt is gone")
	# A pillar in the way is passed (no bounces).
	await _begin()
	_map([], [_c + Vector2(60, 6)] as Array[Vector2])
	var d = _enemy(Vector2(120, 0))
	await _wait(2)
	_pool().fire(_c, Vector2.RIGHT, 300.0, DMG, 400.0, 0, {&"arrow": true, &"steady": false})
	await _wait(60)
	_check(is_equal_approx(_lost(d), DMG), "plain: an arrow without bounces passes a pillar (lost %f)" % _lost(d))


func _enemy_bounce() -> void:
	# A at (100, 0), B at (100, 100), E at (160, 200); D is out of reach of A.
	await _begin()
	var a = _enemy(Vector2(100, 0))
	var b = _enemy(Vector2(100, 100))
	var e = _enemy(Vector2(160, 200))
	var far = _enemy(Vector2(100, -200))
	await _wait(2)
	var ar = _shoot(Vector2.ZERO, Vector2.RIGHT)
	var min_bounces := 99
	for i in 150:
		await physics_frame
		if ar.active:
			min_bounces = mini(min_bounces, ar._bounces_left)
	_check(is_equal_approx(_lost(a), DMG) and is_equal_approx(_lost(b), DMG) and is_equal_approx(_lost(e), DMG),
		"bounce: A, B and E are each hit once (%f %f %f)" % [_lost(a), _lost(b), _lost(e)])
	_check(_lost(far) == 0.0, "bounce: an enemy out of reach is not hit")
	_check(not ar.active, "bounce: the arrow ends on its third distinct enemy")
	_check(ar._bounces_left == 1, "bounce: two bounces spent on two turns (left %d)" % ar._bounces_left)
	_check(ar._hit.size() == 3, "bounce: three distinct hits")

	# Nothing in reach: keeps its direction and its bounce.
	await _begin()
	a = _enemy(Vector2(100, 0))
	far = _enemy(Vector2(100, 200))
	await _wait(2)
	ar = _shoot(Vector2.ZERO, Vector2.RIGHT)
	await _wait(30)
	_check(ar.active and ar._bounces_left == 3, "bounce: no target in reach keeps the bounce (left %d)" % ar._bounces_left)
	_check(ar._dir.is_equal_approx(Vector2.RIGHT), "bounce: no target in reach keeps the direction")
	_check(_lost(far) == 0.0, "bounce: the far enemy was not a target")

	# A wall between the arrow and B: B is not reachable, the arrow flies on.
	await _begin()
	_map([Rect2(_c + Vector2(60, 50), Vector2(100, 10))] as Array[Rect2], [] as Array[Vector2])
	a = _enemy(Vector2(100, 0))
	var bb = _enemy(Vector2(100, 100))
	await _wait(2)
	ar = _shoot(Vector2.ZERO, Vector2.RIGHT)
	await _wait(40)
	_check(is_equal_approx(_lost(a), DMG) and _lost(bb) == 0.0, "bounce: a wall hides the next enemy (%f, %f)" % [_lost(a), _lost(bb)])
	_check(ar._bounces_left == 3 and ar._dir.is_equal_approx(Vector2.RIGHT), "bounce: a hidden target costs no bounce")

	# hits 1: ends on the first enemy, no turn.
	await _begin()
	a = _enemy(Vector2(100, 0))
	bb = _enemy(Vector2(100, 60))
	await _wait(2)
	ar = _shoot(Vector2.ZERO, Vector2.RIGHT, {&"hits": 1})
	await _wait(60)
	_check(not ar.active and _lost(bb) == 0.0, "bounce: hits 1 ends on the first enemy")

	# bounces 0 with hits 2: hits two enemies in line, no turn.
	await _begin()
	a = _enemy(Vector2(100, 0))
	bb = _enemy(Vector2(100, 60))
	var cc = _enemy(Vector2(200, 0))
	await _wait(2)
	ar = _shoot(Vector2.ZERO, Vector2.RIGHT, {&"hits": 2, &"bounces": 0})
	await _wait(80)
	_check(_lost(bb) == 0.0 and is_equal_approx(_lost(a), DMG) and is_equal_approx(_lost(cc), DMG), "bounce: bounces 0 goes straight on")
	_check(not ar.active, "bounce: hits 2 ends on the second enemy")


func _walls() -> void:
	await _begin()
	_map([Rect2(_c + Vector2(120, -200), Vector2(20, 400)), Rect2(_c + Vector2(-140, -200), Vector2(20, 400))] as Array[Rect2], [] as Array[Vector2])
	var ar = _shoot(Vector2(0, 5), Vector2.RIGHT, {&"bounces": 2})
	await _wait(40)
	_check(ar.active and ar._dir.x < -0.99 and ar._bounces_left == 1, "wall: reflects off the right wall and spends one bounce (dir %s, left %d)" % [ar._dir, ar._bounces_left])
	await _wait(60)
	_check(ar.active and ar._dir.x > 0.99 and ar._bounces_left == 0, "wall: reflects off the left wall too (dir %s, left %d)" % [ar._dir, ar._bounces_left])
	await _wait(100)
	_check(not ar.active, "wall: with no bounce left the next wall retires it")
	ar = _shoot(Vector2(0, 5), Vector2.RIGHT, {&"bounces": 1})
	await _wait(100)
	_check(not ar.active, "wall: one bounce, retires at the second wall")


func _pillar() -> void:
	await _begin()
	_map([] as Array[Rect2], [_c + Vector2(120, 6)] as Array[Vector2])  # centre at (120, 0)
	var ar = _shoot(Vector2.ZERO, Vector2.RIGHT, {&"bounces": 2})
	await _wait(40)
	_check(ar.active and ar._dir.x < -0.9 and absf(ar._dir.y) < 0.35 and ar._bounces_left == 1, "pillar: head on comes straight back (dir %s)" % ar._dir)
	# At the side the normal points sideways: the arrow glances off downwards and keeps going right.
	ar = _shoot(Vector2(2, 6), Vector2.RIGHT, {&"bounces": 2})
	await _wait(35)
	_check(ar.active and ar._dir.y > 0.2 and ar._dir.x > 0.0 and ar._bounces_left == 1, "pillar: at the side it glances off (dir %s)" % ar._dir)

	# Fired from inside a blocked cell: no bounce is burned on the first frames.
	await _begin()
	_map([Rect2(_c + Vector2(-10, -50), Vector2(30, 100))] as Array[Rect2], [] as Array[Vector2])
	ar = _shoot(Vector2.ZERO, Vector2.RIGHT, {&"bounces": 2})
	await _wait(1)
	_check(ar.active and ar._bounces_left == 2, "inside: no bounce on frame 1")
	await _wait(20)
	_check(ar.active and ar._bounces_left == 2 and ar._dir.is_equal_approx(Vector2.RIGHT) and ar.global_position.x > _c.x + 25.0,
		"inside: leaves the obstacle without bouncing (left %d)" % ar._bounces_left)


func _edge() -> void:
	await _begin()
	var margin: float = Arena.wall_margin
	var right: float = float(Arena.world_size.x) - margin
	var left: float = margin
	var ar = _shoot(Vector2(right - 12.0 - _c.x, 0), Vector2.RIGHT, {&"bounces": 1}, 600.0, 3000.0)
	await _wait(15)
	_check(ar.active and ar._dir.x < -0.99 and ar._bounces_left == 0, "edge: the right edge reflects (dir %s, left %d)" % [ar._dir, ar._bounces_left])
	_check(ar.global_position.x <= right, "edge: stays inside the playable rectangle")
	await _wait(320)
	_check(not ar.active, "edge: with no bounce left the opposite edge retires it")
	# The top edge reflects on the other axis.
	var top = _shoot(Vector2(0, left - _c.y + 12.0), Vector2.UP, {&"bounces": 2}, 600.0, 3000.0)
	await _wait(15)
	_check(top.active and top._dir.y > 0.99 and top._bounces_left == 1, "edge: the top edge reflects (dir %s)" % top._dir)
	# A corner reflects both axes.
	var corner = _shoot(Vector2(right - 6.0 - _c.x, left - _c.y + 6.0), Vector2(1, -1), {&"bounces": 2}, 600.0, 3000.0)
	await _wait(10)
	_check(corner.active and corner._dir.x < -0.5 and corner._dir.y > 0.5, "edge: a corner reflects both axes (dir %s)" % corner._dir)


## No ObstacleMap (the hub): only the edge reflects.
func _hub() -> void:
	await _begin()
	var map := ObstacleMap.get_for(_main)
	_map([Rect2(_c + Vector2(60, -200), Vector2(20, 400))] as Array[Rect2], [] as Array[Vector2])
	map.remove_from_group(&"obstacles")
	_check(ObstacleMap.get_for(_main) == null, "hub: no ObstacleMap found")
	var right: float = float(Arena.world_size.x) - Arena.wall_margin
	var ar = _shoot(Vector2.ZERO, Vector2.RIGHT, {&"bounces": 1}, 600.0, 3000.0)
	await _wait(30)
	_check(ar.active and ar._dir.is_equal_approx(Vector2.RIGHT) and ar._bounces_left == 1 and ar.global_position.x > _c.x + 100.0,
		"hub: the (absent) wall is ignored")
	await _wait(220)
	_check(ar._dir.x < -0.99 and ar._bounces_left == 0 and ar.global_position.x <= right, "hub: the edge reflects (dir %s)" % ar._dir)
	# An enemy bounce works without a map too.
	var a = _enemy(Vector2(100, 0))
	var b = _enemy(Vector2(100, 80))
	await _wait(2)
	_pool().clear()
	ar = _shoot(Vector2.ZERO, Vector2.RIGHT)
	await _wait(50)
	_check(is_equal_approx(_lost(a), DMG) and is_equal_approx(_lost(b), DMG), "hub: bounces between enemies without a map")


func _steady() -> void:
	# Damage by the straight distance from the launch point, not the path: A at 60 px, B at (60, 100).
	await _begin()
	var a = _enemy(Vector2(60, 0))
	var b = _enemy(Vector2(60, 100))
	await _wait(2)
	_shoot(Vector2.ZERO, Vector2.RIGHT, {&"steady": true})
	await _wait(60)
	var S = SteadyAimScript
	var m_a: float = S.multiplier(60.0)  # the distance is to the enemy's position
	var m_b: float = S.multiplier(Vector2(60, 100).length())
	_check(absf(_lost(a) - DMG * m_a) < 0.01, "steady: A hit at 60 px (%f vs %f)" % [_lost(a), DMG * m_a])
	_check(absf(_lost(b) - DMG * m_b) < 0.01, "steady: B scaled by the straight distance 117 px, not the path (%f vs %f)" % [_lost(b), DMG * m_b])
	_check(DMG * m_b < DMG * S.BONUS - 0.1, "steady: below the full bonus")
	# Without the flag no bonus; a custom full distance reaches the bonus sooner.
	await _begin()
	a = _enemy(Vector2(100, 0))
	await _wait(2)
	_shoot(Vector2.ZERO, Vector2.RIGHT, {&"steady": false})
	await _wait(40)
	_check(is_equal_approx(_lost(a), DMG), "steady: off by default (%f)" % _lost(a))
	await _begin()
	a = _enemy(Vector2(100, 0))
	await _wait(2)
	_shoot(Vector2.ZERO, Vector2.RIGHT, {&"steady": true, &"steady_full": 100.0})
	await _wait(40)
	_check(absf(_lost(a) - DMG * S.BONUS) < 0.01, "steady: steady_full 100 gives the full bonus at 100 px (%f)" % _lost(a))


func _cap() -> void:
	await _begin()
	var pool = _pool()
	pool.clear()
	var fired := 0
	for i in MAX_LIVE + 5:
		if pool.fire(_c, Vector2.RIGHT, 1.0, DMG, 10.0, 0, {&"arrow": true, &"bounces": 2}):
			fired += 1
	_check(fired == MAX_LIVE, "cap: the shared cap holds for arrows (%d)" % fired)
	pool.clear()
	_check(pool.fire(_c, Vector2.RIGHT, 1.0, DMG, 10.0, 0), "cap: room again after clear")
	pool.clear()


## 30 seeds: random crowds. An arrow never hits an enemy twice, never more than `hits` enemies, ends on the last,
## and a seed reproduces its result.
func _seeds() -> void:
	for s in SEED_COUNT:
		var first: String = await _run_seed(s)
		var second: String = first
		if s < 3:
			second = await _run_seed(s)
		_check(first == second, "seed %d: reproduces (%s vs %s)" % [s, first, second])


func _run_seed(seed_value: int) -> String:
	await _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var walls: Array[Rect2] = []
	if rng.randi() % 2 == 0:
		walls.append(Rect2(_c + Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250)), Vector2(20, 120)))
	_map(walls, [] as Array[Vector2])
	var enemies := []
	for i in 8:
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 300.0)
		if walls.size() > 0 and walls[0].grow(14.0).has_point(_c + off):
			continue
		enemies.append(_enemy(off))
	await _wait(2)
	var ar = _shoot(Vector2.ZERO, Vector2.from_angle(rng.randf() * TAU))
	for i in 160:
		await physics_frame
	var hit_count := 0
	var sig := ""
	for e in enemies:
		var l: float = _lost(e)
		_check(is_zero_approx(l) or is_equal_approx(l, DMG), "seed %d: an enemy lost %f (once or never)" % [seed_value, l])
		if l > 0.0:
			hit_count += 1
		sig += "%d," % int(l)
	_check(hit_count <= 3, "seed %d: at most 3 enemies hit (%d)" % [seed_value, hit_count])
	_check(ar._hit.size() == hit_count, "seed %d: the hit set matches the damage (%d vs %d)" % [seed_value, ar._hit.size(), hit_count])
	_check(ar._bounces_left >= 0 and ar._bounces_left <= 3, "seed %d: bounces stay in range" % seed_value)
	if hit_count == 3:
		_check(not ar.active, "seed %d: retired on the third enemy" % seed_value)
	return sig

extends SceneTree
## Tidal Wave, Frost Comet and Thorn Nova (spec 1.0, sections 4.1 to 4.3): cadence, numbers per level, aim, walls, targets,
## freeze and vulnerable, seeded picks, bramble, a nearly full projectile pool, nothing while dead.
## Run: godot --headless --path . --script tests/relic_wave_comet_nova.gd

const SEED_COUNT := 30
const MAX_LIVE := 40  # PlayerProjectiles.MAX_LIVE (not named here: it uses an autoload)

var _failed := false
var _main: Node
var _p
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	root.get_node("GameSession").scene_hook = func(_path: String) -> void: pass
	_F = load("res://tests/fixture.gd")
	await _wave()
	await _comet()
	await _nova()
	root.get_node("GameSession").scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## A fresh run with an empty obstacle map; the player stands in the middle.
func _begin() -> void:
	if _main:
		_main.free()
		paused = false
		await process_frame
	_main = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	_p = _F.player()
	_p.caster.set_physics_process(false)  # no auto attacks: only the relic may damage the victims
	var map := ObstacleMap.get_for(_main)
	if map == null:
		map = ObstacleMap.new()
		_main.add_child(map)
	map.setup([] as Array[Rect2], [] as Array[Vector2], map.size, map.bounds)


## A walled-off map: one wall `x` px to the right of the player.
func _wall_at(x: float) -> void:
	var map := ObstacleMap.get_for(_main)
	var rect := Rect2(_p.global_position.x + x, _p.global_position.y - 200.0, 20.0, 400.0)
	map.setup([rect] as Array[Rect2], [] as Array[Vector2], map.size, map.bounds)


func _pool():
	return _main.get_tree().get_first_node_in_group(&"player_projectiles")


func _zones():
	return _main.get_tree().get_first_node_in_group(&"zones")


func _enemy(offset: Vector2, hp := 1000.0):
	return _F.spawn_enemy(_main, "grunt", _p.global_position + offset, hp / 20.0, true)


func _give(id: StringName, level: int):
	var data := RelicRegistry.find(id)
	for i in level:
		_p.relics.add_or_raise(data, false)
	return _p.relics.behavior_of(id)


## The physics frames (counted from now) at which `e` lost health, over `secs` seconds.
func _drops(e, secs: float) -> Array[int]:
	var out: Array[int] = []
	var last: float = e.health.current
	for i in int(secs * 60.0):
		await physics_frame
		if e.health.current < last - 0.001:
			out.append(i)
			last = e.health.current
	return out


func _wave() -> void:
	# Level 1: cadence, damage, knockback along the travel direction.
	await _begin()
	_F.upgrade(_p, "damage")
	_p.player_input.aim_vector = Vector2.RIGHT
	var e = _enemy(Vector2(100, 0))
	var b = _give(&"tidal_wave", 1)
	_check(b.cooldown_fraction() == 0.0, "wave: ready when taken")
	var start: float = e.health.current
	var drops: Array[int] = await _drops(e, 9.0)
	var per: float = b.dmg(10.0)
	_check(drops.size() == 3, "wave L1: three casts in 9 s (got %d)" % drops.size())
	_check(is_equal_approx(start - e.health.current, 3.0 * per), "wave L1: 10 x damage stat per pass (%f vs %f)" % [start - e.health.current, 3.0 * per])
	if drops.size() >= 2:
		_check(absi((drops[1] - drops[0]) - 240) <= 3, "wave L1: cooldown 4 s (%d frames)" % (drops[1] - drops[0]))
	_check(e._knockback.x > 100.0 and absf(e._knockback.y) < 0.01, "wave: knockback along the travel direction (%s)" % e._knockback)

	# Level 2: faster cooldown, wider (an enemy 40 px off the line is hit; at level 1, width 48, it is not a target).
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	var near = _enemy(Vector2(100, 40))
	b = _give(&"tidal_wave", 2)
	drops = await _drops(near, 7.0)
	_check(drops.size() == 3, "wave L2: three casts in 7 s, width 72 (got %d)" % drops.size())
	if drops.size() >= 2:
		_check(absi((drops[1] - drops[0]) - 192) <= 3, "wave L2: cooldown 3.2 s (%d frames)" % (drops[1] - drops[0]))
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	near = _enemy(Vector2(100, 40))
	b = _give(&"tidal_wave", 1)
	drops = await _drops(near, 1.5)
	_check(drops.is_empty() and b.cooldown_fraction() == 0.0, "wave L1: an enemy 40 px off the line is not a target")

	# Direction follows aim_vector.
	await _begin()
	var east = _enemy(Vector2(100, 0))
	var west = _enemy(Vector2(-100, 0))
	var north = _enemy(Vector2(0, -100))
	_p.player_input.aim_vector = Vector2.LEFT
	b = _give(&"tidal_wave", 1)
	await _F.seconds(self, 1.2)
	_check(west.health.current < 1000.0 and east.health.current == 1000.0 and north.health.current == 1000.0, "wave: fired along the aim (left)")
	_check(west._knockback.x < -100.0, "wave: knockback points left")
	_p.player_input.aim_vector = Vector2.UP
	await _F.seconds(self, 4.0)
	_check(north.health.current < 1000.0 and east.health.current == 1000.0, "wave: the next cast follows the new aim (up)")

	# No target: no cast and no cooldown spent; it retries and fires when one arrives.
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	e = _enemy(Vector2(300, 0))
	b = _give(&"tidal_wave", 1)
	await _F.seconds(self, 1.0)
	_check(b.cooldown_fraction() == 0.0 and e.health.current == 1000.0, "wave: no target, no cast, cooldown not spent")
	e.global_position = _p.global_position + Vector2(120, 0)
	await _F.seconds(self, 0.4)
	_check(b.cooldown_fraction() > 0.9 and b._waves.size() == 1, "wave: cast within 0.25 s of a target arriving (%f)" % b.cooldown_fraction())
	await _F.seconds(self, 1.0)
	_check(e.health.current < 1000.0, "wave: the late target is hit")

	# A wall shortens the wave: an enemy behind it is not hit.
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	_wall_at(90.0)
	var before = _enemy(Vector2(40, 0))
	var behind = _enemy(Vector2(125, 0))
	b = _give(&"tidal_wave", 1)
	await _F.seconds(self, 1.2)
	var shortened: float = ObstacleMap.get_for(_main).ray_distance(_p.global_position, Vector2.RIGHT, 140.0, 16.0)
	_check(shortened < 90.0, "wave: the ray is shortened by the wall (%f)" % shortened)
	_check(before.health.current < 1000.0, "wave: hits before the wall")
	_check(behind.health.current == 1000.0, "wave: stops at the wall, nothing behind it is hit")

	# Level 3 returns over the same range and hits once more per pass.
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	e = _enemy(Vector2(100, 0))
	b = _give(&"tidal_wave", 3)
	start = e.health.current
	drops = await _drops(e, 2.5)
	_check(drops.size() == 2, "wave L3: hit on the way out and again on the way back (%d)" % drops.size())
	_check(is_equal_approx(start - e.health.current, 2.0 * b.dmg(14.0)), "wave L3: 14 damage per pass")
	_check(e._knockback.x < 0.0, "wave L3: the return pass pushes toward the player (%s)" % e._knockback)
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	_wall_at(90.0)
	e = _enemy(Vector2(40, 0))
	b = _give(&"tidal_wave", 3)
	await _F.frames(self, 3)
	_check(b._waves.size() == 1 and b._waves[0].length < 90.0, "wave L3: the range is shortened once at the cast")
	start = e.health.current
	drops = await _drops(e, 2.0)
	_check(drops.size() == 1 and start - e.health.current < 2.0 * b.dmg(14.0) + 0.01, "wave L3: one more hit on the return, once per pass (%d)" % drops.size())

	# Raising keeps a running cooldown; dead players cast nothing.
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	e = _enemy(Vector2(100, 0))
	b = _give(&"tidal_wave", 1)
	await _F.seconds(self, 1.0)
	_p.relics.add_or_raise(RelicRegistry.find(&"tidal_wave"), false)
	_check(b.level == 2 and b.cooldown_fraction() > 0.5, "wave: a raise keeps the running cooldown (%f)" % b.cooldown_fraction())
	await _begin()
	_p.player_input.aim_vector = Vector2.RIGHT
	e = _enemy(Vector2(100, 0))
	_p.dead = true
	b = _give(&"tidal_wave", 1)
	await _F.seconds(self, 1.5)
	_check(e.health.current == 1000.0 and b.cooldown_fraction() == 0.0, "wave: nothing while the player is dead")


func _comet() -> void:
	# Level 1: one comet, 12 damage after a 0.5 s telegraph, freeze 1 s, no vulnerable.
	await _begin()
	_F.upgrade(_p, "damage")
	var e = _enemy(Vector2(100, 0))
	var far = _enemy(Vector2(250, 0))
	var b = _give(&"frost_comet", 1)
	b.rng.seed = 1
	_check(b.cooldown_fraction() == 0.0, "comet: ready when taken")
	var start: float = e.health.current
	await _F.seconds(self, 0.3)
	_check(e.health.current == start, "comet: nothing lands during the 0.5 s telegraph")
	await _F.seconds(self, 0.5)
	_check(is_equal_approx(start - e.health.current, b.dmg(12.0)), "comet L1: 12 x damage stat (%f)" % (start - e.health.current))
	_check(is_equal_approx(e.status.freeze_left, 1.0), "comet L1: frozen for 1 s (%f)" % e.status.freeze_left)
	_check(is_equal_approx(e.status.damage_multiplier(), 1.0), "comet L1: no vulnerable")
	_check(far.health.current == 1000.0, "comet: an enemy beyond 200 px is never a target")
	_check(b.cooldown_fraction() > 0.8, "comet: cooldown spent")
	await _F.seconds(self, 5.1)
	_check(e.health.current < start - b.dmg(12.0) - 0.01, "comet L1: lands again after the 5 s cooldown")

	# Level 2: radius 52 (an enemy 45 px from the target is reached; not at radius 40), freeze 1.5.
	await _begin()
	e = _enemy(Vector2(100, 0))
	var side = _enemy(Vector2(150, 0))
	b = _give(&"frost_comet", 2)
	b.rng.seed = 2
	await _F.seconds(self, 0.9)
	_check(e.health.current < 1000.0 and side.health.current < 1000.0, "comet L2: radius 52 reaches an enemy 50 px away")
	_check(is_equal_approx(e.status.freeze_left, 1.5), "comet L2: frozen for 1.5 s")
	await _begin()
	e = _enemy(Vector2(100, 0))
	side = _enemy(Vector2(150, 0))
	b = _give(&"frost_comet", 1)
	b.rng.seed = 2
	await _F.seconds(self, 0.9)
	_check((e.health.current < 1000.0) != (side.health.current < 1000.0), "comet L1: radius 40 does not reach 50 px (one hit only)")

	# Level 3: two distinct comets, 1.5x vulnerable while frozen, not applied to the comet's own hit.
	await _begin()
	var ring: Array = []
	for i in 5:
		ring.append(_enemy(Vector2.from_angle(TAU * i / 5.0) * 100.0))
	b = _give(&"frost_comet", 3)
	b.rng.seed = 3
	await _F.seconds(self, 0.9)
	var hit: Array = ring.filter(func(x) -> bool: return x.health.current < 1000.0)
	_check(hit.size() == 2, "comet L3: two comets hit two different enemies (%d)" % hit.size())
	for x in hit:
		_check(is_equal_approx(1000.0 - x.health.current, b.dmg(16.0)), "comet L3: the comet's own hit is 16 with no 1.5x (%f)" % (1000.0 - x.health.current))
		_check(is_equal_approx(x.status.damage_multiplier(), 1.5) and x.status.freeze_left > 0.0, "comet L3: frozen and vulnerable 1.5")
	await _begin()
	var lone = _enemy(Vector2(100, 0))
	b = _give(&"frost_comet", 3)
	await _F.seconds(self, 0.9)
	_check(is_equal_approx(1000.0 - lone.health.current, b.dmg(16.0)), "comet L3: with one enemy only one comet lands (%f)" % (1000.0 - lone.health.current))

	# No target: no cast, retry, cooldown not spent; fires when one arrives.
	await _begin()
	b = _give(&"frost_comet", 1)
	await _F.seconds(self, 1.0)
	_check(b.cooldown_fraction() == 0.0, "comet: no target, no cast")
	e = _enemy(Vector2(80, 0))
	await _F.seconds(self, 1.0)
	_check(e.health.current < 1000.0 and b.cooldown_fraction() > 0.0, "comet: retried and cast when an enemy arrived")

	# Dead: nothing.
	await _begin()
	e = _enemy(Vector2(80, 0))
	_p.dead = true
	b = _give(&"frost_comet", 1)
	await _F.seconds(self, 1.5)
	_check(e.health.current == 1000.0, "comet: nothing while the player is dead")

	# Seeded picks reproduce, and the pick is not always the same.
	await _begin()
	for i in 8:
		_enemy(Vector2.from_angle(TAU * i / 8.0) * (60.0 + 10.0 * i))
	await _F.frames(self, 2)  # the enemy grid is rebuilt every physics frame
	var zones = _zones()
	b = _give(&"frost_comet", 3)
	b.set_physics_process(false)
	var seen := {}
	var reproducible := true
	var distinct := true
	for s in SEED_COUNT:
		var runs: Array = []
		for r in 2:
			zones.clear()
			b.rng.seed = s
			b._cast()
			runs.append(zones._zones.map(func(z: Dictionary) -> Vector2: return z.a))
		reproducible = reproducible and runs[0] == runs[1]
		distinct = distinct and runs[0].size() == 2 and runs[0][0] != runs[0][1]
		seen[str(runs[0])] = true
	zones.clear()
	_check(reproducible, "comet: the same seed picks the same enemies (%d seeds)" % SEED_COUNT)
	_check(distinct, "comet: two comets never share a target")
	_check(seen.size() > 5, "comet: different seeds pick different enemies (%d variants)" % seen.size())


func _nova() -> void:
	# Level 1: 8 thorns, a slowing bramble of radius 36 for 2 s that does no damage.
	await _begin()
	_F.upgrade(_p, "damage")
	var pool = _pool()
	var zones = _zones()
	var e = _enemy(Vector2(30, 0).rotated(deg_to_rad(22.5)))  # between two thorns
	var b = _give(&"thorn_nova", 1)
	_check(b.cooldown_fraction() == 0.0, "nova: ready when taken")
	await _F.frames(self, 2)
	_check(pool._live == 8, "nova L1: 8 thorns (%d)" % pool._live)
	_check(zones._zones.size() == 1 and zones._zones[0].radius == 36.0 and zones._zones[0].total == 4, "nova L1: bramble radius 36, 4 ticks of 0.5 s")
	_check(zones._zones[0].damage == 0.0 and is_equal_approx(zones._zones[0].extras.slow.factor, 0.6), "nova L1: slow 0.6, no damage")
	_check(e.status.slow_left > 0.0 and is_equal_approx(e.status.slow_factor, 0.6), "nova L1: the bramble slows an enemy inside")
	_check(e.health.current == 1000.0, "nova L1: the bramble does no damage")
	_check(b.cooldown_fraction() > 0.9, "nova: cooldown spent")
	pool.clear()
	zones.clear()
	await _F.seconds(self, 6.1)
	_check(pool._live == 8 and zones._zones.size() == 1, "nova L1: casts again after 6 s (%d thorns)" % pool._live)

	# A thorn hits for 8 x damage stat.
	await _begin()
	_F.upgrade(_p, "damage")
	e = _enemy(Vector2(40, 0))
	b = _give(&"thorn_nova", 1)
	await _F.seconds(self, 0.6)
	_check(is_equal_approx(1000.0 - e.health.current, b.dmg(8.0)), "nova L1: a thorn hits for 8 x damage stat (%f)" % (1000.0 - e.health.current))

	# Level 2: 12 evenly spaced thorns, radius 44, 5 s cooldown.
	await _begin()
	pool = _pool()
	zones = _zones()
	b = _give(&"thorn_nova", 2)
	await _F.frames(self, 2)
	_check(pool._live == 12, "nova L2: 12 thorns (%d)" % pool._live)
	_check(zones._zones[0].radius == 44.0 and zones._zones[0].total == 4, "nova L2: bramble radius 44")
	var angles: Array[float] = []
	for t in pool.get_children():
		if t.active:
			angles.append(fposmod(t._dir.angle(), TAU))
			_check(is_equal_approx(t._damage, b.dmg(10.0)) and t._pierce_left == 0 and is_equal_approx(t._speed, 200.0), "nova L2: thorn damage 10, speed 200, pierce 0")
	angles.sort()
	var even := angles.size() == 12
	for i in angles.size() - 1:
		even = even and absf((angles[i + 1] - angles[i]) - TAU / 12.0) < 0.1
	_check(even, "nova: thorns evenly spaced")
	await _F.seconds(self, 4.6)
	_check(b.cooldown_fraction() > 0.0 and b.cooldown_fraction() < 0.2, "nova L2: cooldown 5 s, nearly ready at 4.6 s (%f)" % b.cooldown_fraction())
	await _F.seconds(self, 0.6)
	_check(b.cooldown_fraction() > 0.8, "nova L2: recast after 5 s (%f)" % b.cooldown_fraction())

	# Level 3: bramble life 4 s, 4 damage per tick scaled by the stat.
	await _begin()
	_F.upgrade(_p, "damage")
	pool = _pool()
	zones = _zones()
	pool._live = MAX_LIVE  # no thorns, so only the bramble can hurt
	e = _enemy(Vector2(20, 0))
	b = _give(&"thorn_nova", 3)
	await _F.frames(self, 2)
	var z: Dictionary = zones._zones[0]
	_check(z.total == 8 and is_equal_approx(z.damage, b.dmg(4.0)) and z.radius == 44.0, "nova L3: 8 ticks (4 s), 4 x damage stat per tick")
	await _F.seconds(self, 1.2)
	var lost: float = 1000.0 - e.health.current
	var ticks := roundi(lost / b.dmg(4.0))
	_check(ticks >= 2 and ticks <= 3 and is_equal_approx(lost, ticks * b.dmg(4.0)), "nova L3: the bramble hurts what it slows (%d ticks)" % ticks)
	_check(e.status.slow_left > 0.0, "nova L3: and slows")
	await _F.seconds(self, 3.4)
	_check(zones._zones.is_empty(), "nova L3: the bramble ends after about 4 s")

	# A nearly full pool: a short volley, the bramble still comes, no error.
	await _begin()
	pool = _pool()
	zones = _zones()
	pool._live = MAX_LIVE - 3
	b = _give(&"thorn_nova", 2)
	await _F.frames(self, 2)
	_check(pool._live == MAX_LIVE, "nova: a nearly full pool gives a short volley (%d)" % pool._live)
	_check(zones._zones.size() == 1, "nova: the bramble is still dropped")
	_check(b.cooldown_fraction() > 0.9, "nova: the cooldown is still spent")

	# Dead: nothing.
	await _begin()
	pool = _pool()
	zones = _zones()
	_p.dead = true
	b = _give(&"thorn_nova", 1)
	await _F.seconds(self, 1.0)
	_check(pool._live == 0 and zones._zones.is_empty() and b.cooldown_fraction() == 0.0, "nova: nothing while the player is dead")

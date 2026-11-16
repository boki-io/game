extends SceneTree
## Archer abilities E and R (spec 1.1, sections 4.3 and 4.4): Ricochet Volley (arrow 1 at the cast and the 6th at 0.5 s,
## each along the aim at its moment, hits and bounces, never busy, stops on death, a full pool skips a shot, the three
## upgrade keys) and Arrow Rain (zone count, radius, the n-gon spacing, the windup and ticks, one zone per enemy, the
## range and arena clamps, no mana, damage scaling). The Archer does not exist yet, so a Knight run has its E and R
## slots set to the Archer's data by hand.
## Run: godot --headless --path . --script tests/archer_ricochet_rain.gd

const RICOCHET := "res://data/abilities/ricochet.tres"
const RAIN := "res://data/abilities/arrow_rain.tres"
const SPREAD: Array[float] = [0.0, -3.0, 3.0, -6.0, 6.0, 0.0, 0.0, -3.0, 3.0, -6.0]  # degrees, by arrow number
const ARENA_INSET := 8.0  # AbilityBehavior.ARENA_INSET (not named here: it uses an autoload)
const MAX_LIVE := 40  # PlayerProjectiles.MAX_LIVE (not named here: it uses an autoload)

var _failed := false
var _main: Node
var _p
var _F: GDScript
var _zones
var _aims: Array[Vector2] = []
var _seen: Dictionary = {}  # arrow -> physics frame it was first seen
var _order: Array = []  # arrows in the order they were first seen


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	root.get_node("GameSession").scene_hook = func(_path: String) -> void: pass
	_F = load("res://tests/fixture.gd")
	await _volley_timing()
	await _volley_busy()
	await _volley_death()
	await _volley_full_pool()
	await _volley_upgrades()
	await _rain_layout()
	await _rain_timing()
	await _rain_one_zone()
	await _rain_clamps()
	await _rain_stats()
	root.get_node("GameSession").scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## A fresh Knight run with E and R replaced by the Archer's, no auto attack, the player in the middle.
func _begin() -> void:
	if _main:
		_main.free()
		paused = false
		await process_frame
	_main = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	_p = _F.player()
	_p.caster.ability_auto = null
	_p.caster.ability_e = load(RICOCHET)
	_p.caster.ability_r = load(RAIN)
	_zones = _main.get_tree().get_first_node_in_group(&"zones")
	_zones.clear()
	_seen.clear()
	_order.clear()
	_aims.clear()


func _pool():
	return _main.get_tree().get_first_node_in_group(&"player_projectiles")


func _active_arrows() -> Array:
	var out: Array = []
	for child in _pool().get_children():
		if child.active:
			out.append(child)
	return out


## Records every arrow in flight that has not been seen yet, with the frame it appeared.
func _scan(frame: int) -> void:
	for a in _active_arrows():
		if not _seen.has(a):
			_seen[a] = frame
			_order.append(a)


func _enemy(pos: Vector2):
	return _F.spawn_enemy(_main, "grunt", pos, 500.0, true)


func _lost(e) -> float:
	return e.health.max_health - e.health.current


# ---------------------------------------------------------------- Ricochet Volley

func _volley_timing() -> void:
	await _begin()
	var rate := Engine.physics_ticks_per_second
	var data = _p.caster.ability_e
	_check(data.param(&"arrows", 0.0) == 6.0 and data.cooldown == 7.0 and data.mana_cost == 0.0 and data.range == 420.0,
		"ricochet data: 6 arrows, cooldown 7, no mana, range 420")
	_aims.append(Vector2.RIGHT)
	_F.cast(_p, &"e", Vector2.RIGHT)
	_scan(0)
	_check(_order.size() == 1, "ricochet: arrow 1 flies at the cast (%d)" % _order.size())
	_check(_p.caster.cooldowns[&"e"] > 6.0, "ricochet: the cooldown starts")
	# Sweep the aim while the volley fires: every arrow follows the aim of its own moment.
	for f in range(1, int(0.8 * rate)):
		var aim := Vector2.from_angle(0.01 * f)
		_aims.append(aim)
		_p.player_input.aim_vector = aim
		await physics_frame
		_scan(f)
		if f == int(0.45 * rate):
			_check(_order.size() == 5, "ricochet: five arrows at 0.45 s (%d)" % _order.size())
	_check(_order.size() == 6, "ricochet: six arrows in all (%d)" % _order.size())
	for k in _order.size():
		var a = _order[k]
		var f: int = _seen[a]
		_check(absi(f - roundi(0.1 * k * rate)) <= 1, "ricochet: arrow %d at 0.1 s steps (frame %d)" % [k + 1, f])
		var rad := deg_to_rad(SPREAD[k])
		var err := minf(absf(a._dir.angle_to(_aims[f].rotated(rad))), absf(a._dir.angle_to(_aims[maxi(f - 1, 0)].rotated(rad))))
		_check(err < 0.002, "ricochet: arrow %d follows the aim of its moment with spread %.0f (err %f)" % [k + 1, SPREAD[k], err])
		_check(a._hits_left == 3 and a._bounces_left == 3, "ricochet: arrow %d has 3 hits and 3 bounces" % [k + 1])
		_check(a._arrow and a._steady and a._pierce_left == 0 and is_equal_approx(a._bounce_reach, 140.0),
			"ricochet: arrow %d is an arrow with steady aim, no pierce, reach 140" % [k + 1])
		_check(is_equal_approx(a._speed, 360.0) and is_equal_approx(a._damage, _p.caster.damage_of(data)),
			"ricochet: arrow %d speed and damage" % [k + 1])
		_check(is_equal_approx(a._range_left + (a.global_position - a._launch).length(), 420.0),
			"ricochet: arrow %d has a range of 420" % [k + 1])


func _volley_busy() -> void:
	await _begin()
	var started: Array = []
	_p.caster.cast_started.connect(func(slot: StringName, _d) -> void: started.append(slot))
	_F.cast(_p, &"e", Vector2.RIGHT)
	await _F.seconds(self, 0.2)
	_check(not _p.caster.is_busy(), "ricochet: the caster is not busy during the volley")
	_p.caster.cooldowns[&"q"] = 0.0
	_F.cast(_p, &"q", Vector2.RIGHT)
	await _F.frames(self, 2)
	_check(started.has(&"q"), "ricochet: Q can be cast in the middle of the volley")
	await _F.seconds(self, 0.5)
	_check(_active_arrows().size() >= 6, "ricochet: the volley carries on after Q")


func _volley_death() -> void:
	await _begin()
	_F.cast(_p, &"e", Vector2.RIGHT)
	await _F.seconds(self, 0.25)
	_scan(0)
	var before := _order.size()
	_check(before >= 3 and before <= 4, "ricochet: three or four arrows by 0.25 s (%d)" % before)
	_p.dead = true
	await _F.seconds(self, 0.6)
	_scan(1)
	_check(_order.size() == before, "ricochet: the volley stops when the player dies (%d, then %d)" % [before, _order.size()])


func _volley_full_pool() -> void:
	await _begin()
	var pool = _pool()
	var origin: Vector2 = _p.global_position
	for i in MAX_LIVE:  # parked arrows: speed 1 and a huge range
		pool.fire(origin + Vector2(0, -100), Vector2.UP, 1.0, 1.0, 100000.0, 0)
	_check(_active_arrows().size() == MAX_LIVE, "pool: filled to the cap")
	_F.cast(_p, &"e", Vector2.RIGHT)
	await _F.seconds(self, 0.25)
	_check(_active_arrows().size() == MAX_LIVE, "pool: shots at the cap are skipped, not queued")
	var freed := 0
	for a in _active_arrows():
		if freed < 6:
			a.retire()
			freed += 1
	await _F.seconds(self, 0.6)
	# Shots 1 to 3 were lost; 4, 5 and 6 (at 0.3, 0.4 and 0.5 s) found room.
	_check(_active_arrows().size() == MAX_LIVE - 6 + 3, "pool: only the later three shots fire (%d live)" % _active_arrows().size())


func _volley_upgrades() -> void:
	await _begin()
	_p.stats.add(&"ricochet.extra", 2.0)
	_p.stats.add(&"ricochet.bounces", 1.0)
	_p.stats.add(&"ricochet.hits", 1.0)
	_F.cast(_p, &"e", Vector2.RIGHT)
	_scan(0)
	await _F.seconds(self, 0.9)
	_scan(1)
	_check(_order.size() == 8, "ricochet.extra +2: eight arrows (%d)" % _order.size())
	var ok := true
	for a in _order:
		ok = ok and a._hits_left == 4 and a._bounces_left == 4
	_check(ok, "ricochet.hits and ricochet.bounces +1: 4 hits and 4 bounces on every arrow")
	_check(absf(_order[6]._dir.angle()) < 0.001 and absf(_order[7]._dir.angle() + deg_to_rad(3.0)) < 0.001,
		"ricochet.extra: arrows 7 and 8 restart the spread pattern")


# ---------------------------------------------------------------- Arrow Rain

func _cast_rain(aim: Vector2 = Vector2.RIGHT) -> Array:
	_zones.clear()
	_p.caster.cooldowns[&"r"] = 0.0
	_F.cast(_p, &"r", aim)
	await _F.frames(self, 1)
	var out: Array = []
	for z in _zones._zones:
		out.append(z)
	return out


func _centroid(list: Array) -> Vector2:
	var sum := Vector2.ZERO
	for z in list:
		sum += z.a
	return sum / list.size()


func _min_gap(list: Array) -> float:
	var gap := INF
	for i in list.size():
		for j in range(i + 1, list.size()):
			gap = minf(gap, list[i].a.distance_to(list[j].a))
	return gap


func _rain_layout() -> void:
	await _begin()
	var data = _p.caster.ability_r
	_check(data.cooldown == 12.0 and data.mana_cost == 0.0 and data.range == 240.0 and data.radius == 34.0
		and data.windup == 0.9 and data.animation == &"attack2", "arrow rain data")
	var origin: Vector2 = _p.global_position
	var list: Array = await _cast_rain()
	_check(list.size() == 3, "rain: three zones (%d)" % list.size())
	_check(list.all(func(z) -> bool: return z.kind == &"field" and is_equal_approx(z.radius, 34.0)), "rain: fields of radius 34")
	_check(is_equal_approx(_min_gap(list), 84.0), "rain: centres 84 px apart (%f)" % _min_gap(list))
	var center := _centroid(list)
	_check(center.distance_to(origin + Vector2(240, 0)) < 0.01, "rain: centred on the aim point at range 240")
	_check(absf(list[0].a.distance_to(center) - 48.5) < 0.01 and list[0].a.x < center.x and absf(list[0].a.y - center.y) < 0.01,
		"rain: the first corner is towards the player, R = 48.5")
	for extra in [1, 2]:  # 4 and 5 zones
		_p.stats.add(&"arrow_rain.extra", 1.0)
		list = await _cast_rain()
		_check(list.size() == 3 + extra, "rain.extra: %d zones (%d)" % [3 + extra, list.size()])
		_check(_min_gap(list) > 2.0 * (34.0 + 6.0) and is_equal_approx(_min_gap(list), 84.0),
			"rain: %d zones are 84 px apart (%f)" % [list.size(), _min_gap(list)])
	_p.stats.add(&"arrow_rain.radius", 30.0)  # radius 64, with 5 zones still on
	for n in [5, 4, 3]:
		list = await _cast_rain()
		_check(list.size() == n and is_equal_approx(list[0].radius, 64.0), "rain.radius: %d zones of radius 64" % n)
		_check(_min_gap(list) > 2.0 * (64.0 + 6.0), "rain: %d zones at radius 64 are %f apart, more than 140" % [n, _min_gap(list)])
		_p.stats.add(&"arrow_rain.extra", -1.0)


func _rain_timing() -> void:
	await _begin()
	var origin: Vector2 = _p.global_position
	var data = _p.caster.ability_r
	# Zone 0 sits at the aim point minus 48.5 px; stand a frozen enemy on it.
	var spot := origin + Vector2(240.0 - 48.5, 0)
	var e = _enemy(spot)
	await _F.frames(self, 2)
	var dmg: float = data.damage * _p.stats.value(&"damage", 1.0)
	_F.cast(_p, &"r", Vector2.RIGHT)
	await _F.seconds(self, 0.85)
	_check(_lost(e) == 0.0, "rain: nothing before the windup ends")
	await _F.seconds(self, 0.12)
	_check(is_equal_approx(_lost(e), dmg), "rain: the first tick at 0.9 s (%f)" % _lost(e))
	await _F.seconds(self, 0.3)
	_check(is_equal_approx(_lost(e), 2.0 * dmg), "rain: the second tick 0.3 s later (%f)" % _lost(e))
	await _F.seconds(self, 1.3)
	_check(is_equal_approx(_lost(e), 5.0 * dmg), "rain: five ticks in all (%f of %f)" % [_lost(e) / dmg, 5.0])
	_check(_zones._zones.is_empty(), "rain: the zones are gone after the last tick")


func _rain_one_zone() -> void:
	await _begin()
	var origin: Vector2 = _p.global_position
	var data = _p.caster.ability_r
	var dmg: float = data.damage * _p.stats.value(&"damage", 1.0)
	var center := origin + Vector2(240, 0)
	var z0 := center + Vector2(-48.5, 0)
	var z1 := center + Vector2(-48.5, 0).rotated(deg_to_rad(120.0))  # the next corner
	# 39 px from zone 0 along the line to zone 1: inside zone 0's reach (40), outside zone 1's (45 away).
	var spot := z0 + (z1 - z0).normalized() * 39.0
	var e = _enemy(spot)
	var mid = _enemy((z0 + z1) / 2.0)  # 42 px from both: in neither
	await _F.frames(self, 2)
	_F.cast(_p, &"r", Vector2.RIGHT)
	await _F.seconds(self, 2.4)
	_check(is_equal_approx(_lost(e), 5.0 * dmg), "rain: an enemy between two zones is hit by one only (%f)" % (_lost(e) / dmg))
	_check(_lost(mid) == 0.0, "rain: an enemy midway between two zones is in neither")


func _rain_clamps() -> void:
	await _begin()
	var origin: Vector2 = _p.global_position
	_p.stats.add(&"arrow_rain.range", -100.0)  # range 140
	var list: Array = await _cast_rain()
	_check(is_equal_approx(_centroid(list).distance_to(origin), 140.0), "rain: the aim point is held to the range (%f)" % _centroid(list).distance_to(origin))
	_p.stats.add(&"arrow_rain.range", 100.0)
	# Next to the right wall the centre is pulled inside the arena inset.
	_p.global_position = Vector2(Arena.world_size.x - 20.0, origin.y)
	list = await _cast_rain()
	var inset := ARENA_INSET + Arena.wall_margin
	_check(_centroid(list).x <= Arena.world_size.x - inset + 0.01 and _centroid(list).x > 1000.0,
		"rain: the centre is clamped to the arena inset (x %f)" % _centroid(list).x)
	# Standing on the target (no aim to follow): still three zones, nothing broken.
	_p.global_position = origin
	_p.stats.add(&"arrow_rain.range", -240.0)
	list = await _cast_rain(Vector2.UP)
	_check(list.size() == 3 and is_equal_approx(_min_gap(list), 84.0), "rain: range 0 still lays three zones")


func _rain_stats() -> void:
	await _begin()
	var data = _p.caster.ability_r
	_p.mana.current = 0.0
	var list: Array = await _cast_rain()
	_check(list.size() == 3 and _p.mana.current < 1.0, "rain: casts with no mana and spends none (only regen: %f)" % _p.mana.current)
	_check(is_equal_approx(list[0].damage, 16.0 * _p.stats.value(&"damage", 1.0)), "rain: damage 16 times the damage stat")
	_p.stats.multiply(&"damage", 1.5)
	list = await _cast_rain()
	_check(is_equal_approx(list[0].damage, 16.0 * _p.stats.value(&"damage", 1.0)) and _p.stats.value(&"damage", 1.0) >= 1.5,
		"rain: damage follows the damage stat (%f)" % list[0].damage)
	_p.stats.add(&"arrow_rain.ticks", 2.0)
	list = await _cast_rain()
	_check(list[0].total == 7 and is_equal_approx(list[0].interval, 0.3), "arrow_rain.ticks +2: seven ticks, 0.3 s apart")

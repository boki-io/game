extends SceneTree
## Storm Orbs and Fire Trail (spec 1.0, sections 4.4 and 4.5): the numbers of each level, damage scaling,
## the belt's own instance, zaps, flame spacing / life / cap, once-per-tick damage, burn, nothing while dead.
## Run: godot --headless --path . --script tests/relic_orbs_trail.gd

var _failed := false
var _main: Node
var _p


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _new_run() -> void:
	if _main:
		_main.queue_free()
		await process_frame
		paused = false
	var F: GDScript = load("res://tests/fixture.gd")
	_main = F.start_run(self, &"wizard")
	await F.frames(self, 3)
	_p = F.player()
	_p.caster.set_physics_process(false)  # no auto bolt
	for c in _p.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"ArcaneFocus":
			c.set_physics_process(false)  # tests switch the 1.25x on by hand
	await F.frames(self, 2)


func _give(id: StringName, level: int) -> Node:
	var data := RelicRegistry.find(id)
	for i in level:
		_p.relics.add_or_raise(data, false)
	return _p.relics.behavior_of(id)


func _enemy(offset: Vector2) -> Node:
	var F: GDScript = load("res://tests/fixture.gd")
	return F.spawn_enemy(_main, "grunt", _p.global_position + offset, 1000.0, true)


func _lost(e: Node) -> float:
	return e.health.max_health - e.health.current


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	await _orbs(F)
	await _trail(F)
	if _failed:
		quit(1)
	else:
		print("PASS")
		quit(0)


func _orbs(F: GDScript) -> void:
	await _new_run()
	var b = _give(&"storm_orbs", 1)
	var belt = b.belt
	_check(belt != null and belt != _p._belt and belt.get_parent() == b, "Storm Orbs has its own belt, a child of the behavior")
	_check(belt.active and belt.orb_count() == 3 and belt._radius == 40.0 and is_equal_approx(belt._turns_per_second, 0.6), "level 1: 3 orbs, radius 40, 0.6 turns/s")
	_check(is_equal_approx(belt._damage, 6.0), "level 1 damage 6")
	_check(belt.color == b.data.color, "the belt takes the relic colour")
	await F.frames(self, 3)
	_p.stats.set_conditional(&"arcane_focus", &"damage", 1.25)
	await F.frames(self, 2)
	_check(is_equal_approx(belt._damage, 7.5), "damage scales 1.25x with Arcane Focus (got %s)" % belt._damage)
	_p.stats.clear_conditional(&"arcane_focus")

	# An orb passing an enemy at its radius hurts it, in whole hits.
	var victim := _enemy(Vector2(40, 0))
	var close := _enemy(Vector2(25, 0))  # inside the ring: never touched at level 1, never zapped
	await F.seconds(self, 4.0)
	var lost := _lost(victim)
	_check(lost > 0.0 and is_equal_approx(fmod(lost, 1.5), 0.0), "an enemy at the ring takes hits of 6 or 7.5 (lost %s)" % lost)
	_check(_lost(close) == 0.0, "no zaps below level 3")
	var follow_x: float = belt.global_position.x
	_p.global_position += Vector2(60, 0)
	await F.frames(self, 2)
	_check(absf(belt.global_position.x - follow_x - 60.0) < 0.5, "the belt follows the player")

	# Level 2 and 3 numbers, and the same belt kept over a level-up.
	b = _give(&"storm_orbs", 1)
	_check(belt.orb_count() == 4 and belt._radius == 52.0 and is_equal_approx(belt._turns_per_second, 0.8) and is_equal_approx(belt._damage, 7.0 * _p.stats.value(&"damage", 1.0)), "level 2: 4 orbs, radius 52, 0.8 turns/s, damage 7")
	_check(b.belt == belt, "a level-up keeps the same belt")
	b = _give(&"storm_orbs", 1)
	_check(belt.orb_count() == 5 and is_equal_approx(belt._damage, 7.0 * _p.stats.value(&"damage", 1.0)), "level 3: 5 orbs")
	victim.queue_free()
	close.queue_free()

	# Per-enemy hit cooldown shared by orbs: three orbs stacked on one enemy hit it once per 0.5 s.
	var stack = load("res://scripts/player/orb_belt.gd").new()
	_main.add_child(stack)
	stack.global_position = Vector2(500, 500)
	var target = F.spawn_enemy(_main, "grunt", Vector2(500, 500), 1000.0, true)
	stack.start(3, 0.0, 0.0, 6.0, 0.0)
	await F.seconds(self, 1.2)
	var hits := roundi(_lost(target) / 6.0)
	_check(hits >= 2 and hits <= 3, "three stacked orbs hit once per 0.5 s (hits %d in 1.2 s)" % hits)
	stack.queue_free()
	target.queue_free()

	# Level 3 zaps: staggered, a zap every 0.4 s, 8 damage; an enemy 25 px away is in range of every orb.
	await _new_run()
	b = _give(&"storm_orbs", 3)
	var z := _enemy(Vector2(25, 0))
	await F.seconds(self, 0.45)
	_check(is_equal_approx(_lost(z), 8.0), "first zap lands after interval / count (lost %s)" % _lost(z))
	await F.seconds(self, 1.65)
	_check(is_equal_approx(_lost(z), 40.0), "5 zaps of 8 in 2.1 s (lost %s)" % _lost(z))
	var far := _enemy(Vector2(400, 0))
	await F.seconds(self, 0.5)
	_check(_lost(far) == 0.0, "no zap beyond range")
	_p.stats.set_conditional(&"arcane_focus", &"damage", 1.25)
	var before := _lost(z)
	await F.seconds(self, 0.85)
	var gained := _lost(z) - before
	_check(gained > 0.0 and is_equal_approx(fmod(gained, 10.0), 0.0), "zaps scale with the damage stat (gained %s)" % gained)
	_p.stats.clear_conditional(&"arcane_focus")

	# Phase Shift's belt is separate: ending the phase does not stop the relic's belt.
	var data = _p.caster.ability_q
	_p.start_phase(0.2, 1.5, 0.0, 0.0, {"count": 5, "radius": data.radius, "turns": 2.0, "damage": data.damage, "duration": 0.5})
	await F.seconds(self, 0.5)
	_check(_p._belt != null and _p._belt != b.belt and _p._belt.active, "Phase Shift has its own belt")
	await F.seconds(self, 0.8)
	_check(not _p._belt.active and b.belt.active, "Phase Shift's belt ending leaves the relic's belt running")

	# Dead: hidden and idle; alive again: back.
	var dead_hp := _lost(z)
	_p.dead = true
	await F.frames(self, 3)
	_check(not b.belt.visible, "the belt is hidden while dead")
	await F.seconds(self, 1.0)
	_check(_lost(z) == dead_hp, "no zaps or hits while dead")
	_p.dead = false
	await F.frames(self, 3)
	_check(b.belt.visible, "the belt is back when alive")


func _trail(F: GDScript) -> void:
	await _new_run()
	var b = _give(&"fire_trail", 1)
	b.flames.clear()
	# Walking 5 px a frame for 24 frames: 120 px, a flame every 12 px.
	for i in 24:
		_p.global_position += Vector2(5, 0)
		await F.frames(self, 1)
	_check(b.flames.size() >= 9 and b.flames.size() <= 10, "120 px walked drops 10 flames (got %d)" % b.flames.size())
	var spaced := true
	for i in range(1, b.flames.size()):
		spaced = spaced and absf(b.flames[i].pos.distance_to(b.flames[i - 1].pos) - 12.0) < 0.01
	_check(spaced, "flames are 12 px apart")
	_check(b.flames[0].pos.y == _p.global_position.y, "flames are dropped at the feet position")
	b.flames.clear()
	await F.seconds(self, 0.3)
	_check(b.flames.is_empty(), "no flames while standing still")

	# Longer steps: interpolated, at most 8; a jump over 120 px drops none.
	b._carry = 0.0
	_p.global_position += Vector2(50, 0)
	await F.frames(self, 1)
	_check(b.flames.size() == 4, "a 50 px step drops 4 interpolated flames (got %d)" % b.flames.size())
	b.flames.clear()
	_p.global_position += Vector2(110, 0)
	await F.frames(self, 1)
	_check(b.flames.size() == 8, "a 110 px step drops at most 8 (got %d)" % b.flames.size())
	b.flames.clear()
	_p.global_position += Vector2(150, 0)
	await F.frames(self, 1)
	_check(b.flames.is_empty(), "a jump over 120 px drops none")

	# Life: level 1 flames last 1.5 s.
	b.flames.clear()
	b.drop_flame(_p.global_position + Vector2(300, 0))
	_check(is_equal_approx(b.flames[0].left, 1.5), "level 1 life 1.5 s")
	await F.seconds(self, 1.3)
	_check(b.flames.size() == 1, "a flame is still there at 1.3 s")
	await F.seconds(self, 0.4)
	_check(b.flames.is_empty(), "a flame is gone after its life")

	# Overlapping flames hit an enemy once per tick: 5 stacked flames, 5 damage (level 1).
	b.flames.clear()
	var e := _enemy(Vector2(0, 100))
	for i in 5:
		b.drop_flame(e.global_position)
	b._tick_left = 0.5
	await F.seconds(self, 0.55)
	_check(is_equal_approx(_lost(e), 5.0), "5 overlapping flames hit once per tick for 5 (lost %s)" % _lost(e))
	_check(e.status.burn_left <= 0.0, "no burn before level 3")
	b.flames.clear()
	b = _give(&"fire_trail", 1)
	_check(is_equal_approx(b.params().radius, 12.0) and is_equal_approx(b.params().life, 2.5), "level 2: radius 12, life 2.5 s")
	b.drop_flame(e.global_position)
	_check(is_equal_approx(b.flames[0].left, 2.5), "level 2 flames last 2.5 s")
	_p.stats.set_conditional(&"arcane_focus", &"damage", 1.25)
	var before := _lost(e)
	b._tick_left = 0.5
	await F.seconds(self, 0.55)
	_check(is_equal_approx(_lost(e) - before, 7.5), "level 2 tick 6 x 1.25 (got %s)" % (_lost(e) - before))
	_p.stats.clear_conditional(&"arcane_focus")

	# Level 3: ignite 4 dps for 3 s on every enemy touched.
	b = _give(&"fire_trail", 1)
	b.flames.clear()
	var e2 := _enemy(Vector2(0, -100))
	b.drop_flame(e2.global_position)
	b._tick_left = 0.5
	await F.seconds(self, 0.55)
	_check(e2.status.burn_left > 2.0 and is_equal_approx(e2.status.burn_dps, 4.0), "level 3 ignites 4 dps for 3 s")
	_check(_lost(e2) >= 6.0, "the level 3 tick still deals 6")

	# The cap: 100 direct drops leave 80 and the oldest went; walking in a circle also stays at 80.
	b.flames.clear()
	for i in 100:
		b.drop_flame(Vector2(1000 + i, 0))
	_check(b.flames.size() == 80 and b.flames[0].pos.x == 1020.0, "cap of 80, oldest dropped")
	b.flames.clear()
	var c: Vector2 = _p.global_position
	for i in 200:
		_p.global_position = c + Vector2.from_angle(i * 8.0 / 60.0) * 60.0
		await F.frames(self, 1)
		_check(b.flames.size() <= 80, "never more than 80 flames")
	_check(b.flames.size() == 80, "walking in a circle reaches the cap (got %d)" % b.flames.size())

	# Dead: nothing dropped, nothing burns, flames hidden.
	b.flames.clear()
	_p.dead = true
	await F.frames(self, 3)
	var hp := _lost(e2)
	for i in 10:
		_p.global_position += Vector2(8, 0)
		await F.frames(self, 1)
	await F.seconds(self, 0.6)
	_check(b.flames.is_empty(), "no flames while dead")
	_check(not b._drawer.visible, "flames are hidden while dead")
	_check(_lost(e2) - hp < 1.0 or e2.status.burn_left > 0.0, "no fire damage while dead")

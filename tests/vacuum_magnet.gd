extends SceneTree
## The vacuum magnet (spec 1.3): its data file and sound, the vacuum on Pickups (every gem and coin flies to the player who
## started it, fast, for 5 s), and the item (drop, lifetime and flash, pickup).
## Run: godot --headless --path . --script tests/vacuum_magnet.gd

const DATA := "res://content/pickups/vacuum_magnet.tres"

var _failed := false
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	_F = load("res://tests/fixture.gd")
	_data()
	await _vacuum()
	await _refresh_and_coop()
	await _pause()
	await _drop()
	await _lifetime()
	await _pickup()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _data() -> void:
	var d: VacuumData = load(DATA)
	_check(d != null, "vacuum_magnet.tres loads as VacuumData")
	if d == null:
		return
	_check(is_equal_approx(d.drop_chance, 0.01), "drop chance 1%%: %s" % d.drop_chance)
	_check(d.effect_time == 5.0 and d.lifetime == 30.0 and d.flash_time == 10.0 and d.flash_hz == 4.0, "times: effect 5 s, lifetime 30 s, flash 10 s at 4 Hz")
	_check(d.pick_distance == 14.0 and d.pull_speed == 1000.0 and d.pull_accel == 3000.0, "pick distance 14 px, pull 1000 px/s at 3000 px/s^2")
	var audio = root.get_node("Audio")
	_check(&"vacuum_pickup" in audio.SOUNDS, "the sound is in Audio.SOUNDS")
	_check(audio._streams.get(&"vacuum_pickup") != null, "the sound file loads")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var pk = scene.get_node("Pickups")
	_check(pk.vacuum_data == d and pk.magnet_scene != null, "main.tscn's Pickups names the data and the magnet scene")
	scene.free()


## A fresh run with the test player moved to `at`, a very high level (40 gems must not level it up: the level-up menu
## pauses the tree and would freeze the items) and no abilities casting.
func _run(at: Vector2) -> Array:
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	var p = _F.player()
	p.caster.set_physics_process(false)
	p.xp.level = 60
	p.global_position = at
	return [main, p, main.get_node("Pickups")]


func _active(pickups: Node) -> Array:
	return pickups.get_children().filter(func(c: Node) -> bool: return c.visible and c.has_method("attract"))


func _gold() -> int:
	return root.get_node("GameSession").run_gold


func _vacuum() -> void:
	var world := Vector2(3200, 1792)
	var r := await _run(Vector2(60, 60))
	var main: Node = r[0]
	var p = r[1]
	var pickups = r[2]
	_check(not pickups.vacuuming() and pickups.vacuum_left == 0.0, "no vacuum at the start")
	var xp_before: int = p.xp.xp
	var gold_before := _gold()
	# 40 gems and 20 coins over the arena; one gem and one coin in the corner opposite the player.
	for i in 38:
		pickups.spawn_gem(Vector2(200 + (i % 10) * 290, 200 + (i / 10) * 400), 1)
	pickups.spawn_gem(world - Vector2(60, 60), 1)
	pickups.spawn_gem(world - Vector2(60, 60) - Vector2(20, 0), 1)
	for i in 19:
		pickups.spawn_coin(Vector2(300 + (i % 10) * 270, 300 + (i / 10) * 700))
	pickups.spawn_coin(world - Vector2(60, 60))
	await _F.seconds(self, 0.5)
	_check(_active(pickups).size() == 60, "no vacuum: the far items stay put (%d active)" % _active(pickups).size())

	pickups.start_vacuum(p)
	_check(pickups.vacuuming() and pickups.vacuum_target == p and is_equal_approx(pickups.vacuum_left, 5.0), "start_vacuum: target and 5 s")
	await _F.seconds(self, 2.0)
	_check(is_equal_approx(pickups.vacuum_left, 3.0) or absf(pickups.vacuum_left - 3.0) < 0.05, "the time counts down (%s)" % pickups.vacuum_left)
	# A gem dropped 2 s in is pulled once its hop ends.
	pickups.spawn_gem(Vector2(1800, 900), 1)
	await _F.seconds(self, 2.5)  # 4.5 s after the start
	_check(_active(pickups).is_empty(), "everything arrived within 4.5 s (%d left)" % _active(pickups).size())
	_check(p.xp.xp - xp_before == 41, "XP rose by the 41 gems' value (%d)" % (p.xp.xp - xp_before))
	_check(p.xp.level == 60, "the test player did not level up")
	_check(_gold() - gold_before == 20, "run gold rose by 20 (%d)" % (_gold() - gold_before))

	# After the vacuum a far gem stays; one still flying when it ends keeps coming, slowly.
	await _F.seconds(self, 1.0)
	_check(not pickups.vacuuming(), "the vacuum has ended after 5 s")
	pickups.spawn_gem(Vector2(2000, 1000), 1)
	await _F.seconds(self, 1.0)
	var idle := _active(pickups)
	_check(idle.size() == 1 and idle[0].global_position.distance_to(Vector2(2000, 1000)) < 40.0, "after the vacuum a far gem stays where it fell")
	pickups.spawn_gem(Vector2(1900, 900), 1)  # restart: a gem mid-flight when the vacuum ends
	pickups.start_vacuum(p)
	await _F.seconds(self, 4.6)
	var flying := _active(pickups).filter(func(c: Node) -> bool: return c.target != null)
	_check(flying.size() <= 2, "most items are in by 4.6 s")
	await _F.seconds(self, 0.6)  # the vacuum ended
	for c in _active(pickups):
		_check(c._speed <= 320.0 + 0.01, "an item's speed is capped at 320 after the vacuum (%s)" % c._speed)
	await _F.seconds(self, 6.0)
	_check(_active(pickups).filter(func(c: Node) -> bool: return c.target != null).is_empty(), "items the vacuum caught are all delivered")
	main.queue_free()
	await process_frame
	paused = false


func _second_player(main: Node, like) -> Node:
	var p2: Node = load("res://scenes/player.tscn").instantiate()
	p2.character = like.character
	p2.attribute_levels = like.attribute_levels
	p2.position = Vector2(2900, 1700)
	main.get_node("World/Players").add_child(p2)
	await _F.frames(self, 2)
	p2.caster.set_physics_process(false)
	p2.xp.level = 60
	return p2


func _refresh_and_coop() -> void:
	var r := await _run(Vector2(60, 60))
	var main: Node = r[0]
	var p = r[1]
	var pickups = r[2]
	var p2 = await _second_player(main, p)

	# start_vacuum ignores null and dead players.
	pickups.start_vacuum(null)
	_check(not pickups.vacuuming(), "start_vacuum(null) does nothing")
	p2.dead = true
	pickups.start_vacuum(p2)
	_check(not pickups.vacuuming(), "start_vacuum(dead player) does nothing")
	p2.dead = false

	# A second start refreshes the time and hands everything to the second player.
	pickups.start_vacuum(p)
	await _F.seconds(self, 3.0)
	pickups.start_vacuum(p2)
	_check(is_equal_approx(pickups.vacuum_left, 5.0) and pickups.vacuum_target == p2, "a second start refreshes to 5 s and retargets")
	var xp1: int = p.xp.xp
	var xp2: int = p2.xp.xp
	for i in 5:
		pickups.spawn_gem(Vector2(1500 + i * 40, 900), 1)
	await _F.seconds(self, 3.0)
	_check(_active(pickups).is_empty(), "the gems reached someone")
	_check(p2.xp.xp - xp2 == 5 and p.xp.xp == xp1, "the second player got the XP, the first nothing (%d, %d)" % [p2.xp.xp - xp2, p.xp.xp - xp1])

	# The target dies: the vacuum ends and the items let go.
	pickups.spawn_gem(Vector2(1600, 800), 1)
	await _F.seconds(self, 0.3)
	p2.dead = true
	await _F.frames(self, 2)
	_check(not pickups.vacuuming() and pickups.vacuum_left == 0.0, "the vacuum ends when its target dies")
	for c in _active(pickups):
		_check(c.target == null, "an item drops its target when the player dies")
	p2.dead = false

	# The target is freed mid-vacuum: nothing errors, the vacuum ends.
	pickups.start_vacuum(p2)
	pickups.spawn_gem(Vector2(1600, 800), 1)
	await _F.seconds(self, 0.4)
	p2.queue_free()
	await _F.frames(self, 3)
	_check(not pickups.vacuuming(), "the vacuum ends when its target is freed")
	for c in _active(pickups):
		_check(c.target == null, "an item drops a freed target")
	main.queue_free()
	await process_frame
	paused = false


func _pause() -> void:
	var r := await _run(Vector2(60, 60))
	var main: Node = r[0]
	var p = r[1]
	var pickups = r[2]
	pickups.start_vacuum(p)
	await _F.seconds(self, 1.0)
	var left: float = pickups.vacuum_left
	paused = true
	await _F.seconds(self, 0.5)
	_check(is_equal_approx(pickups.vacuum_left, left), "the vacuum time does not run while the tree is paused (%s -> %s)" % [left, pickups.vacuum_left])
	paused = false
	main.queue_free()
	await process_frame


func _magnets(pickups: Node) -> Array:
	var script: Script = load("res://scripts/systems/vacuum_magnet.gd")
	return pickups.get_children().filter(func(c: Node) -> bool: return c.get_script() == script and c.active)


## A kill through the director, set up as tests/gold.gd does it (the director's pools need the type).
func _kill(main: Node, at: Vector2, data: Resource = null) -> void:
	var e = _F.spawn_enemy(main, "grunt", at, 1.0, true)
	if data != null:
		main.spawn_director._pools[data] = []
		main.spawn_director.alive_by_type[data.id] += 1
		e.data = data
	main.spawn_director.alive += 1
	main.spawn_director._on_enemy_died(e)


func _drop() -> void:
	var r := await _run(Vector2(60, 60))
	var main: Node = r[0]
	var pickups = r[2]
	var d: VacuumData = pickups.vacuum_data.duplicate()  # never edit the cached resource
	d.drop_chance = 1.0
	pickups.vacuum_data = d
	main.spawn_director.apply_stage(load("res://scripts/stages/stage_data.gd").new())

	_kill(main, Vector2(1000, 800))
	await _F.seconds(self, 0.4)
	_check(_magnets(pickups).size() == 1 and pickups.magnet_on_map(), "a kill at 100%% drops one magnet")
	var m = _magnets(pickups)[0]
	_check(m.global_position.distance_to(Vector2(1000, 800)) < 25.0, "it hops out near the kill (%s)" % m.global_position)
	var spot: Vector2 = m.global_position
	_kill(main, Vector2(1500, 800))
	await _F.frames(self, 2)
	_check(_magnets(pickups).size() == 1 and m.global_position == spot, "a second kill leaves still one magnet, in place")
	_check(not m.has_method("attract"), "the magnet has no attract(): the pickup radius never pulls it")

	pickups.release_magnet()
	d.drop_chance = 0.0
	_kill(main, Vector2(1000, 800))
	_check(_magnets(pickups).is_empty(), "at 0%% no drop")
	d.drop_chance = 1.0
	var no_xp = load("res://content/enemies/grunt.tres").duplicate()
	no_xp.xp_drop = 0
	_kill(main, Vector2(1000, 800), no_xp)
	_check(_magnets(pickups).is_empty(), "a mob with xp_drop 0 never drops it")
	pickups.start_vacuum(_F.player())
	_kill(main, Vector2(1000, 800))
	_check(_magnets(pickups).is_empty(), "no drop while the vacuum runs")
	pickups.vacuum_target = null

	d.drop_chance = 0.01
	var hits := 0
	for i in 2000:
		if pickups.roll_magnet(Vector2(1000, 800)):
			hits += 1
			pickups.release_magnet()
	_check(hits >= 5 and hits <= 40, "2000 rolls at 1%% gave %d drops (expected about 20)" % hits)
	main.queue_free()
	await process_frame
	paused = false


func _lifetime() -> void:
	var r := await _run(Vector2(60, 60))
	var main: Node = r[0]
	var pickups = r[2]
	pickups.place_magnet(Vector2(1500, 900))
	var m = pickups._magnet
	await _F.seconds(self, 0.4)
	_check(m.active and not m.is_flashing(), "a new magnet is active and not flashing")
	m._age = 19.9
	await _F.frames(self, 1)
	_check(not m.is_flashing(), "not flashing at 19.9 s")
	m._age = 20.1
	var seen := {}
	for i in 40:
		await _F.frames(self, 1)
		seen[snappedf(m.modulate.a, 0.01)] = true
	_check(m.is_flashing() and seen.has(1.0) and seen.has(0.25), "flashing at 20.1 s: it blinks between 1.0 and 0.25 (%s)" % [seen.keys()])
	m._age = 29.95
	await _F.frames(self, 4)
	_check(not m.active and not m.visible and not pickups.magnet_on_map(), "gone at 30 s")

	# Paused: its age does not move.
	pickups.place_magnet(Vector2(1500, 900))
	await _F.seconds(self, 0.3)
	var age: float = m._age
	paused = true
	await _F.seconds(self, 0.4)
	_check(is_equal_approx(m._age, age), "the age does not advance while the tree is paused")
	paused = false
	main.queue_free()
	await process_frame


func _pickup() -> void:
	var r := await _run(Vector2(60, 60))
	var main: Node = r[0]
	var p = r[1]
	var pickups = r[2]
	var fx: Node = main.get_tree().get_first_node_in_group(&"effects")
	pickups.place_magnet(Vector2(800, 600))
	var m = pickups._magnet
	await _F.seconds(self, 0.5)
	p.global_position = m.global_position + Vector2(30, 6)  # near, but not on it
	await _F.seconds(self, 0.2)
	_check(m.active and not pickups.vacuuming(), "30 px away: not taken")
	fx.clear()
	p.global_position = m.global_position + Vector2(8, 6)
	await _F.frames(self, 2)
	_check(not m.active and pickups.vacuuming() and pickups.vacuum_target == p, "within 14 px it is taken and the vacuum starts")
	_check(is_equal_approx(pickups.vacuum_left, 5.0) or pickups.vacuum_left > 4.95, "5 s of vacuum (%s)" % pickups.vacuum_left)
	_check(fx._bits.size() == 24, "a burst of 24 bits marks the pickup (%d)" % fx._bits.size())
	pickups.vacuum_target = null

	# Not during its hop.
	pickups.place_magnet(p.global_position + Vector2(0, 6))
	await _F.frames(self, 2)
	_check(pickups.magnet_on_map() and not pickups.vacuuming(), "it cannot be taken during its hop")
	await _F.seconds(self, 0.6)  # the hop carried it up to 14 px away, so step onto it
	if pickups.magnet_on_map():
		p.global_position = pickups._magnet.global_position + Vector2(0, 6)
		await _F.frames(self, 2)
	_check(not pickups.magnet_on_map() and pickups.vacuuming(), "once the hop is over it is taken")
	pickups.vacuum_target = null

	# A living and a dead player on it: the living one takes it; two dead ones, nobody.
	var p2 = await _second_player(main, p)
	pickups.place_magnet(Vector2(2000, 1000))
	await _F.seconds(self, 0.5)
	p2.global_position = pickups._magnet.global_position + Vector2(0, 6)
	p2.dead = true
	p.global_position = pickups._magnet.global_position + Vector2(10, 6)
	await _F.frames(self, 2)
	_check(pickups.vacuum_target == p, "the living player took it, not the dead one on top of it")
	pickups.vacuum_target = null
	p.dead = true  # p2 is dead too: nobody is left to take a magnet lying between them
	pickups.place_magnet(Vector2(2000, 1000))
	await _F.seconds(self, 0.7)
	_check(pickups.magnet_on_map() and not pickups.vacuuming(), "with only dead players nothing happens")
	p.dead = false
	p2.dead = false
	main.queue_free()
	await process_frame
	paused = false

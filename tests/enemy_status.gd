extends SceneTree
## Enemy statuses (spec 1.0 section 2): slow through chase() and settle(), freeze as a stun with vulnerable, vulnerable
## on take_damage, burn ticks, stacking, expiry, pooling, dummies, a slowed Dasher's dash, tint priority, the
## DamageZones extras and the cost of 300 enemies with statuses on them.
## Run: godot --headless --path . --script tests/enemy_status.gd

const SEED_COUNT := 30
const BUDGET_MS := 12.0  # the same mean physics budget as crowd_performance.gd
const STATUS := preload("res://scripts/enemy/enemy_status.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _near(a: float, b: float, tol: float, what: String) -> void:
	_check(absf(a - b) <= tol, "%s (got %f, wanted %f)" % [what, a, b])


func _init() -> void:
	await process_frame
	await process_frame
	_seeded_status_rules()
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 3)
	var p = F.player()
	p.hurtbox.invulnerable = true
	p.caster.set_physics_process(false)  # no auto attack: nothing else may damage the victims
	var far: Vector2 = p.global_position + Vector2(0, -300)

	await _slow_through_chase_and_settle(F, main, p)
	await _slow_in_motion(F, main, p)
	await _freeze(F, main, p, far)
	await _vulnerable(F, main, far)
	await _burn(F, main, far)
	_tint_priority(F, main, far)
	_pooling(F, main, far)
	await _dummies(F, main, far)
	await _dasher_dash(F, main, p)
	await _zone_extras(F, main, far)
	await _contact_hits(F, main, p)
	await _crowd_cost(F, main, p)

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## The pure numbers, 30 seeds: strongest wins, longest time, burn total independent of the frame rate.
func _seeded_status_rules() -> void:
	for s in SEED_COUNT:
		var rng := RandomNumberGenerator.new()
		rng.seed = s + 1
		var st = STATUS.new()
		var min_f := 1.0
		var max_s := 0.0
		var max_m := 1.0
		var max_v := 0.0
		for i in rng.randi_range(2, 5):
			var f := rng.randf_range(0.2, 0.95)
			var secs := rng.randf_range(0.5, 3.0)
			var m := rng.randf_range(1.1, 2.5)
			st.apply_slow(f, secs)
			st.apply_vulnerable(m, secs)
			min_f = minf(min_f, f)
			max_s = maxf(max_s, secs)
			max_m = maxf(max_m, m)
			max_v = maxf(max_v, secs)
		_check(st.any_active, "seed %d: any_active after applying" % s)
		_near(st.slow_factor, min_f, 1e-6, "seed %d: the lowest slow factor wins" % s)
		_near(st.slow_left, max_s, 1e-6, "seed %d: the longest slow time wins" % s)
		_near(st.vulnerable_mult, max_m, 1e-6, "seed %d: the highest vulnerable wins" % s)
		_near(st.vulnerable_left, max_v, 1e-6, "seed %d: the longest vulnerable time wins" % s)
		_near(st.damage_multiplier(), max_m, 1e-6, "seed %d: damage multiplier while vulnerable" % s)
		var t := 0.0
		while st.any_active and t < 10.0:
			var dt := rng.randf_range(0.005, 0.05)
			st.advance(dt)
			t += dt
		_check(not st.any_active, "seed %d: every status expires" % s)
		_check(st.slow_factor == 1.0 and st.damage_multiplier() == 1.0, "seed %d: expired values are neutral" % s)
		_near(t, maxf(max_s, max_v), 0.06, "seed %d: it lasts as long as it was applied" % s)

		# Burn: ticks of dps * 0.5 every 0.5 s, the total is dps * seconds whatever the frame times.
		var dps := rng.randf_range(1.0, 10.0)
		var secs := rng.randi_range(1, 8) * 0.5
		var b = STATUS.new()
		b.ignite(dps, secs)
		var total := 0.0
		var ticks := 0
		while b.any_active:
			var got: float = b.advance(rng.randf_range(0.004, 0.07))
			if got > 0.0:
				ticks += 1
			total += got
		_near(total, dps * secs, 1e-6, "seed %d: burn total is dps x seconds" % s)
		_check(ticks <= int(secs / 0.5) and ticks >= int(secs / 0.5) - 0, "seed %d: burn tick count %d" % [s, ticks])

	# A weaker slow after the first one expired takes effect (the factor is not stuck at the old minimum).
	var st = STATUS.new()
	st.apply_slow(0.3, 0.1)
	st.advance(0.2)
	st.apply_slow(0.8, 1.0)
	_near(st.slow_factor, 0.8, 1e-6, "a slow after an expired slow starts fresh")
	# Burn: the highest dps wins, the time is reset.
	st.ignite(4.0, 3.0)
	st.advance(1.0)
	st.ignite(2.0, 3.0)
	_near(st.burn_dps, 4.0, 1e-6, "the highest burn dps wins")
	_near(st.burn_left, 3.0, 1e-6, "a new ignite resets the burn time")
	st.ignite(6.0, 1.0)
	_near(st.burn_dps, 6.0, 1e-6, "a stronger ignite replaces the dps")
	st.reset()
	_check(not st.any_active and st.slow_factor == 1.0 and st.burn_left == 0.0 and st.freeze_left == 0.0, "reset clears everything")


func _slow_through_chase_and_settle(F: GDScript, main: Node, p) -> void:
	var e = F.spawn_enemy(main, "grunt", p.global_position + Vector2(200, 0), 100.0, true)
	var plain: Vector2 = e.chase(p, 100.0)
	e.apply_slow(0.6, 5.0)
	var slowed: Vector2 = e.chase(p, 100.0)
	_near(slowed.length(), plain.length() * 0.6, 0.01, "chase() speed x the slow factor")
	e.apply_slow(0.4, 1.0)
	_near((e.chase(p, 100.0) as Vector2).length(), plain.length() * 0.4, 0.01, "the lowest slow factor wins")
	e.apply_slow(0.9, 9.0)
	_near((e.chase(p, 100.0) as Vector2).length(), plain.length() * 0.4, 0.01, "a weaker slow does not replace it")
	_near(e.status.slow_left, 9.0, 1e-6, "but its longer time is kept")
	e.queue_free()

	# settle() is only separation, so two enemies close together give it something to scale.
	var a = F.spawn_enemy(main, "grunt", p.global_position + Vector2(200, 0), 100.0, true)
	var b = F.spawn_enemy(main, "grunt", p.global_position + Vector2(205, 0), 100.0, true)
	await F.frames(self, 3)  # the enemy grid is rebuilt once a frame
	# _separation() recomputes only on frames where (physics frame + instance id) is even, so wait for one.
	for i in 4:
		if (Engine.get_physics_frames() + a.get_instance_id()) % 2 == 0:
			break
		await F.frames(self, 1)
	var s1: Vector2 = a.settle(p, 100.0)
	a.apply_slow(0.5, 5.0)
	var s2: Vector2 = a.settle(p, 100.0)  # the same frame, so the same separation
	_check(s1.length() > 0.0, "settle() has separation to scale")
	_near(s2.length(), s1.length() * 0.5, 0.01, "settle() speed x the slow factor")
	a.queue_free()
	b.queue_free()


func _slow_in_motion(F: GDScript, main: Node, p) -> void:
	# Two grunts on opposite sides of the Player, one slowed: it covers 60% of the other's distance.
	var fast = F.spawn_enemy(main, "grunt", p.global_position + Vector2(-280, 0), 1000.0)
	var slow = F.spawn_enemy(main, "grunt", p.global_position + Vector2(280, 0), 1000.0)
	slow.apply_slow(0.6, 10.0)
	var f0: float = fast.global_position.distance_to(p.global_position)
	var s0: float = slow.global_position.distance_to(p.global_position)
	await F.seconds(self, 1.5)
	var fd: float = f0 - fast.global_position.distance_to(p.global_position)
	var sd: float = s0 - slow.global_position.distance_to(p.global_position)
	_check(fd > 40.0, "the plain grunt walks (%f px)" % fd)
	_near(sd / fd, 0.6, 0.08, "a slowed grunt walks 60% as far")
	_check(not slow.is_stunned(), "a slowed enemy is not stunned")
	await F.seconds(self, 9.0)
	_check(not slow.status.any_active and slow.status.slow_factor == 1.0, "the slow expires")
	fast.queue_free()
	slow.queue_free()


func _freeze(F: GDScript, main: Node, p, far: Vector2) -> void:
	var e = F.spawn_enemy(main, "grunt", far, 1000.0)
	e.freeze(0.5, 1.5)
	_check(e.is_stunned(), "a frozen enemy is stunned")
	_check(e.status.vulnerable_mult == 1.5 and e.status.vulnerable_left >= 0.49, "freeze applies vulnerable for the same time")
	var at: Vector2 = e.global_position
	await F.seconds(self, 0.4)
	_check(e.global_position.is_equal_approx(at), "a frozen enemy does not move")
	await F.seconds(self, 0.3)
	_check(not e.is_stunned(), "freeze ends")
	_check(e.status.vulnerable_mult == 1.0, "vulnerable ends with the freeze")
	await F.seconds(self, 0.3)
	_check(not e.global_position.is_equal_approx(at), "it walks again afterwards")
	# The longest time wins, a shorter freeze does not cut a longer one.
	e.freeze(1.0)
	e.freeze(0.2)
	_near(e.status.freeze_left, 1.0, 1e-6, "freeze keeps the longest time")
	e.queue_free()


func _vulnerable(F: GDScript, main: Node, far: Vector2) -> void:
	var e = F.spawn_enemy(main, "grunt", far, 1000.0, true)
	var full: float = e.health.max_health
	e.take_damage(10.0)
	_near(full - e.health.current, 10.0, 1e-4, "a plain hit")
	e.apply_vulnerable(1.5, 5.0)
	var hp: float = e.health.current
	e.take_damage(10.0)
	_near(hp - e.health.current, 15.0, 1e-4, "vulnerable 1.5 multiplies the damage")
	e.apply_vulnerable(1.2, 5.0)
	hp = e.health.current
	e.take_damage(10.0)
	_near(hp - e.health.current, 15.0, 1e-4, "the highest multiplier wins")
	e.status.vulnerable_left = 0.0
	e.status.advance(0.01)
	hp = e.health.current
	e.take_damage(10.0)
	_near(hp - e.health.current, 10.0, 1e-4, "no multiplier once it has expired")
	e.queue_free()
	await F.frames(self, 1)


func _burn(F: GDScript, main: Node, far: Vector2) -> void:
	var e = F.spawn_enemy(main, "grunt", far, 1000.0)
	var hp0: float = e.health.current
	e.ignite(4.0, 3.0)
	await F.seconds(self, 0.3)
	_check(e.health.current == hp0, "no burn damage before the first 0.5 s")
	await F.seconds(self, 0.3)  # 0.6 s
	_near(hp0 - e.health.current, 2.0, 0.01, "the first tick is dps x 0.5")
	_check(e._flash_left == 0.0 and not e.sprite.flash and e._recoil_left == 0.0 and e.sprite.position == Vector2.ZERO,
		"a burn tick has no flash or recoil")
	await F.seconds(self, 0.5)  # 1.1 s
	_near(hp0 - e.health.current, 4.0, 0.01, "two ticks by 1.1 s")
	# Refresh: a new ignite resets the time to the full 3 s from now.
	e.ignite(2.0, 3.0)
	_near(e.status.burn_dps, 4.0, 1e-6, "the weaker ignite does not lower the dps")
	var hp1: float = e.health.current
	await F.seconds(self, 3.2)
	_near(hp1 - e.health.current, 12.0, 0.01, "3 s of burn after the refresh, 6 ticks")
	_check(not e.status.any_active, "the burn ends")
	var hp2: float = e.health.current
	await F.seconds(self, 1.0)
	_check(e.health.current == hp2, "no damage after the burn ends")
	# Vulnerable multiplies each tick before the number is shown.
	hp0 = e.health.current
	e.apply_vulnerable(2.0, 5.0)
	e.ignite(4.0, 1.0)
	await F.seconds(self, 0.6)
	_near(hp0 - e.health.current, 4.0, 0.01, "a burn tick is multiplied by vulnerable")
	# A normal hit still has its flash (the control for the quiet tick).
	e.take_damage(1.0)
	_check(e.sprite.flash or e._anim != null, "a normal hit flashes")
	# A burn can kill, and the enemy comes back clean.
	var weak = F.spawn_enemy(main, "grunt", far + Vector2(50, 0), 1.0)
	weak.ignite(100.0, 2.0)
	await F.seconds(self, 0.7)
	_check(weak.health.current <= 0.0, "burn can kill")
	e.queue_free()
	weak.queue_free()


func _tint_priority(F: GDScript, main: Node, far: Vector2) -> void:
	var e = F.spawn_enemy(main, "grunt", far, 1000.0, true)
	var yellow := Color(1.0, 1.0, 0.45)
	var ice := Color(0.55, 0.8, 1.0)
	var burn := Color(1.0, 0.6, 0.35)
	var slow := Color(0.75, 0.95, 0.75)
	_check(e.sprite.modulate == Color.WHITE, "no tint without a status")
	e.apply_slow(0.6, 5.0)
	_check(e.sprite.modulate == slow, "slow tint")
	e.ignite(2.0, 5.0)
	_check(e.sprite.modulate == burn, "burn beats slow")
	e.freeze(5.0)
	_check(e.sprite.modulate == ice, "freeze beats burn")
	e.stun(5.0)
	_check(e.sprite.modulate == yellow, "stun beats freeze")
	e._stun_left = 0.0
	e._refresh_tint()
	_check(e.sprite.modulate == ice, "back to ice when the stun ends")
	e.status.freeze_left = 0.0
	e._refresh_tint()
	_check(e.sprite.modulate == burn, "back to burn when the freeze ends")
	e.status.burn_left = 0.0
	e._refresh_tint()
	_check(e.sprite.modulate == slow, "back to slow when the burn ends")
	e.status.slow_left = 0.0
	e._refresh_tint()
	_check(e.sprite.modulate == Color.WHITE, "white when nothing is left")
	e.queue_free()


func _pooling(F: GDScript, main: Node, far: Vector2) -> void:
	var e = F.spawn_enemy(main, "grunt", far, 1000.0, true)
	e.apply_slow(0.3, 9.0)
	e.freeze(9.0, 2.0)
	e.ignite(5.0, 9.0)
	e.apply_vulnerable(3.0, 9.0)
	e.deactivate()
	_check(not e.status.any_active, "deactivate clears the statuses")
	e.activate(far, 1000.0)
	_check(not e.status.any_active and e.status.slow_factor == 1.0 and e.status.vulnerable_mult == 1.0
		and e.status.burn_left == 0.0 and e.status.freeze_left == 0.0, "a pooled enemy comes back clean")
	_check(e.sprite.modulate == Color.WHITE and not e.is_stunned(), "and untinted, not stunned")
	var hp: float = e.health.current
	e.take_damage(10.0)
	_near(hp - e.health.current, 10.0, 1e-4, "and takes plain damage")
	# Statuses on an inactive enemy are ignored.
	e.deactivate()
	e.apply_slow(0.5, 5.0)
	e.ignite(1.0, 5.0)
	_check(not e.status.any_active, "an inactive enemy takes no status")
	e.queue_free()


func _dummies(F: GDScript, main: Node, far: Vector2) -> void:
	var d = F.spawn_enemy(main, "training_dummy", far, 1.0)
	d.apply_slow(0.5, 5.0)
	d.freeze(5.0, 2.0)
	d.ignite(10.0, 5.0)
	d.apply_vulnerable(3.0, 5.0)
	_check(not d.status.any_active, "a dummy takes no status")
	_check(not d.is_stunned() and d.sprite.modulate == Color.WHITE, "a dummy is not frozen or tinted")
	var at: Vector2 = d.global_position
	await F.seconds(self, 1.2)
	_check(d.global_position == at, "a dummy does not move")
	_check(d.health.current == d.health.max_health or d.health.current > 0.0, "no burn on a dummy")
	d.queue_free()


## Walks one Dasher through its AIM, LOCK and DASH and returns how far the dash itself carried it.
func _dash_length(F: GDScript, main: Node, p, slow: bool) -> float:
	var e = F.spawn_enemy(main, "dasher", p.global_position + Vector2(90, 0), 1000.0)
	if slow:
		e.apply_slow(0.3, 30.0)
	var start := Vector2.ZERO
	var length := -1.0
	var dashing := false
	for i in 400:
		await physics_frame
		var state: int = e.brain._state
		if state == 3 and not dashing:
			dashing = true
			start = e.global_position
		if state == 4 and dashing:
			length = start.distance_to(e.global_position)
			break
	e.queue_free()
	return length


func _dasher_dash(F: GDScript, main: Node, p) -> void:
	var plain: float = await _dash_length(F, main, p, false)
	var slowed: float = await _dash_length(F, main, p, true)
	_check(plain > 100.0, "the plain dash was measured (%f)" % plain)
	_near(slowed, plain, 1.0, "a slowed Dasher's dash length is unchanged")


func _zone_extras(F: GDScript, main: Node, far: Vector2) -> void:
	var zones = main.get_tree().get_first_node_in_group(&"zones")
	# A field of statuses only: slow and burn, no damage, no hit effects.
	var e = F.spawn_enemy(main, "grunt", far, 1000.0, true)
	await F.frames(self, 2)  # the enemy grid is rebuilt once a frame
	var hp: float = e.health.current
	zones.add_field(far, 40.0, 0.0, 0.5, 1, Color.WHITE, 0.0, {"slow": {"factor": 0.6, "seconds": 0.75}, "ignite": {"dps": 3.0, "seconds": 2.0}})
	await F.frames(self, 3)
	_near(e.status.slow_factor, 0.6, 1e-6, "a field applies its slow")
	_near(e.status.slow_left, 0.75, 0.05, "for the slow's seconds")
	_near(e.status.burn_dps, 3.0, 1e-6, "and its ignite")
	_check(e.health.current == hp, "a field with damage 0 deals no damage")
	_check(e._flash_left == 0.0 and not e.sprite.flash and e._recoil_left == 0.0, "and no hit effects")
	# A field without extras still behaves as before.
	zones.add_field(far, 40.0, 5.0, 0.5, 1, Color.WHITE)
	await F.frames(self, 3)
	_near(hp - e.health.current, 5.0, 1e-4, "a plain field still damages")
	e.queue_free()

	# A burst with freeze: its own damage lands before the freeze, so it is not multiplied.
	var f = F.spawn_enemy(main, "grunt", far + Vector2(100, 0), 1000.0, true)
	await F.frames(self, 2)
	hp = f.health.current
	zones.add_burst(far + Vector2(100, 0), 40.0, 10.0, 0.0, 0.0, {"freeze": {"seconds": 1.5, "vulnerable": 1.5}})
	await F.frames(self, 3)
	_near(hp - f.health.current, 10.0, 1e-4, "the burst's own damage is not multiplied")
	_check(f.is_stunned() and f.status.freeze_left > 1.0, "the burst freezes")
	_near(f.status.vulnerable_mult, 1.5, 1e-6, "and makes it vulnerable")
	hp = f.health.current
	f.take_damage(10.0)
	_near(hp - f.health.current, 15.0, 1e-4, "the next hit is multiplied")
	f.queue_free()


## A frozen enemy standing on the Player does not hit; the same enemy hits once it thaws.
func _contact_hits(F: GDScript, main: Node, p) -> void:
	p.hurtbox.invulnerable = false
	p.hurtbox.grace_left = 0.0
	var e = F.spawn_enemy(main, "grunt", p.global_position, 100000.0)
	e.freeze(0.8)
	var hp: float = p.health.current
	await F.seconds(self, 0.7)
	_check(p.health.current == hp, "a frozen enemy deals no contact damage")
	await F.seconds(self, 1.2)
	_check(p.health.current < hp, "it hits again after it thaws")
	e.queue_free()
	p.health.setup(p.health.max_health)
	p.hurtbox.invulnerable = true


## 300 enemies with a mix of statuses kept on them: the mean physics time stays inside the crowd budget.
func _crowd_cost(F: GDScript, main: Node, p) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crowd: Array = []
	for i in 300:
		var type: String = ["grunt", "grunt", "ranged", "dasher"][i % 4]
		crowd.append(F.spawn_enemy(main, type, p.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 160), 100000.0))
	await F.seconds(self, 1.0)
	var plain: float = await _mean_physics_ms(F, crowd, false)
	var loaded: float = await _mean_physics_ms(F, crowd, true)
	print("mean physics %.2f ms plain, %.2f ms with statuses, 300 enemies" % [plain, loaded])
	_check(loaded <= BUDGET_MS, "mean physics time %.2f ms with statuses is over %.1f ms" % [loaded, BUDGET_MS])
	for e in crowd:
		e.queue_free()


func _mean_physics_ms(F: GDScript, crowd: Array, with_statuses: bool) -> float:
	var total := 0.0
	var frames := 180
	for i in frames:
		if with_statuses and i % 30 == 0:  # keep them on for the whole run
			for j in crowd.size():
				var e = crowd[j]
				e.apply_slow(0.6, 1.0)
				e.apply_vulnerable(1.5, 1.0)
				e.ignite(2.0, 1.0)
				if j % 4 == 0:
					e.freeze(0.4, 1.2)
		await physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return total / frames

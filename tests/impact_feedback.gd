extends SceneTree
## Feel feedback on impact (spec v0.8): the particle bits in Effects (cap, spark budget, direction, drift, fade, clear),
## enemy hit and death feedback, pickups popping out, the hurt pulse.
## Run: godot --headless --path . --script tests/impact_feedback.gd

var _failed := false
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_F = load("res://tests/fixture.gd")
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 3)
	var fx = get_nodes_in_group(&"effects")[0]

	# Bits: a burst adds its count, thrown in the cone around dir, plus the drift.
	fx.clear()
	fx.burst(Vector2(100, 100), Color.WHITE, 5, Vector2(50, 50), 1.0, 2.0, Vector2.RIGHT, 0.0)
	_check(fx._bits.size() == 5, "a burst of 5 adds 5 bits, got %d" % fx._bits.size())
	var straight := true
	for b in fx._bits:
		straight = straight and b.vel.is_equal_approx(Vector2(50, 0))
	_check(straight, "a zero-width cone throws every bit along dir at the given speed")
	fx.clear()
	fx.burst(Vector2.ZERO, Color.WHITE, 3, Vector2(0, 0), 1.0, 2.0, Vector2.ZERO, TAU, Vector2(0, -14))
	var drifting := true
	for b in fx._bits:
		drifting = drifting and b.vel.is_equal_approx(Vector2(0, -14))
	_check(drifting, "drift is added to every bit")
	fx.clear()
	fx.dust(Vector2.ZERO, Vector2.RIGHT)
	_check(fx._bits.size() == 2, "dust is 2 bits")
	var behind := true
	for b in fx._bits:
		behind = behind and b.vel.x < 0.0
	_check(behind, "dust is thrown backwards from the direction of travel")
	fx.clear()
	fx.dust(Vector2.ZERO, Vector2.RIGHT, 3)
	_check(fx._bits.size() == 3, "a skid is 3 bits")

	# The cap: 1000 bursts leave MAX_BITS, and the newest survive.
	fx.clear()
	for i in 200:
		fx.burst(Vector2(i, 0), Color.WHITE, 5, Vector2(10, 10), 5.0, 2.0)
	_check(fx._bits.size() == fx.MAX_BITS, "1000 bits leave %d, got %d" % [fx.MAX_BITS, fx._bits.size()])
	_check(fx._bits.back().pos.x == 199.0, "the newest bits are the ones kept")

	# The spark budget: low priority bursts are skipped over SPARK_BUDGET, normal ones are not.
	fx.clear()
	fx.burst(Vector2.ZERO, Color.WHITE, fx.SPARK_BUDGET + 8, Vector2(10, 10), 5.0, 2.0)
	var before: int = fx._bits.size()
	fx.burst(Vector2.ZERO, Color.WHITE, 3, Vector2(10, 10), 5.0, 2.0, Vector2.ZERO, TAU, Vector2.ZERO, true)
	_check(fx._bits.size() == before, "a spark burst is skipped over the budget")
	fx.burst(Vector2.ZERO, Color.WHITE, 3, Vector2(10, 10), 5.0, 2.0)
	_check(fx._bits.size() == before + 3, "a normal burst still lands over the budget")
	fx.clear()
	fx.burst(Vector2.ZERO, Color.WHITE, 3, Vector2(10, 10), 5.0, 2.0, Vector2.ZERO, TAU, Vector2.ZERO, true)
	_check(fx._bits.size() == 3, "a spark burst lands under the budget")

	# clear() empties the bits; bits are gone after their life.
	fx.clear()
	_check(fx._bits.is_empty(), "clear() empties the bits")
	fx.burst(Vector2.ZERO, Color.WHITE, 4, Vector2(10, 10), 0.2, 2.0)
	await create_timer(0.5).timeout
	_check(fx._bits.is_empty(), "bits are gone after their life, %d left" % fx._bits.size())

	await _hit_tests(main, fx)
	await _death_tests(main, fx)
	await _pickup_tests(main)
	await _pulse_tests(main)

	main.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# A frozen enemy has its physics process off, so the recoil ease is stepped by hand.
func _step(e, frames: int) -> void:
	for i in frames:
		e._physics_process(1.0 / 60.0)


func _hit_tests(main, fx) -> void:
	var p = _F.player()
	var spot: Vector2 = p.global_position + Vector2(60, 0)
	var e = _F.spawn_enemy(main, "dasher", spot, 1.0, true)  # no drawn frames: it flashes white
	await _F.frames(self, 3)

	# A hit that does not kill: 3 sparks, the flash, a recoil away from the player that eases back to nothing.
	fx.clear()
	e.take_damage(1.0)
	_check(fx._bits.size() == 3, "a hit gives 3 sparks, got %d" % fx._bits.size())
	_check(absf(e._flash_left - 0.09) < 0.0001 and e.sprite.flash, "the flash lasts 0.09 s")
	_check(e.sprite.position.x > 0.0 and e.sprite.position.length() <= 2.0001, "recoil is up to 2 px, away from the player, got %s" % e.sprite.position)
	_step(e, 2)
	_check(e.sprite.position.length() < 2.0, "the recoil is easing back")
	_step(e, 6)  # 0.133 s in all
	_check(e.sprite.position == Vector2.ZERO, "the recoil is over after 0.1 s, got %s" % e.sprite.position)
	e.deactivate()

	# Over the spark budget the sparks are skipped.
	fx.clear()
	fx.burst(Vector2.ZERO, Color.WHITE, fx.SPARK_BUDGET + 8, Vector2(10, 10), 5.0, 2.0)
	var n: int = fx._bits.size()
	var e2 = _F.spawn_enemy(main, "dasher", spot, 1.0, true)
	await _F.frames(self, 3)
	e2.take_damage(1.0)
	_check(fx._bits.size() == n, "no sparks over the budget")
	e2.deactivate()

	# A training dummy gets the sparks but never moves, tints or recoils.
	fx.clear()
	var d = _F.spawn_enemy(main, "training_dummy", spot + Vector2(0, 40), 1.0, true)
	await _F.frames(self, 3)
	var start: Vector2 = d.global_position
	d.take_damage(5.0)
	_check(fx._bits.size() == 3, "a dummy gets the sparks")
	_step(d, 3)
	_check(d.sprite.position == Vector2.ZERO and d.global_position == start, "a dummy does not recoil or move")
	_check(d.sprite.modulate == Color.WHITE, "a dummy is not tinted")
	d.deactivate()


func _puffs(fx) -> int:
	var n := 0
	for f in fx._fx:
		if f.kind == &"puff":
			n += 1
	return n


func _death_tests(main, fx) -> void:
	var p = _F.player()
	var cam = main.get_node("Camera")
	# The burst has one bit per 30 px^2 of body, 5 to 14: Grunt 6, Ranged 7, Dasher 14. A kill gets no hit sparks.
	for row in [["grunt", 6], ["ranged", 7], ["dasher", 14]]:
		var e = _F.spawn_enemy(main, row[0], p.global_position + Vector2(80, 0), 1.0, true)
		await _F.frames(self, 3)
		fx.clear()
		cam._shake_time = 0.0
		e.take_damage(1e9)
		_check(fx._bits.size() == row[1], "%s death: %d bits, got %d" % [row[0], row[1], fx._bits.size()])
		if row[0] == "dasher":  # the grunt and the ranged enemy die as drawn art; the dasher leaves the colour puff, exactly one
			_check(_puffs(fx) == 1, "%s death: exactly one puff, got %d" % [row[0], _puffs(fx)])
		_check(e.sprite.body_color == fx._bits[0].color, "%s death: the burst is the body colour" % row[0])
		# Only the Dasher (kill_shake 1.2) kicks the camera.
		_check((cam._shake_time > 0.0) == (row[0] == "dasher"), "%s death: camera shake %s" % [row[0], cam._shake_time])
	fx.clear()


func _pickup_tests(main) -> void:
	var p = _F.player()
	var pickups = main.get_node("Pickups")
	var far: Vector2 = p.global_position + Vector2(220, 0)  # outside the 48 px pickup radius

	# 20 gems and 20 coins hop 10 to 17 px from where they spawned and then lie still.
	var items: Array = []
	for i in 20:
		pickups.spawn_gem(far + Vector2(0, i * 3), 1)
		pickups.spawn_coin(far + Vector2(40, i * 3))
	for c in pickups.get_children():
		if c.visible:
			items.append([c, c.global_position])
	_check(items.size() >= 40, "40 pickups are out, got %d" % items.size())
	await _F.seconds(self, 0.4)
	var bad := 0
	for it in items:
		var d: float = it[0].global_position.distance_to(it[1])
		if d < 10.0 or d > 17.0 or it[0]._pop_vel != Vector2.ZERO:
			bad += 1
	_check(bad == 0, "%d of %d pickups did not hop 10 to 17 px and rest" % [bad, items.size()])
	# They stay put until the Player comes: then they are pulled in and collected.
	var session = root.get_node("GameSession")
	var gold: int = session.run_gold
	# Only the coins are collected here: eight gems would level the Player up and the level-up menu pauses the game.
	var coins: Array = []
	for it in items:
		if it[0].scene_file_path.ends_with("coin.tscn"):
			coins.append(it[0])
			it[0].attract(p)  # the Player's collector would do this for the ones inside its radius
	await _F.seconds(self, 4.0)
	var left := 0
	for c in coins:
		if c.visible:
			left += 1
	_check(coins.size() == 20 and left == 0, "%d of %d coins were not collected" % [left, coins.size()])
	_check(session.run_gold == gold + 20, "the 20 coins reached the purse, got %d" % (session.run_gold - gold))

	# Inside the pickup radius attract() sets the target at once, but the pull-in waits for the hop to end.
	p.global_position = Vector2(Arena.world_size) / 2.0
	pickups.spawn_coin(p.global_position + Vector2(20, 0))
	var gem = null
	for c in pickups.get_children():
		if c.visible and c.scene_file_path.ends_with("coin.tscn") and c.global_position.distance_to(p.global_position + Vector2(20, 0)) < 1.0:
			gem = c
	await _F.frames(self, 4)
	_check(gem != null and gem.target != null and gem._pop_vel != Vector2.ZERO, "attracted mid-hop: target set, still hopping")
	await _F.seconds(self, 1.5)
	_check(not gem.visible, "then it is collected as before")

	# Near the arena edge a pickup stays inside the arena.
	var edge := Vector2(1, 1)
	for i in 10:
		pickups.spawn_gem(edge, 1)
	await _F.seconds(self, 0.4)
	var inside := true
	for c in pickups.get_children():
		if c.visible and c.global_position.distance_to(edge) < 40.0:
			inside = inside and c.global_position.x >= 6.0 + Arena.wall_margin - 0.01 and c.global_position.y >= 6.0 + Arena.wall_margin - 0.01
	_check(inside, "a pickup near the edge stays inside the arena")


func _pulse_tests(main) -> void:
	var p = _F.player()
	var hud = main.get_node("UI/Hud")
	_check(hud._hurt_pulse == 0.0, "no pulse before a hit")
	# A landed hit sets the pulse and it runs out within 0.4 s.
	p.hurtbox.grace_left = 0.0
	p.hurtbox.invulnerable = false
	_check(p.hurtbox.receive_hit(5.0), "the hit landed")
	_check(absf(hud._hurt_pulse - 0.35) < 0.0001, "the pulse is 0.35 s, got %s" % hud._hurt_pulse)
	await _F.seconds(self, 0.4)
	_check(hud._hurt_pulse == 0.0, "the pulse is over after 0.4 s")
	# A hit that does not land (i-frames, grace, Phase Shift) makes none.
	p.hurtbox.grant_grace(1.0)
	_check(not p.hurtbox.receive_hit(5.0) and hud._hurt_pulse == 0.0, "a hit during grace does not pulse")
	p.hurtbox.grace_left = 0.0
	p.hurtbox.invulnerable = true
	_check(not p.hurtbox.receive_hit(5.0) and hud._hurt_pulse == 0.0, "a hit while invulnerable does not pulse")
	p.hurtbox.invulnerable = false

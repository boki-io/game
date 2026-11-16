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
	var e = _F.spawn_enemy(main, "ranged", spot, 1.0, true)  # no drawn frames: it flashes white
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
	var e2 = _F.spawn_enemy(main, "ranged", spot, 1.0, true)
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

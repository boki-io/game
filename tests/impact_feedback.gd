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

	main.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

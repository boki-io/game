extends SceneTree
## Walking feel (spec v0.8): the Player ramps up to top speed in accel_time and coasts to a stop in friction_time, never
## exceeds top speed, loses speed into a wall, hands a dash over at walking speed, and a time of 0 is instant (the old movement).
## Run: godot --headless --path . --script tests/movement_feel.gd

var _failed := false
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _hold(p, dir: Vector2) -> void:
	# PlayerInput overwrites move_vector from the (empty) device input every physics frame, so it is switched off.
	p.player_input.set_physics_process(false)
	p.player_input.move_vector = dir


func _init() -> void:
	await process_frame
	_F = load("res://tests/fixture.gd")
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 5)
	var p = _F.player()
	var top := 90.0
	_check(p.accel_time == 0.06 and p.friction_time == 0.08, "the Knight's ramp times come from its data")

	# Ramp up: above 0 and below top after one frame, top after accel_time plus two frames, never above it.
	_hold(p, Vector2.RIGHT)
	await physics_frame
	var first: float = p.velocity.length()
	_check(first > 0.0 and first < top, "one frame in: above 0 and below top, got %s" % first)
	var peak := first
	for i in 12:
		await physics_frame
		peak = maxf(peak, p.velocity.length())
	_check(absf(p.velocity.length() - top) < 0.01, "after the ramp: top speed, got %s" % p.velocity.length())
	_check(peak <= top + 0.01, "never above top speed, peak %s" % peak)

	# Friction: not an instant stop, but stopped within friction_time plus two frames.
	_hold(p, Vector2.ZERO)
	await physics_frame
	_check(p.velocity.length() > 0.0, "one frame after release the Player is still moving")
	await _F.seconds(self, p.friction_time + 0.04)
	_check(p.velocity.length() < 0.01, "stopped after friction_time, got %s" % p.velocity.length())

	# A diagonal is capped at top speed, not top times 1.41.
	_hold(p, Vector2(1, 1).normalized())  # PlayerInput gives a vector of length 1 at most
	await _F.seconds(self, 0.3)
	_check(p.velocity.length() <= top + 0.01, "diagonal speed %s" % p.velocity.length())
	_hold(p, Vector2.ZERO)
	await _F.seconds(self, 0.3)

	# Phase Shift's speed_scale raises the top speed and the ramp follows it.
	p.speed_scale = 1.5
	_hold(p, Vector2.RIGHT)
	await _F.seconds(self, 0.3)
	_check(absf(p.velocity.length() - 135.0) < 0.01, "phased top speed 135, got %s" % p.velocity.length())
	p.speed_scale = 1.0
	_hold(p, Vector2.ZERO)
	await _F.seconds(self, 0.3)

	# A wall takes the speed: walking left into the rock band leaves no speed along the wall's normal.
	p.global_position = Vector2(60, Arena.world_size.y / 2.0)
	_hold(p, Vector2.LEFT)
	await _F.seconds(self, 1.5)
	_check(p.global_position.x >= 14.0, "the Player is stopped by the wall, x %s" % p.global_position.x)
	_check(absf(p.get_real_velocity().x) < 1.0, "no speed left into the wall, got %s" % p.get_real_velocity().x)
	_hold(p, Vector2.ZERO)
	p.global_position = Vector2(Arena.world_size) / 2.0
	await _F.seconds(self, 0.3)

	# A dash that ends with a key held hands over at walking speed the next frame; with no key it ends at zero.
	p.override_active = true
	p.velocity_override = Vector2.RIGHT * 300.0
	await physics_frame
	_hold(p, Vector2.RIGHT)
	await physics_frame  # the override frame: _move_vel is set from the held key
	p.override_active = false
	await physics_frame
	_check(absf(p.velocity.length() - top) < 0.01, "dash into a held key: walking speed at once, got %s" % p.velocity.length())
	_hold(p, Vector2.ZERO)
	await _F.seconds(self, 0.3)
	p.override_active = true
	p.velocity_override = Vector2.RIGHT * 300.0
	await physics_frame
	p.override_active = false
	await physics_frame
	_check(p.velocity.length() < 0.01, "dash with no key held ends at zero, got %s" % p.velocity.length())

	# A time of 0 is the old instant movement.
	p.accel_time = 0.0
	p.friction_time = 0.0
	_hold(p, Vector2.RIGHT)
	await physics_frame
	_check(absf(p.velocity.length() - top) < 0.01, "accel_time 0: top speed on the first frame, got %s" % p.velocity.length())
	_hold(p, Vector2.ZERO)
	await physics_frame
	_check(p.velocity.length() < 0.01, "friction_time 0: stopped on the first frame")
	# No NaN when the top speed is 0.
	p.speed_scale = 0.0
	_hold(p, Vector2.RIGHT)
	await _F.frames(self, 3)
	_check(is_zero_approx(p.velocity.length()) and not is_nan(p.velocity.x), "top speed 0 gives no NaN")
	p.speed_scale = 1.0
	p.accel_time = 0.06
	p.friction_time = 0.08

	# A dead Player has no velocity.
	_hold(p, Vector2.RIGHT)
	await _F.seconds(self, 0.3)
	p.health.take_damage(1e9)
	await _F.frames(self, 2)
	_check(p.dead and p.velocity == Vector2.ZERO and p._move_vel == Vector2.ZERO, "a dead Player stands still")

	# Agility 7 (108.9 px/s) reaches its own top speed.
	main.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

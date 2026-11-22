extends SceneTree
## Enemy states (spec 1.8 section 5): DORMANT stands still and deals no contact damage, a hit wakes it (CHASE, `woken`,
## fresh brain), RETURNING walks home at return_speed_mult, deals no contact damage, and on arrival heals to full, goes
## DORMANT and emits `arrived_home`; a fresh enemy is CHASE and still chases.
## Run: godot --headless --path . --script tests/enemy_states.gd

var _failed := false
var _woken := 0
var _arrived := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 3)
	var p = F.player()
	p.caster.set_physics_process(false)  # nothing but the enemies may touch the hero
	var start: Vector2 = p.global_position
	var hp0: float = p.health.current

	# CHASE is the default and still chases and hits.
	var c = F.spawn_enemy(main, "grunt", start + Vector2(80, 0))
	_check(c.state == c.State.CHASE, "default state is CHASE")
	await F.seconds(self, 0.5)
	_check(c.global_position.distance_to(start) < 80.0 - 10.0, "a CHASE enemy walks toward the hero")
	await F.seconds(self, 2.0)
	_check(p.health.current < hp0, "a CHASE enemy hits on contact")
	c.deactivate()
	p.health.setup(p.health.max_health)
	hp0 = p.health.current

	# DORMANT: stays put, no contact damage even when on top of the hero.
	var d = F.spawn_enemy(main, "grunt", start + Vector2(2, 0))
	d.state = d.State.DORMANT
	d.home = d.global_position
	var spot: Vector2 = d.global_position
	await F.seconds(self, 2.0)
	_check(d.global_position.distance_to(spot) < 0.01, "a DORMANT enemy does not move")
	_check(p.health.current == hp0, "a DORMANT enemy deals no contact damage")

	# Damage wakes it: CHASE, woken signal, brain reset.
	d.woken.connect(func(_e) -> void: _woken += 1)
	d.take_damage(1.0)
	_check(d.state == d.State.CHASE, "a hit wakes a DORMANT enemy")
	_check(_woken == 1, "woken emitted once (got %d)" % _woken)
	d.take_damage(1.0)
	_check(_woken == 1, "an awake enemy does not emit woken again")
	d.deactivate()

	# RETURNING: walks home at 1.2x speed, harmless, then heals and goes dormant.
	var r = F.spawn_enemy(main, "grunt", start + Vector2(0, 40))
	r.home = start + Vector2(0, 40) + Vector2(-60, 0)
	r.health.current = 5.0
	r.arrived_home.connect(func(_e) -> void: _arrived += 1)
	r.send_home()
	_check(r.state == r.State.RETURNING, "send_home sets RETURNING")
	var before: Vector2 = r.global_position
	await F.seconds(self, 0.5)
	var walked: float = r.global_position.distance_to(before)
	var want: float = r.data.speed * r.return_speed_mult * 0.5
	_check(absf(walked - want) < want * 0.15, "returning speed (walked %f, wanted about %f)" % [walked, want])
	_check(r.global_position.x < before.x, "it walks toward home")
	_check(p.health.current == hp0, "a RETURNING enemy deals no contact damage")
	await F.seconds(self, 2.0)
	_check(r.state == r.State.DORMANT, "dormant on arrival (state %d)" % r.state)
	_check(_arrived == 1, "arrived_home emitted once (got %d)" % _arrived)
	_check(r.health.current == r.health.max_health, "healed to full on arrival")
	_check(r.global_position.distance_to(r.home) <= 8.0, "stands at home")

	# A hit on a returning enemy wakes it too.
	r.send_home()
	r.take_damage(1.0)
	_check(r.state == r.State.CHASE, "a hit wakes a RETURNING enemy")

	main.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

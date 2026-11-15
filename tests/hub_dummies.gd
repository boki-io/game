extends SceneTree
## Training dummies: every ability of both characters damages them, and they never die, move, tint or stun.
## Also the damage readout (Last / Total / DPS bursts) and its 3s timeout.
## Run: godot --headless --path . --script tests/hub_dummies.gd

var _failed := false
var _players: Node
var _hits := 0.0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _wait(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		await physics_frame


func _init() -> void:
	await process_frame
	await process_frame
	_players = root.get_node("PlayerRegistry")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _wait(1.5)
	var dummies: Array = hub.get_node("World/Dummies").get_children()
	_check(dummies.size() == 3, "three dummies")
	var start := []
	for d in dummies:
		start.append(d.global_position)
		d.health.damaged.connect(func(amount: float) -> void: _hits += amount)
		_check(d.active and d.data.immovable, "dummy is active and immovable")

	# Both characters, every slot. Each slot: reset the counter, cast, and expect some damage.
	var spots := {&"knight": Vector2(180, 170), &"wizard": Vector2(190, 170)}
	for index in 2:
		hub._focus(index, true)
		await _wait(0.4)
		hub._confirm()
		await _wait(0.3)
		var p = _players.players[0]
		var id: StringName = p.character.id
		for slot in [&"auto", &"q", &"e", &"r"]:
			await _wait(0.4)
			p.global_position = spots[id]
			p.hurtbox.grace_left = 0.0
			p.caster.cooldowns[slot] = 0.0
			_hits = 0.0
			if slot == &"auto":
				await _wait(1.2)  # the auto attack fires by itself
			else:
				p.player_input.aim_vector = Vector2.LEFT
				p.player_input.ability_pressed.emit(slot)
				await _wait(1.6)  # long enough for a meteor and for orbs to sweep
			_check(_hits > 0.0, "%s %s damages the dummies" % [id, slot])
		_check(p.mana.current >= p.mana.max_mana() - 0.01, "%s mana never drops" % id)
		hub._enter_browse(index, true)
		await _wait(0.4)
		hub._lockout = 0.0

	await _wait(3.5)
	for i in dummies.size():
		var d = dummies[i]
		_check(d.active and d.health.current >= d.health.max_health * 0.5, "dummy %d is alive" % i)
		_check(d.global_position == start[i], "dummy %d never moved" % i)
		_check(d.sprite.modulate == Color.WHITE, "dummy %d is not tinted" % i)
		_check(d._stun_left <= 0.0, "dummy %d is not stunned" % i)
	# Hits take it below half: topped back up, and `died` never fires.
	var d0 = dummies[0]
	var died := [false]
	d0.health.died.connect(func() -> void: died[0] = true)
	d0.take_damage(d0.health.max_health * 0.9)
	_check(d0.health.current == d0.health.max_health and not died[0], "a big hit is topped up, the dummy never dies")
	d0.stun(5.0)
	d0.apply_knockback(Vector2(500, 0))
	await _wait(0.5)
	_check(d0._stun_left <= 0.0 and d0.global_position == start[0] and d0.sprite.modulate == Color.WHITE, "stun and knockback are ignored")
	_check(not d0.brain.can_contact(), "the dummy never makes contact")

	# The readout: bursts, DPS and the timeout (driven with its own clock).
	var r := DummyReadout.new()
	root.add_child(r)
	r._on_damaged(20.0)
	await _wait(0.5)
	r._on_damaged(22.0)
	_check(r.last == 22.0 and r.total == 42.0, "Last and Total within a burst")
	_check(is_equal_approx(r.dps(), 42.0), "DPS uses at least 1.0s")
	_check(r.readout_text() == "Last 22  Total 42  DPS 42", "readout text (%s)" % r.readout_text())
	await _wait(2.5)
	r._on_damaged(10.0)  # 3.0s after the first hit is still inside the 3s gap from the previous
	_check(r.total == 52.0, "a hit within 3s of the previous continues the burst")
	await _wait(3.2)
	_check(r.readout_text().is_empty(), "the readout clears 3s after the last hit")
	r._on_damaged(5.0)
	_check(r.total == 5.0, "a later hit starts a new burst")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

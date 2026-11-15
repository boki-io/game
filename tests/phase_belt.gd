extends SceneTree
## Phase Shift's orb belt: it appears when the phase ends, hurts an enemy it sweeps through, follows the Wizard,
## stops after its duration, and Orbital Ring adds orbs.
## Run: godot --headless --path . --script tests/phase_belt.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"wizard")
	await F.frames(self, 3)
	var p = F.player()
	var data = p.caster.ability_q
	p.caster.set_physics_process(false)  # keep the auto bolt out of it; cooldowns do not matter here

	var victim = F.spawn_enemy(main, "grunt", p.global_position + Vector2(data.radius, 0), 1000.0, true)
	p.start_phase(data.duration, 1.5, 0.0, data.immunity_after,
		{"count": 5, "radius": data.radius, "turns": 2.0, "damage": data.damage, "duration": 2.0})
	await F.seconds(self, data.duration - 0.1)
	_check(p._belt == null or not p._belt.active, "no belt while still phased")
	await F.seconds(self, 0.3)
	_check(p._belt != null and p._belt.active, "the belt appears when the phase ends")
	await F.seconds(self, 1.0)
	_check(victim.health.current < victim.health.max_health, "the belt hurts an enemy at its radius")

	p.global_position += Vector2(50, 0)
	await F.frames(self, 2)
	_check(is_equal_approx(p._belt.global_position.x, p.global_position.x), "the belt follows the Wizard")
	await F.seconds(self, 1.5)
	_check(not p._belt.active, "the belt stops after its duration")

	# Orbital Ring: more orbs in the belt.
	F.upgrade(p, "phase_orbs")
	_check(int(p.caster.value(data, &"orbs", 5.0)) > 5, "Orbital Ring adds orbs")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

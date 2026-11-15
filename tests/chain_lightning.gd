extends SceneTree
## Chain Lightning: strikes the nearest enemy then jumps (4 jumps, 5 with Extra Jumps), damage falls off
## 15% per jump, and an enemy standing on the Wizard is still struck.
## Run: godot --headless --path . --script tests/chain_lightning.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _line(F: GDScript, main: Node, p, count: int) -> Array:
	var out := []
	for i in count:
		out.append(F.spawn_enemy(main, "grunt", p.global_position + Vector2(50 + 40 * i, 0), 100.0, true))
	return out


func _hit_count(enemies: Array) -> int:
	var n := 0
	for e in enemies:
		if e.health.current < e.health.max_health:
			n += 1
	return n


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"wizard")
	await F.frames(self, 3)
	var p = F.player()
	p.caster.set_physics_process(false)  # cast by hand only, no auto bolts
	var damage = p.caster.damage_of(p.caster.ability_e)

	var enemies := _line(F, main, p, 7)
	await F.frames(self, 2)
	F.cast(p, &"e")
	await F.frames(self, 2)
	_check(_hit_count(enemies) == 5, "base chain strikes 5 enemies (struck %d)" % _hit_count(enemies))
	var first_loss = enemies[0].health.max_health - enemies[0].health.current
	var second_loss = enemies[1].health.max_health - enemies[1].health.current
	_check(is_equal_approx(first_loss, damage), "the first enemy takes full damage")
	_check(is_equal_approx(second_loss, damage * 0.85), "the second takes 85%")
	for e in enemies:
		e.queue_free()
	await F.frames(self, 2)

	# Extra Jumps: one more.
	F.upgrade(p, "lightning_jumps")
	var expected = 1 + 4 + int(p.caster.value(p.caster.ability_e, &"jumps", 0.0))
	p.caster.cooldowns[&"e"] = 0.0
	enemies = _line(F, main, p, 8)
	await F.frames(self, 2)
	F.cast(p, &"e")
	await F.frames(self, 2)
	_check(_hit_count(enemies) == expected, "Extra Jumps strikes %d (struck %d)" % [expected, _hit_count(enemies)])
	for e in enemies:
		e.queue_free()
	await F.frames(self, 2)

	# An enemy standing right on the Wizard is struck too.
	p.caster.cooldowns[&"e"] = 0.0
	var on_top = F.spawn_enemy(main, "grunt", p.global_position, 100.0, true)
	await F.frames(self, 2)
	F.cast(p, &"e")
	await F.frames(self, 2)
	_check(on_top.health.current < on_top.health.max_health, "an enemy on top of the Wizard is struck")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

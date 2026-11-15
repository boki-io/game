extends SceneTree
## Wizard kit: Arcane Bolt auto-fires, Phase Shift (immune, faster, costs mana), Chain Lightning, Meteor Strike
## (lands after its windup at the aimed spot) and the Arcane Focus trait.
## Run: godot --headless --path . --script tests/wizard_abilities.gd

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
	var origin = p.global_position

	# Arcane Bolt: fires by itself at an enemy in range.
	var target = F.spawn_enemy(main, "grunt", origin + Vector2(80, 0), 100.0, true)
	await F.seconds(self, 1.2)
	_check(target.health.current < target.health.max_health, "Arcane Bolt hits an enemy in range by itself")
	target.queue_free()
	await F.frames(self, 2)

	# Arcane Focus: standing still for 1s switches on +25% damage; moving ends it.
	await F.seconds(self, 1.2)
	_check(p.trait_active(), "Arcane Focus is active after standing still")
	_check(is_equal_approx(p.stats.value(&"damage", 1.0), 1.25), "Arcane Focus gives +25% damage")

	# Phase Shift: costs mana, makes the Wizard immune and faster, then wears off.
	var mana = p.mana.current
	F.cast(p, &"q")
	await F.frames(self, 3)
	_check(p.mana.current < mana, "Phase Shift costs mana")
	_check(p.hurtbox.is_immune(), "immune while phased")
	_check(p.speed_scale > 1.4, "faster while phased")
	await F.seconds(self, p.caster.ability_q.duration + 0.2)
	_check(p.phase_left <= 0.0 and p.speed_scale == 1.0, "Phase Shift wears off")
	await F.seconds(self, 2.5)  # the orb belt and the grace period are over

	# Chain Lightning: strikes enemies in any direction, including behind.
	var behind = F.spawn_enemy(main, "grunt", p.global_position + Vector2(-60, 0), 100.0, true)
	var behind_hp = behind.health.current
	await F.frames(self, 2)  # the enemy grid is rebuilt once per physics frame
	F.cast(p, &"e", Vector2.RIGHT)
	await F.frames(self, 2)
	_check(behind.health.current < behind_hp, "Chain Lightning strikes an enemy behind the Wizard")
	behind.queue_free()
	await F.frames(self, 2)

	# Meteor Strike: nothing at once, a big hit after the windup at the aimed spot.
	await F.seconds(self, 1.0)
	var spot = p.global_position + Vector2(p.caster.ability_r.range, 0)
	var victim = F.spawn_enemy(main, "grunt", spot, 100.0, true)
	var before = victim.health.current
	F.cast(p, &"r", Vector2.RIGHT)
	await F.seconds(self, 0.3)
	_check(victim.health.current == before, "the meteor has not landed yet")
	await F.seconds(self, p.caster.ability_r.windup + 0.3)
	_check(before - victim.health.current >= p.caster.ability_r.damage - 0.01, "the meteor deals its damage at the spot")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

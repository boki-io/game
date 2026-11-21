extends SceneTree
## Player.revive(pos): after death (frozen corpse, hurtbox off, grey tint, animation locked, cast cancelled) it clears all
## of it, restores full health and mana, places the hero, plays idle and registers with PlayerRegistry again.
## Run: godot --headless --path . --script tests/player_revive.gd

var _failed := false


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
	var reg: Node = root.get_node("PlayerRegistry")
	var max_hp: float = p.health.max_health
	p.mana.spend(60.0)
	p.caster.cooldowns[&"q"] = 5.0
	p.health.take_damage(max_hp * 10.0)
	await F.frames(self, 3)
	_check(p.dead, "the hero is dead")
	_check(reg.nearest(Vector2.ZERO) == null, "a dead hero is not a target")
	reg.unregister(p)  # a scene may drop it on death: revive must put it back

	var spot := Vector2(123, 456)
	p.revive(spot)
	await F.frames(self, 3)
	_check(not p.dead, "revive clears dead")
	_check(p.global_position.distance_to(spot) < 1.0, "placed at the spot (got %s)" % p.global_position)
	_check(is_equal_approx(p.health.current, max_hp), "full health")
	_check(is_equal_approx(p.mana.current, p.mana.max_mana()), "full mana")
	_check(p.hurtbox.monitorable, "hurtbox on again")
	_check(not p.hurtbox.invulnerable, "not invulnerable")
	_check(p.sprite.modulate.is_equal_approx(Color.WHITE), "tint cleared")
	_check(not p._anim_busy, "animation lock cleared")
	_check(not p.caster.is_busy() and p.caster.cooldowns[&"q"] == 0.0, "caster reset")
	_check(reg.players.has(p), "registered again")
	_check(reg.nearest(Vector2.ZERO) == p, "a target again")
	if p._anim != null:
		_check(p._anim.animation != &"death", "death animation replaced (got %s)" % p._anim.animation)

	p.health.take_damage(5.0)
	_check(p.health.current < max_hp, "takes damage again")
	p.health.take_damage(max_hp * 10.0)
	_check(p.dead, "can die a second time")
	p.revive(spot)
	_check(not p.dead and p.health.current == max_hp, "and revive again")

	main.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

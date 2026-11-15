extends SceneTree
## Knight's Dash & Slash: unhittable while dashing and for immunity_after seconds afterwards, then hittable again.
## Run: godot --headless --path . --script tests/dash_immunity.gd

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
	var data: AbilityData = p.caster.ability_q
	_check(not p.hurtbox.is_immune(), "hittable before the dash")

	F.cast(p, &"q")
	await F.frames(self, 3)
	_check(p.caster.is_busy(), "dashing")
	_check(p.hurtbox.is_immune(), "immune while dashing")
	_check(not p.hurtbox.receive_hit(10.0), "a hit during the dash is ignored")

	await F.seconds(self, data.duration + 0.1)
	_check(not p.caster.is_busy(), "dash finished")
	_check(p.hurtbox.is_immune(), "still immune right after the dash")
	await F.seconds(self, data.immunity_after + 0.2)
	_check(not p.hurtbox.is_immune(), "hittable again after the grace period")
	var hp = p.health.current
	_check(p.hurtbox.receive_hit(10.0) and p.health.current == hp - 10.0, "a hit now lands")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

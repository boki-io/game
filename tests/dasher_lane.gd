extends SceneTree
## A Dasher's locked lane: a player standing in it takes dash_damage once; a player who steps out
## of it after it locks takes nothing.
## Run: godot --headless --path . --script tests/dasher_lane.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## Runs one dash and returns the damage the player took. `sidestep` moves the player out of the lane once it locks.
func _run(F: GDScript, sidestep: bool) -> float:
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 3)
	var p = F.player()
	p.caster.set_physics_process(false)  # no auto-attacks: the Dasher must survive
	var data = load("res://content/enemies/dasher.tres")
	var start = p.global_position
	var dasher = F.spawn_enemy(main, "dasher", start + Vector2(-100, 0))
	await F.seconds(self, data.aim_time + 0.05)
	if sidestep:
		p.global_position = start + Vector2(0, 60)  # the lane is locked by now
	await F.seconds(self, data.lock_time + data.dash_distance / data.dash_speed + 0.2)
	var lost = p.health.max_health - p.health.current
	main.queue_free()
	await F.frames(self, 3)
	return lost


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var data = load("res://content/enemies/dasher.tres")
	var standing: float = await _run(F, false)
	_check(is_equal_approx(standing, data.dash_damage), "standing in the lane costs %s (took %s)" % [data.dash_damage, standing])
	var stepped: float = await _run(F, true)
	_check(stepped == 0.0, "stepping out of the locked lane costs nothing (took %s)" % stepped)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

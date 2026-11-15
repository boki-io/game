extends SceneTree
## 300 enemies that cannot die, piled on a stationary Player: the physics step must stay well inside its
## 16.6ms budget. Prints the mean and worst physics time. Uses the engine's own physics-process timer, so it is
## meaningful headless (it leaves out rendering; check F3 in a real window for the full picture).
## Run: godot --headless --path . --script tests/crowd_performance.gd

const ENEMIES := 300
const FRAMES := 180
const BUDGET_MS := 12.0  # mean physics time; the frame budget is 16.6ms and rendering needs the rest

var _failed := false


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 3)
	var p = F.player()
	p.hurtbox.invulnerable = true  # the pile must not kill the Player
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in ENEMIES:
		var type: String = ["grunt", "grunt", "ranged", "dasher"][i % 4]
		F.spawn_enemy(main, type, p.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 160), 1000.0)
	await F.seconds(self, 1.0)  # let the crowd close in

	var total := 0.0
	var worst := 0.0
	for i in FRAMES:
		await physics_frame
		var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total += ms
		worst = maxf(worst, ms)
	var mean := total / FRAMES
	print("mean physics %.2f ms, worst %.2f ms with %d enemies" % [mean, worst, ENEMIES])
	if mean > BUDGET_MS:
		_failed = true
		print("FAIL: mean physics time %.2f ms is over %.1f ms" % [mean, BUDGET_MS])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## The 300-enemy crowd of crowd_performance.gd on a Bone-Warren-like dense layout, with a stationary Player and a
## moving one (the flow field only rebuilds when the Player changes cell). Gate: mean physics time under the same
## limit as crowd_performance.gd. The worst frame and the mean without obstacles are logged only (headless timing is
## too noisy for a fixed gate).
## The layout is MapLayout's real Bone Warren output (10 walls in rows, 2 pillars) for a fixed seed.
## Run: godot --headless --path . --script tests/maps/crowd_bone_warren.gd

const ENEMIES := 300
const FRAMES := 180
const BUDGET_MS := 12.0  # the same mean limit as crowd_performance.gd
const ObstacleMapT := preload("res://scripts/maps/obstacle_map.gd")
const MapLayoutT := preload("res://scripts/maps/map_layout.gd")
const MapBuilderT := preload("res://scripts/maps/map_builder.gd")
const MapRegistryT := preload("res://scripts/maps/map_registry.gd")

var _failed := false


## MapLayout's real Bone Warren output for a fixed seed: [walls, pillars].
func _dense_layout() -> Array:
	var layout = MapLayoutT.generate(MapRegistryT.by_id(&"bone_warren"), 12345, Vector2(Arena.RUN_SIZE))
	return [layout.walls, layout.pillars]


func _run(F: GDScript, with_obstacles: bool, moving: bool) -> Array:
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	for n in main.get_children():
		if n.is_in_group(&"obstacles"):
			n.remove_from_group(&"obstacles")
			main.remove_child(n)
			n.free()
	for n in main.get_node("World/Props").get_children():
		n.free()
	var layout := _dense_layout()
	var walls: Array[Rect2] = layout[0] if with_obstacles else ([] as Array[Rect2])
	var pillars: Array[Vector2] = layout[1] if with_obstacles else ([] as Array[Vector2])
	for r in walls:
		var w := CaveWall.new()
		main.get_node("World/Props").add_child(w)
		w.setup(r)
	var map := ObstacleMapT.new()
	map.setup(walls, pillars, Vector2(Arena.RUN_SIZE), MapBuilderT.playable_rect(Vector2(Arena.RUN_SIZE), 16.0))
	main.add_child(map)
	main.spawn_director.obstacles = map
	var p = F.player()
	p.hurtbox.invulnerable = true
	p.caster.set_physics_process(false)
	var centre: Vector2 = p.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in ENEMIES:
		var type: String = ["grunt", "grunt", "ranged", "dasher"][i % 4]
		F.spawn_enemy(main, type, centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 160), 1000.0)
	await F.seconds(self, 1.0)
	var total := 0.0
	var worst := 0.0
	for i in FRAMES:
		if moving:  # a circle of radius 120, one lap in 3 s (about 250 px/s: faster than any enemy)
			p.global_position = centre + Vector2.from_angle(i / 60.0 / 3.0 * TAU) * 120.0
		await physics_frame
		var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total += ms
		worst = maxf(worst, ms)
	var searches: int = map.searches_started
	var max_exp: int = map.max_frame_expansions
	main.queue_free()
	await F.frames(self, 3)
	return [total / FRAMES, worst, searches, max_exp]


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	for moving in [false, true]:
		var label := "moving" if moving else "stationary"
		var with: Array = await _run(F, true, moving)
		var without: Array = await _run(F, false, moving)
		print("%s Player: with obstacles mean %.2f ms worst %.2f ms (%d searches, max %d expansions/frame); without: mean %.2f ms worst %.2f ms"
			% [label, with[0], with[1], with[2], with[3], without[0], without[1]])
		if with[0] > BUDGET_MS:
			_failed = true
			print("FAIL: %s mean physics time %.2f ms is over %.1f ms" % [label, with[0], BUDGET_MS])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

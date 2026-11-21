extends SceneTree
## Walking the whole route (spec 1.6): a scripted walk along the 841 main-path points (interpolated, steps of 60 px; the 107,568 px route
## takes about 1,800 to 2,500 of them) keeps streaming chunks with no frame building more than one or freeing more than two, the loaded
## chunk and node counts stay bounded, and the chunk under the focus always ends up loaded. It asserts counts, not frame times
## (headless timing is noisy).
## Run: godot --headless --path . --script tests/overworld/overworld_walk.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const RulesS := preload("res://scripts/overworld/overworld_rules.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var w = WorldDataS.shared()
	var holder := Node2D.new()
	root.add_child(holder)
	var terrain = load("res://scripts/overworld/world_terrain.gd").new()
	holder.add_child(terrain)
	terrain.setup(w)
	# The path in world px, every 8 tiles, walked in steps of 60 px.
	var points: Array[Vector2] = []
	for p in w.main_path:
		points.append(WorldDataS.world_of(p))
	var steps := 0
	var most_builds := 0
	var most_frees := 0
	var most_chunks := 0
	var most_nodes := 0
	var behind := 0
	var prev: Array = []
	var pos := points[0]
	for i in range(1, points.size()):
		var target := points[i]
		while pos.distance_to(target) > 1.0:
			pos = pos.move_toward(target, 60.0)
			terrain.focus(pos)
			await physics_frame
			steps += 1
			var now: Array = terrain.loaded_chunks()
			var built := 0
			for c in now:
				if not prev.has(c):
					built += 1
			var freed := 0
			for c in prev:
				if not now.has(c):
					freed += 1
			most_builds = maxi(most_builds, built)
			most_frees = maxi(most_frees, freed)
			most_chunks = maxi(most_chunks, now.size())
			most_nodes = maxi(most_nodes, terrain.get_child_count())
			prev = now
			# A walk of 60 px per frame is far faster than the game's (1.5 px per frame): the chunk under the focus may lag.
	for i in 6:
		await physics_frame
	var here := Vector2i(int(pos.x) / 512, int(pos.y) / 512)
	_check(terrain.loaded_chunks().has(here), "the chunk under the focus is loaded at the end of the walk")
	_check(steps > 1500 and steps < 2700, "the walk took 1,800 to 2,500 steps (each 128 px segment is walked in whole 60 px steps): %d" % steps)
	_check(most_builds <= RulesS.BUILDS_PER_FRAME, "no frame built more than %d chunk (%d)" % [RulesS.BUILDS_PER_FRAME, most_builds])
	_check(most_frees <= RulesS.FREES_PER_FRAME, "no frame freed more than %d chunks (%d)" % [RulesS.FREES_PER_FRAME, most_frees])
	_check(most_chunks <= 40 and most_nodes <= 60, "the loaded chunks and nodes stay bounded (%d chunks, %d nodes)" % [most_chunks, most_nodes])
	_check(terrain.loaded_chunks().size() <= 25, "only chunks near the end remain (%d)" % terrain.loaded_chunks().size())
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

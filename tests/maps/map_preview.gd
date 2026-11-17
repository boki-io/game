extends SceneTree
## The map preview scene (spec 0.6, 3.6): it loads, builds each of the eight maps through MapBuilder (wall, pillar and
## decor counts equal the layout's), shows the three monster looks, survives Tab / R / L / O / Z and `walk`, and leaves
## GameSession alone. Rendering is not covered (tools/maps/shot_maps.gd renders it).
## Run: godot --headless --path . --script tests/maps/map_preview.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const Layout := preload("res://scripts/maps/map_layout.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	return e


func _init() -> void:
	await process_frame  # the autoloads exist from here
	var session = root.get_node("GameSession")
	var stage_before = session.current_stage
	var seed_before = session.path_seed
	var scene: PackedScene = load("res://scenes/dev/map_preview.tscn")
	_check(scene != null, "the preview scene loads")
	var preview = scene.instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var themes: Array = Registry.all()
	_check(preview.map != null and preview.map.id == themes[0].id, "an empty map shows the first map")
	var size := Vector2(1600, 896)
	for i in themes.size():
		var theme = themes[i]
		preview.show_map(theme, 3 + i)
		await process_frame
		var layout = Layout.generate(theme, 3 + i, size)
		var tag := "[%s] " % theme.id
		_check(preview.get_node("World/Props").get_child_count() == layout.walls.size() + layout.pillars.size() + layout.props.size(), tag + "wall, pillar and prop count")
		_check(preview.get_node("World/Decor").get_child_count() == layout.decor.size(), tag + "decor count")
		var monsters: Node = preview.get_node("World/Enemies")
		_check(monsters.get_child_count() == 3, tag + "three monsters")
		for m in monsters.get_children():
			var v = theme.variant_for(m.data.id)
			_check(v != null and m.sprite.body_color == v.body_color and m.sprite.mark == int(v.mark), tag + "%s wears the map's variant" % m.data.id)
		_check(preview._targets.obstacles != null and preview._targets.obstacles.has_obstacles(), tag + "an ObstacleMap exists")
		_check(preview.get_node("World").get_children().filter(func(n): return n.name == &"Ambience").size() == (1 if theme.ambience_kind != 0 and theme.ambience_count > 0 else 0), tag + "the workbench has one Ambience, not one per rebuild")
	# Keys: Tab goes to the next map, R changes the seed, L reloads from disk, O and Z toggle.
	var before: String = preview.map.id
	preview._unhandled_key_input(_key(KEY_TAB))
	_check(preview.map.id == themes[(themes.map(func(t): return t.id).find(before) + 1) % themes.size()].id, "Tab shows the next map")
	var old_seed: int = preview.seed
	preview._unhandled_key_input(_key(KEY_R))
	_check(preview.seed >= 0, "R sets a seed (was %d)" % old_seed)
	var id: String = preview.map.id
	preview._unhandled_key_input(_key(KEY_L))
	_check(preview.map != null and preview.map.id == id, "L reloads the same map from disk")
	preview._unhandled_key_input(_key(KEY_O))
	await process_frame
	_check(preview.overlay_on and preview._flow != null and preview._flow.has_field(), "O turns the overlay and a flow field on")
	preview._unhandled_key_input(_key(KEY_Z))
	_check(preview.zoomed_out and preview._camera.zoom.x < 1.0, "Z zooms out to the whole arena")
	# walk: a Player is added and the flow field starts at it
	preview.walk = true
	preview.rebuild()
	await process_frame
	_check(preview.get_node("World/Players").get_child_count() == 1, "walk adds one Player")
	preview.walk = false
	preview.rebuild()
	_check(preview.get_node("World/Players").get_child_count() == 0, "no walk, no Player")
	_check(session.current_stage == stage_before and session.path_seed == seed_before, "GameSession untouched")
	preview.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

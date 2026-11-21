extends SceneTree
## The overworld's markers (spec 1.6): all 108 exist where the map puts them with the right kinds, the prompt per kind (and
## " (cleared)"), the interaction radius and the lockout, a checkpoint lights once (respawn, saved, healed, banner), the start
## camp starts lit, caves and dungeons enter the arena run, specials only show their name, camps, caches, arenas and gates do
## nothing, and a gate is open (lock hook false) while a test-only locked gate blocks a body.
## Run: godot --headless --path . --script tests/overworld/markers.gd

const SG := preload("res://scripts/systems/save_game.gd")
const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const JSave := preload("res://scripts/overworld/journey_save.gd")
const RulesS := preload("res://scripts/overworld/overworld_rules.gd")

var _failed := false
var _gs: Node
var _base := ""
var _w


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame
	await process_frame


func _clean() -> void:
	for who in ["knight", "wizard", "archer"]:
		for suffix in ["", ".tmp", ".bad"]:
			DirAccess.remove_absolute("%s.journey.%s%s" % [_base, who, suffix])
	for suffix in ["", ".tmp", ".bad", ".inventory"]:
		DirAccess.remove_absolute(_base + suffix)


func _load(prep := Callable()):
	_gs.character = CharacterRegistry.all()[0]
	_gs.journey = JSave.load_for(_gs.character.id, _w)
	if prep.is_valid():
		prep.call(_gs.journey)
	var ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	current_scene = ow
	await _frames(3)
	return ow


func _unload(ow) -> void:
	ow.queue_free()
	await process_frame
	paused = false


func _of_kind(ow, kind: String) -> Array:
	return ow.markers.filter(func(m): return String(m.kind) == kind)


## Stands the player at `m` and waits for the overworld to notice, with the F lockout over.
func _stand_at(ow, m) -> void:
	ow.player.global_position = m.position
	ow._lockout = 0.0
	await _frames(3)


func _init() -> void:
	await process_frame
	await process_frame
	_gs = root.get_node("GameSession")
	_w = WorldDataS.shared()
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_markers_test_%d.json" % OS.get_process_id())
	_clean()
	SG.override_path = _base
	_gs.inventory.set_state([], {})
	await _placement()
	await _checkpoints()
	await _entrances()
	await _inert_and_gates()
	_gs.journey = null
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _placement() -> void:
	var ow = await _load()
	_check(ow.markers.size() == 108, "108 markers")
	for i in ow.markers.size():
		var m = ow.markers[i]
		var d: Dictionary = _w.markers[i]
		_check(m.position == _w.marker_world(d) and String(m.kind) == d.kind and m.index == i, "marker %d (%s) is at its world position with its kind" % [i, d.name])
	var start = _of_kind(ow, "start_camp")[0]
	_check(start.lit and start.prompt_text() == "F: Rest here (lit)", "the start camp starts lit")
	var cp = _of_kind(ow, "checkpoint")[0]
	_check(not cp.lit and cp.prompt_text() == "F: Rest here", "a checkpoint starts dark")
	var cave = _of_kind(ow, "cave")[0]
	_check(cave.prompt_text() == "F: Enter %s" % cave.data.name, "a cave's prompt: %s" % cave.prompt_text())
	cave.set_cleared(true)
	_check(cave.prompt_text() == "F: Enter %s (cleared)" % cave.data.name, "a cleared cave says so")
	_check(_of_kind(ow, "dungeon")[0].prompt_text().begins_with("F: Enter ") and _of_kind(ow, "final_dungeon")[0].prompt_text().begins_with("F: Enter "), "dungeons and the final vault can be entered")
	_check(_of_kind(ow, "special")[0].prompt_text() == "F: Examine", "a special says Examine")
	for kind in ["camp", "cache", "arena", "gate"]:
		var m = _of_kind(ow, kind)[0]
		_check(not m.is_interactive() and m.prompt_text() == "", "a %s has no prompt and is not interactive" % kind)
	_check(_of_kind(ow, "cave").size() == 18 and _of_kind(ow, "checkpoint").size() == 16 and _of_kind(ow, "gate").size() == 7, "the kinds are counted")
	await _unload(ow)


func _checkpoints() -> void:
	var ow = await _load()
	var cp = _of_kind(ow, "checkpoint")[0]
	# Out of range: nothing to use.
	ow.player.global_position = cp.position + Vector2(RulesS.INTERACT_RADIUS + 30.0, 0)
	await _frames(3)
	_check(ow.target != cp and not ow.prompt.visible, "outside the radius there is no prompt")
	await _stand_at(ow, cp)
	_check(ow.target == cp and ow.prompt.visible and ow.prompt.text == "F: Rest here", "inside the radius the prompt reads F: Rest here (%s)" % ow.prompt.text)
	_check(cp.show_name, "the name shows when the player is close")
	ow.player.health.take_damage(40.0)
	_check(ow.player.health.current < ow.player.health.max_health, "the player is hurt before resting")
	# The lockout: F right after a load does nothing.
	ow._lockout = 0.2
	await _press(&"interact")
	_check(not cp.lit, "F inside the lockout does nothing")
	ow._lockout = 0.0
	await _press(&"interact")
	_check(cp.lit and ow.journey.respawn == cp.data.name and ow.journey.checkpoints.has(cp.data.name), "F lights the checkpoint and makes it the respawn")
	_check(is_equal_approx(ow.player.health.current, ow.player.health.max_health), "resting heals the player")
	_check(ow.banner.visible and ow.banner.text == "Checkpoint reached", "the banner says Checkpoint reached (%s)" % ow.banner.text)
	_check(JSave.load_for(_gs.character.id, _w).respawn == cp.data.name, "the journey was saved with the new respawn")
	var count: int = ow.journey.checkpoints.size()
	ow._lockout = 0.0
	await _press(&"interact")
	_check(ow.journey.checkpoints.size() == count and ow.banner.text == "Rested", "a second rest lights nothing new (%s)" % ow.banner.text)
	# The prompt hides while the world map is open.
	ow.world_map.open()
	await _frames(2)
	_check(not ow.prompt.visible, "the prompt is hidden while the world map is open")
	ow.world_map.close()
	await _unload(ow)
	# A saved lit checkpoint is lit on the next visit.
	ow = await _load()
	_check(_of_kind(ow, "checkpoint")[0].lit, "a lit checkpoint is still lit after re-entering")
	await _unload(ow)


func _entrances() -> void:
	var visited := []
	_gs.scene_hook = func(path: String) -> void: visited.append(path)
	var cave_name: String = _w.markers.filter(func(m): return m.kind == "cave")[0].name
	var ow = await _load(func(j): j.mark_cleared(cave_name))
	var cave = _of_kind(ow, "cave")[0]
	_check(cave.cleared and cave.prompt_text().ends_with("(cleared)"), "a cleared cave shows (cleared) after loading the journey")
	await _stand_at(ow, cave)
	await _press(&"interact")
	_check(visited == [_gs.RUN] and _gs.dungeon != null and _gs.dungeon.marker.name == cave.data.name, "F at a cave enters it as an arena run (%s)" % [visited])
	_check(_gs.dungeon.stages.size() == 1, "a cave is one stage")
	_gs.dungeon = null
	_gs.current_stage = null
	await _unload(ow)
	visited.clear()
	ow = await _load()
	var dungeon = _of_kind(ow, "dungeon")[0]
	await _stand_at(ow, dungeon)
	await _press(&"interact")
	_check(visited == [_gs.RUN] and _gs.dungeon.stages.size() == 3, "F at a dungeon enters three stages")
	_gs.dungeon = null
	_gs.current_stage = null
	await _unload(ow)
	_gs.scene_hook = Callable()


func _inert_and_gates() -> void:
	var visited := []
	_gs.scene_hook = func(path: String) -> void: visited.append(path)
	var ow = await _load()
	var special = _of_kind(ow, "special")[0]
	await _stand_at(ow, special)
	var before: Array = ow.journey.checkpoints.duplicate()
	await _press(&"interact")
	_check(ow.banner.visible and ow.banner.text == "%s (%s)" % [special.data.name, special.data.subtype], "a special shows its name and type (%s)" % ow.banner.text)
	_check(ow.journey.checkpoints == before and visited.is_empty(), "a special changes nothing")
	for kind in ["camp", "cache", "gate"]:
		var m = _of_kind(ow, kind)[0]
		await _stand_at(ow, m)
		await _press(&"interact")
		_check(ow.target == null or ow.target == _nearest_interactive(ow, m), "standing on a %s targets nothing of its own" % kind)
	_check(visited.is_empty(), "camps, caches and gates start nothing")
	# Every gate is open.
	for g in _of_kind(ow, "gate"):
		_check(not RulesS.gate_locked(g.data.name) and ow.journey.gate_open(g.data.name) and not g.locked, "gate %s is open" % g.data.name)
	# A test-only locked gate blocks a body; open it lets the body through.
	var gate = _of_kind(ow, "gate")[0]
	var axis: Vector2 = gate._axis()
	var perp := Vector2(-axis.y, axis.x)
	for locked in [false, true]:
		gate.set_locked(locked)
		await _frames(2)
		var body := CharacterBody2D.new()
		body.collision_layer = 2
		body.collision_mask = 1
		var shape := CircleShape2D.new()
		shape.radius = 5.0
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)
		ow.get_node("World").add_child(body)
		body.global_position = gate.position - perp * 50.0
		for i in 150:
			body.move_and_collide(perp * 150.0 / 60.0)
			await physics_frame
		var crossed: bool = (body.global_position - gate.position).dot(perp) > 0.0
		_check(crossed == not locked, "a %s gate %s a body" % ["locked" if locked else "open", "blocks" if locked else "lets through"])
		_check((gate._barrier != null) == locked, "the barrier exists only while locked")
		body.queue_free()
	await _unload(ow)
	_gs.scene_hook = Callable()


func _nearest_interactive(ow, m):
	var best = null
	var best_d := RulesS.INTERACT_RADIUS
	for o in ow.markers:
		if o.is_interactive() and o.position.distance_to(m.position) < best_d:
			best_d = o.position.distance_to(m.position)
			best = o
	return best

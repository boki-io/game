extends SceneTree
## The overworld scene (spec 1.6): it loads for a character with their journey (a new one at the lit start camp), the player
## stands there with the progress restored (and a legendary's granted relic, which a journey never keeps), the camera and terrain
## follow, the scene has the nodes abilities need, Return to Hub saves and leaves, the periodic save, another character gets
## their own journey, and the old stage-select path still works.
## Run: godot --headless --path . --script tests/overworld/overworld_scene.gd

const SG := preload("res://scripts/systems/save_game.gd")
const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const JSave := preload("res://scripts/overworld/journey_save.gd")

var _failed := false
var _gs: Node
var _base := ""
var _scenes: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _character(id: StringName):
	for c in CharacterRegistry.all():
		if c.id == id:
			return c
	return null


func _clean() -> void:
	for who in ["knight", "wizard", "archer"]:
		for suffix in ["", ".tmp", ".bad"]:
			DirAccess.remove_absolute("%s.journey.%s%s" % [_base, who, suffix])
	for suffix in ["", ".tmp", ".bad", ".inventory"]:
		DirAccess.remove_absolute(_base + suffix)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## A fresh overworld for `id` with the journey `prep` (a Callable taking the Journey) adjusted first.
func _load(id: StringName, prep := Callable()):
	var w = WorldDataS.shared()
	_gs.character = _character(id)
	_gs.journey = JSave.load_for(id, w)
	if prep.is_valid():
		prep.call(_gs.journey)
	var ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	current_scene = ow
	_scenes.append(ow)
	await _frames(3)
	return ow


func _unload(ow) -> void:
	ow.queue_free()
	_scenes.erase(ow)
	await process_frame
	paused = false


func _init() -> void:
	await process_frame
	await process_frame
	_gs = root.get_node("GameSession")
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_overworld_test_%d.json" % OS.get_process_id())
	_clean()
	SG.override_path = _base
	_gs.inventory.set_state([], {})
	await _basics()
	await _progress_and_relic()
	await _leaving_and_saving()
	await _characters_and_old_path()
	_gs.inventory.set_state([], {})
	_gs.journey = null
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _basics() -> void:
	var w = WorldDataS.shared()
	var ow = await _load(&"knight")
	var start = w.start_marker()
	_check(ow.player != null and ow.player.global_position.distance_to(w.marker_world(start)) < 2.0, "a new journey stands at the start camp (%s)" % [ow.player.global_position])
	_check(not ow.player.hub_mode, "the overworld player is not in hub mode (mana is limited, relics work)")
	_check(ow.journey.respawn == start.name and ow.journey.checkpoints == [start.name], "the journey starts with the start camp lit")
	var cam = ow.get_node("Camera")
	_check(cam.limit_right == 32000 and cam.limit_bottom == 32000, "the camera limits are the world (%d, %d)" % [cam.limit_right, cam.limit_bottom])
	_check(ow.get_node("Arena").visible == false and ow.get_node("Arena").get_child_count() > 0, "the arena's debug border is hidden but its walls stay")
	_check(ow.get_node("World/Effects").is_in_group(&"effects") and ow.get_node("World/PlayerProjectiles").is_in_group(&"player_projectiles") and ow.get_node("World/Zones") != null, "the nodes abilities need exist (Effects, Zones, PlayerProjectiles)")
	await _frames(12)
	_check(ow.terrain.loaded_chunks().size() >= 4, "the chunks around the player stream in (%d)" % ow.terrain.loaded_chunks().size())
	_check(ow.markers.size() == 108, "108 markers are created")
	# The player walks and the terrain follows.
	var chunk_before: Array = ow.terrain.loaded_chunks().duplicate()
	var far: Vector2 = w.marker_world(w.markers.filter(func(m): return m.kind == "checkpoint")[3])
	ow.player.global_position = far
	await _frames(30)
	_check(ow.terrain.loaded_chunks() != chunk_before and ow.terrain.chunk_node(Vector2i(int(far.x / 512), int(far.y / 512))) != null, "the terrain follows the player to a far checkpoint")
	_check(ow.fog.is_revealed_world(far), "the fog is revealed around the player")
	await _unload(ow)


func _progress_and_relic() -> void:
	var w = WorldDataS.shared()
	var knight = _character(&"knight")
	var upgrade = knight.upgrade_pool[0]
	var ow = await _load(&"knight", func(j): j.progress = {level = 5, xp = 3, upgrades = {upgrade.id: 1}, relics = {&"storm_orbs": 2}})
	_check(ow.player.xp.level == 5 and ow.player.xp.xp == 3, "the journey's level and XP are restored (%d, %d)" % [ow.player.xp.level, ow.player.xp.xp])
	_check(ow.player.upgrades.levels.get(upgrade.id, 0) == 1, "an upgrade is restored")
	_check(ow.player.relics.level_of(RelicRegistry.find(&"storm_orbs")) == 2, "a relic is restored at its level")
	await _unload(ow)
	# A worn legendary's relic is granted in the overworld and never written into the journey.
	_gs.inventory.set_state([&"emberstep_boots"], {&"knight": {&"shoes": &"emberstep_boots"}})
	ow = await _load(&"knight")
	var trail = RelicRegistry.find(&"fire_trail")
	_check(ow.player.relics.level_of(trail) == 1 and &"fire_trail" in ow.player.relics.granted, "a worn legendary's relic is granted in the overworld")
	ow.save_now()
	_check(not JSave.load_for(&"knight", w).progress.relics.has(&"fire_trail") and not ow.journey.progress.relics.has(&"fire_trail"), "the granted relic is not written into the journey")
	await _unload(ow)
	_gs.inventory.set_state([&"emberstep_boots"], {})  # taken off in the hub
	ow = await _load(&"knight")
	_check(ow.player.relics.level_of(trail) == 0, "after taking the item off and re-entering there is no relic")
	await _unload(ow)
	_gs.inventory.set_state([], {})


func _leaving_and_saving() -> void:
	var w = WorldDataS.shared()
	var visited := []
	_gs.scene_hook = func(path: String) -> void: visited.append(path)
	var ow = await _load(&"knight")
	var file := JSave.path(&"knight")
	DirAccess.remove_absolute(file)
	_check(not FileAccess.file_exists(file), "nothing is written until a save")
	# The periodic save: 30 s and at least 100 px of movement.
	ow.player.global_position += Vector2(160, 0)
	ow._save_timer = 29.99
	await _frames(4)
	_check(FileAccess.file_exists(file), "the periodic save writes the journey after 30 s and 100 px of movement")
	# Return to Hub saves and changes to the hub.
	ow.player.global_position += Vector2(40, 0)
	var spot: Vector2 = ow.player.global_position
	ow.pause_menu.return_to_hub_requested.emit()
	_check(visited == [_gs.HUB], "Return to Hub changes to the hub (%s)" % [visited])
	_check(JSave.load_for(&"knight", w).position.distance_to(spot) < 2.0, "and saves the position")
	_gs.scene_hook = Callable()
	await _unload(ow)


func _characters_and_old_path() -> void:
	var visited := []
	_gs.scene_hook = func(path: String) -> void: visited.append(path)
	_gs.enter_overworld(_character(&"knight"))
	_check(visited == [_gs.OVERWORLD] and _gs.journey.character_id == &"knight" and _gs.last_character.id == &"knight", "enter_overworld loads the journey and goes to the overworld")
	_gs.journey.position += Vector2(48, 0)
	_gs.save_journey()
	_gs.enter_overworld(_character(&"wizard"))
	_check(_gs.journey.character_id == &"wizard" and _gs.last_character.id == &"wizard", "another character gets their own journey and becomes the last character")
	_check(_gs.journey.position.distance_to(WorldDataS.marker_world(WorldDataS.shared().start_marker())) < 2.0, "the Wizard starts at the start camp, not where the Knight stands")
	# The old stage select still works from the code.
	visited.clear()
	_gs.start_run(_character(&"knight"))
	_check(visited == [_gs.SELECT] and _gs.path != null, "the old path-based run still opens the select screen")
	_gs.path = null
	_gs.scene_hook = Callable()

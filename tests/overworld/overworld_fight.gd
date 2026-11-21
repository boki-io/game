extends SceneTree
## Fighting in the overworld (spec 1.8, sections 7 and 8), with the hordes switched off: the scene has its enemy, projectile,
## pickup, obstacle and level-up nodes; a plain Enemy killed near the hero drops a gem that gives XP; gems and coins fade and
## free after the pool's lifetime, and a pop never ends in a wall; a level-up queues the menu; Exit and a rest bank the gold;
## a death respawns the hero at the last lit checkpoint with level and XP kept, full health, the gold banked and the journey saved.
## Run: godot --headless --path . --script tests/overworld/overworld_fight.gd

const SG := preload("res://scripts/systems/save_game.gd")
const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const JSave := preload("res://scripts/overworld/journey_save.gd")

var _failed := false
var _gs: Node
var _base := ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _clean() -> void:
	for who in ["knight", "wizard", "archer"]:
		for suffix in ["", ".tmp", ".bad"]:
			DirAccess.remove_absolute("%s.journey.%s%s" % [_base, who, suffix])
	for suffix in ["", ".tmp", ".bad", ".inventory"]:
		DirAccess.remove_absolute(_base + suffix)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _load(prep := Callable()):
	var w = WorldDataS.shared()
	for c in CharacterRegistry.all():
		if c.id == &"knight":
			_gs.character = c
	_gs.journey = JSave.load_for(&"knight", w)
	if prep.is_valid():
		prep.call(_gs.journey)
	var ow = load("res://scenes/overworld.tscn").instantiate()
	ow.hordes_enabled = false
	root.add_child(ow)
	current_scene = ow
	await _frames(3)
	return ow


func _unload(ow) -> void:
	ow.queue_free()
	await process_frame
	paused = false


func _enemy(ow, pos: Vector2):
	var e = load("res://scenes/enemy.tscn").instantiate()
	e.data = load("res://content/enemies/grunt.tres")
	ow.get_node("World/Enemies").add_child(e)
	e.activate(pos, 1.0)
	e.died.connect(func(dead) -> void: ow.pickups.spawn_gem(dead.global_position, 3))
	return e


func _init() -> void:
	await process_frame
	await process_frame
	_gs = root.get_node("GameSession")
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_overworld_fight_%d.json" % OS.get_process_id())
	_clean()
	SG.override_path = _base
	_gs.inventory.set_state([], {})
	await _nodes_and_kill()
	await _pickups()
	await _level_up_and_banking()
	await _death()
	_gs.inventory.set_state([], {})
	_gs.journey = null
	_gs.run_gold = 0
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _nodes_and_kill() -> void:
	var ow = await _load()
	for path in ["World/Enemies", "World/Projectiles", "Pickups", "WorldObstacles", "UI/LevelUpMenu"]:
		_check(ow.has_node(path), "the scene has %s" % path)
	_check(ow.get_node("World/Enemies").y_sort_enabled, "the enemies are y-sorted")
	_check(ow.get_node("World/Projectiles").projectile_scene != null, "the enemy shot pool has its scene")
	_check(ow.pickups.pickup_lifetime == 60.0 and ow.pickups.inventory == _gs.inventory, "the pickups live 60 s and know the inventory")
	_check(ow.get_node("WorldObstacles").is_in_group(&"obstacles") and ow.get_node("WorldObstacles").has_obstacles(), "the world's obstacle map is in the obstacles group")
	_check(ow.pause_menu.level_up_menu == ow.level_up_menu, "the pause menu knows the level-up menu")
	var e = _enemy(ow, ow.player.global_position + Vector2(40, 0))
	_check(e.obstacles == ow.obstacles, "an enemy finds the world's obstacle map")
	e.take_damage(100000.0)
	await _frames(2)
	var gems := 0
	for c in ow.pickups.get_children():
		if c.get_script().get_global_name() == &"XPGem" and c.visible:
			gems += 1
			c.attract(ow.player)
	_check(gems == 1, "a killed enemy leaves one gem (%d)" % gems)
	var xp_before: int = ow.player.xp.xp + ow.player.xp.level * 1000
	await _frames(120)
	_check(ow.player.xp.xp + ow.player.xp.level * 1000 > xp_before, "the hero collects the gem and gains XP")
	await _unload(ow)


func _pickups() -> void:
	var ow = await _load()
	var p = ow.pickups
	_check(p.walkable.is_valid(), "the overworld sets a walkable check on the pickups")
	# A pop that would end in a wall stops where it was.
	var item := Node2D.new()
	ow.add_child(item)
	item.global_position = ow.player.global_position
	var vel: Vector2 = p.pop_step(item, Vector2(100, 0), 0.1, func(_pos: Vector2) -> bool: return false)
	_check(vel == Vector2.ZERO and item.global_position == ow.player.global_position, "a pop onto a rejected position is undone and ends")
	item.queue_free()
	# Coins expire.
	p.spawn_coin(ow.player.global_position + Vector2(300, 0))
	var coin = null
	for c in p.get_children():
		if c.get_script().get_global_name() == &"Coin":
			coin = c
	_check(coin != null and coin.visible, "a coin is on the ground")
	await _frames(30)
	coin._age = 59.0
	await _frames(2)
	_check(coin.modulate.a < 1.0, "a coin fades before its lifetime ends (%f)" % coin.modulate.a)
	coin._age = 59.99
	await _frames(2)
	_check(not coin.visible, "a coin is freed after the lifetime")
	_check(p.life_alpha(10.0, 0.0) == 1.0 and p.life_alpha(0.0, 60.0) == 1.0, "no lifetime or a new pickup is fully opaque")
	# The arena's pool has no lifetime.
	_check(load("res://scenes/main.tscn").instantiate().get_node("Pickups").pickup_lifetime == 0.0, "the arena's pickups never expire")
	await _unload(ow)


func _level_up_and_banking() -> void:
	var visited := []
	_gs.scene_hook = func(path: String) -> void: visited.append(path)
	var ow = await _load()
	var level: int = ow.player.xp.level
	ow.player.xp.add(ow.player.xp.needed())
	await _frames(2)
	_check(ow.player.xp.level == level + 1 and ow.level_up_menu.active and paused, "a level-up opens the level-up menu and pauses")
	ow.level_up_menu.dismiss()
	_check(not ow.level_up_menu.active and not paused, "dismissing it closes the menu and unpauses")
	# An item pickup shows the banner.
	_gs.inventory.set_state([], {})
	var any_id: StringName = ItemRegistry.all()[0].id
	ow.pickups.item_collected.emit(any_id)
	_check(ow.banner.visible and ow.banner.text.begins_with("Found: "), "taking an item shows the Found banner (%s)" % ow.banner.text)
	# Gold is banked by a rest and by Exit.
	var gold: int = _gs.gold
	_gs.run_gold = 5
	ow.show_banner("x")
	var camp = ow.markers.filter(func(m): return String(m.kind) == "start_camp")[0]
	ow._rest(camp)
	_check(_gs.gold == gold + 5 and _gs.run_gold == 0, "resting at a checkpoint banks the purse")
	# Exit and the window close both call save_now (Exit then quits the tree, so it is not called here).
	_gs.run_gold = 4
	ow.save_now()
	_check(_gs.gold == gold + 9 and _gs.run_gold == 0, "save_now banks the purse (Exit, window close)")
	# Entering a cave banks before the run starts.
	var cave = ow.markers.filter(func(m): return String(m.kind) == "cave")[0]
	_gs.run_gold = 6
	ow._enter(cave)
	_check(_gs.gold == gold + 15, "entering a cave banks the purse first (%d)" % (_gs.gold - gold))
	_gs.scene_hook = Callable()
	_gs.dungeon = null
	await _unload(ow)


func _death() -> void:
	var w = WorldDataS.shared()
	var cps: Array = w.markers.filter(func(m): return m.kind == "checkpoint")
	var lit: String = cps[2].name
	var ow = await _load(func(j):
		j.progress = {level = 4, xp = 2, upgrades = {}, relics = {}}
		j.activate_checkpoint(lit))
	var spot: Vector2 = w.marker_world(w.marker_named(lit))
	_check(ow.journey.respawn == lit, "the last lit checkpoint is the respawn")
	ow.player.global_position = ow.player.global_position + Vector2(200, 0)
	var gold: int = _gs.gold
	_gs.run_gold = 11
	DirAccess.remove_absolute(JSave.path(&"knight"))
	ow.player.health.take_damage(100000.0)
	_check(ow.player.dead, "the hero dies")
	await create_timer(0.5, true).timeout
	_check(ow.player.dead, "the hero lies there while the death plays")
	await create_timer(2.5, true).timeout
	await _frames(3)
	_check(not ow.player.dead, "the hero is alive again")
	_check(ow.player.global_position.distance_to(spot) < 2.0, "at the last lit checkpoint (%s vs %s)" % [ow.player.global_position, spot])
	_check(ow.player.health.current == ow.player.health.max_health, "with full health")
	_check(ow.player.xp.level == 4 and ow.player.xp.xp == 2, "level and XP are kept (%d, %d)" % [ow.player.xp.level, ow.player.xp.xp])
	_check(_gs.gold == gold + 11 and _gs.run_gold == 0, "the purse is banked")
	var saved = JSave.load_for(&"knight", w)
	_check(FileAccess.file_exists(JSave.path(&"knight")) and saved.position.distance_to(spot) < 2.0 and saved.progress.level == 4, "the journey is saved at the checkpoint")
	_check(not paused, "the game is not paused")
	await _unload(ow)

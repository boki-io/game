extends SceneTree
## Relic data, the PlayerRelics node and carrying relics between stages (spec 1.0, sections 3 and 7).
## Run: godot --headless --path . --script tests/relic_progress.gd

var _failed := false
var _gs: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_gs = root.get_node("GameSession")
	_gs.scene_hook = func(_path: String) -> void: pass
	var F: GDScript = load("res://tests/fixture.gd")
	var RP: GDScript = load("res://scripts/systems/run_progress.gd")

	# The five relics: data, level tables and the card text limits.
	var all := RelicRegistry.all()
	_check(all.size() == 5, "five relics in the registry")
	var ids: Array = all.map(func(r: RelicData) -> StringName: return r.id)
	_check(ids == [&"tidal_wave", &"frost_comet", &"thorn_nova", &"storm_orbs", &"fire_trail"], "relic ids in order")
	_check(RelicRegistry.find(&"storm_orbs").id == &"storm_orbs", "find by id")
	_check(RelicRegistry.find(&"nope") == null, "find an unknown id gives null")
	var glyphs := ""
	for r in all:
		glyphs += r.glyph
		_check(r.levels.size() == 3, "%s has 3 levels" % r.id)
		var probe: Node = r.behavior.new()
		_check(probe.has_method("params") and probe.has_method("cooldown_fraction"), "%s names a RelicBehavior script" % r.id)
		probe.free()
		for i in r.levels.size():
			var lines: PackedStringArray = r.levels[i].description.split("\n")
			_check(lines.size() <= 3, "%s level %d description is at most 3 lines" % [r.id, i + 1])
			for line in lines:
				_check(line.length() <= 20, "%s level %d line '%s' is short enough" % [r.id, i + 1, line])
	_check(glyphs == "WCTSF", "glyphs W C T S F")
	var wave := RelicRegistry.find(&"tidal_wave")
	_check(wave.levels[0].cooldown == 4.0 and wave.levels[1].width == 72 and wave.levels[2].returns == true, "tidal wave table")
	var comet := RelicRegistry.find(&"frost_comet")
	_check(comet.levels[2].comets == 2 and comet.levels[2].vulnerable == 1.5 and comet.levels[0].freeze == 1.0, "frost comet table")
	var nova := RelicRegistry.find(&"thorn_nova")
	_check(nova.levels[2].bramble_life == 4.0 and nova.levels[2].bramble_tick == 4 and nova.levels[0].thorns == 8, "thorn nova table")
	var orbs := RelicRegistry.find(&"storm_orbs")
	_check(orbs.levels[2].count == 5 and orbs.levels[2].zap_damage == 8 and orbs.levels[2].zap_range == 100, "storm orbs table")
	var trail := RelicRegistry.find(&"fire_trail")
	_check(trail.levels[2].ignite_dps == 4 and trail.levels[2].ignite_seconds == 3.0 and trail.levels[0].radius == 9, "fire trail table")

	# A run: add, raise, caps.
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var p = F.player()
	var rel = p.relics
	var changes := [0]
	var flashes: Array[int] = []
	rel.changed.connect(func() -> void: changes[0] += 1)
	rel.flashed.connect(func(slot: int) -> void: flashes.append(slot))
	_check(rel.levels.is_empty() and rel.free_slots() == 4, "a new player has no relics and 4 free slots")
	_check(rel.add_or_raise(wave), "a new relic is added")
	_check(rel.owns(&"tidal_wave") and rel.level_of(wave) == 1 and rel.free_slots() == 3, "level 1 in a slot")
	var b = rel.behavior_of(&"tidal_wave")
	_check(b.get_script().get_global_name() == &"TidalWave" and b.get_parent() == rel and b.level == 1 and b.player == p, "the behavior node is created")
	_check(b.params().cooldown == 4.0 and b.cooldown_fraction() == 0.0, "params of level 1; ready")
	_check(is_equal_approx(b.dmg(10.0), 10.0 * p.stats.value(&"damage", 1.0)), "dmg scales with the damage stat")
	F.upgrade(p, "damage")
	_check(is_equal_approx(b.dmg(10.0), 10.0 * p.stats.value(&"damage", 1.0)) and b.dmg(10.0) > 10.0, "dmg follows a damage upgrade")
	_check(rel.add_or_raise(wave) and rel.level_of(wave) == 2 and b.level == 2 and b.params().width == 72, "raise to 2 calls set_level")
	_check(rel.add_or_raise(wave) and rel.level_of(wave) == 3 and rel.behavior_of(&"tidal_wave") == b, "raise to 3 keeps the same node")
	_check(not rel.add_or_raise(wave) and rel.level_of(wave) == 3, "no raise past level 3")
	_check(changes[0] == 3 and flashes == [0, 0, 0], "changed and flashed fire on each change (%d, %s)" % [changes[0], flashes])
	_check(rel.add_or_raise(comet, false) and flashes.size() == 3 and changes[0] == 4, "flash false: changed only")
	_check(rel.add_or_raise(nova) and rel.add_or_raise(orbs), "four relics fit")
	_check(rel.free_slots() == 0 and rel.levels.size() == 4, "no free slot")
	_check(flashes[-1] == 3, "the 4th relic flashes slot 3")
	_check(not rel.add_or_raise(trail) and not rel.owns(&"fire_trail") and rel.levels.size() == 4, "no 5th relic")
	_check(rel.add_or_raise(comet) and rel.level_of(comet) == 2, "an owned relic can still be raised with full slots")
	_check(rel.levels.keys() == [&"tidal_wave", &"frost_comet", &"thorn_nova", &"storm_orbs"], "insertion order is slot order")

	# Behaviors stop while dead and resume.
	var cb = rel.behavior_of(&"frost_comet")
	p.dead = true
	await F.frames(self, 2)
	_check(cb.process_mode == Node.PROCESS_MODE_DISABLED, "behaviors stop while the player is dead")
	p.dead = false
	await F.frames(self, 2)
	_check(cb.process_mode == Node.PROCESS_MODE_INHERIT, "behaviors run again when alive")

	# Capture and restore keep ids, levels and order; an old snapshot still loads.
	var snap: Dictionary = RP.capture(p)
	_check(snap.relics == {&"tidal_wave": 3, &"frost_comet": 2, &"thorn_nova": 1, &"storm_orbs": 1}, "capture holds id -> level")
	_check(snap.relics.keys() == rel.levels.keys(), "capture keeps the slot order")
	snap.relics[&"tidal_wave"] = 99  # the snapshot is a copy
	_check(rel.level_of(wave) == 3, "capture duplicates the dictionary")
	snap.relics[&"tidal_wave"] = 3
	main.free()
	paused = false
	await process_frame

	main = F.start_run(self, &"knight")
	await F.frames(self, 2)
	p = F.player()
	var restore_flashes := [0]
	p.relics.flashed.connect(func(_s: int) -> void: restore_flashes[0] += 1)
	RP.restore(p, snap)
	_check(p.relics.levels == snap.relics and p.relics.levels.keys() == snap.relics.keys(), "restore: ids, levels and order")
	_check(restore_flashes[0] == 0, "restore does not flash")
	_check(p.relics.behavior_of(&"tidal_wave").level == 3 and p.relics.behavior_of(&"thorn_nova").get_script().get_global_name() == &"ThornNova", "restore: behaviors at their levels")
	_check(p.relics.free_slots() == 0 and p.relics.levels.size() == 4, "restore: slots used")
	main.free()
	paused = false
	await process_frame

	main = F.start_run(self, &"knight")
	await F.frames(self, 2)
	p = F.player()
	RP.restore(p, {level = 1, xp = 0, upgrades = {}})
	_check(p.relics.levels.is_empty(), "an old snapshot without relics loads")
	main.free()
	paused = false
	await process_frame

	# No relics in the hub.
	var hub_player: Node = load("res://scenes/player.tscn").instantiate()
	hub_player.hub_mode = true
	root.add_child(hub_player)
	await process_frame
	_check(not hub_player.relics.add_or_raise(wave) and hub_player.relics.levels.is_empty(), "no relics for a hub player")
	hub_player.free()

	_gs.scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## Caves and dungeons as arena stages (spec 1.6, sections 8 and 10): DungeonRules' stages (a table of expected modifiers),
## is_last_stage per stage, the marker-fixed seeds, progress carried into the journey and saved, a win marking the marker cleared
## and returning below it, death and abandon keeping the last cleared stage's progress, re-entering a cleared marker, a granted
## relic kept out of the journey, the end screen, pause and HUD wording, and the old path-based run untouched.
## Run: godot --headless --path . --script tests/overworld/dungeon_flow.gd

const SG := preload("res://scripts/systems/save_game.gd")
const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const JSave := preload("res://scripts/overworld/journey_save.gd")
const Rules := preload("res://scripts/overworld/dungeon_rules.gd")

var _failed := false
var _gs: Node
var _fader: Node
var _F: GDScript
var _loaded: Array[String] = []
var _base := ""
var _world


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


func _marker(kind: String, zone: int = -1) -> Dictionary:
	for m in _world.markers:
		if m.kind == kind and (zone < 0 or m.zone == zone):
			return m
	return {}


func _texts(node: Node) -> String:
	var text := ""
	for l in node.find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


func _buttons(node: Node) -> Array:
	return node.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)


## A fresh journey for the knight, then `marker` entered; returns the run scene (clock stopped, spawner off).
func _enter(marker: Dictionary, fresh := true) -> Node:
	if fresh:
		_gs.enter_overworld(CharacterRegistry.all()[0])
	_loaded.clear()
	_gs.enter_dungeon(marker)
	return _F.start_run(self, _gs.character.id)


func _drop(main: Node) -> void:
	main.free()
	paused = false
	_loaded.clear()
	await process_frame


func _init() -> void:
	await process_frame
	await process_frame
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_dungeon_test_%d.json" % OS.get_process_id())
	_clean()
	SG.override_path = _base
	_gs = root.get_node("GameSession")
	_fader = root.get_node("SceneFader")
	_F = load("res://tests/fixture.gd")
	_world = WorldDataS.shared()
	_gs.scene_hook = func(p: String) -> void: _loaded.append(p)
	for i in 200:
		if not _fader.busy:
			break
		await physics_frame
	var knight: CharacterData = CharacterRegistry.all()[0]
	var rules: Resource = load("res://content/overworld/dungeon_rules.tres")
	_check(rules != null and rules.max_population == 60, "dungeon_rules.tres loads")

	# --- DungeonRules: the stages. Expected values by hand from the formula (midpoints of PathGenerator.RANGES, integer
	# division toward zero): easy pop -15 diff -7 exp -10 cur -2; normal 0 0 5 2; hard 15 7 22 15.
	var cave0 := _marker("cave", 0)
	var s: Array = Rules.stages_for(cave0, rules)
	_check(s.size() == 1 and s[0].name == cave0.name, "a cave is one stage, named as the marker")
	_check(s[0].theme != null and s[0].theme.id == &"mossy_hollow", "the cave is on its map_id's theme")
	_check(s[0].tier == StageData.Tier.EASY and s[0].population == -15 and s[0].difficulty == -7 and s[0].experience == -10
		and s[0].currency == -2, "zone 0 cave: easy tier midpoints")
	var cave3 := _marker("cave", 3)
	if not cave3.is_empty():
		s = Rules.stages_for(cave3, rules)
		# zone 3, normal: pop 0 + 4*3, diff 0 + 3*3, exp 5 + 9, cur 2 + 6
		_check(s[0].tier == StageData.Tier.NORMAL and s[0].population == 12 and s[0].difficulty == 9 and s[0].experience == 14
			and s[0].currency == 8, "zone 3 cave: %s" % [[s[0].population, s[0].difficulty, s[0].experience, s[0].currency]])
	s = Rules.stages_for(_marker("dungeon", 0), rules)
	_check(s.size() == 3 and s[2].name.ends_with(" - stage 3") and s[0].name.ends_with(" - stage 1"), "a dungeon has three named stages")
	_check(s[0].tier == StageData.Tier.NORMAL, "a zone 0 dungeon is one tier up")
	_check([s[0].population, s[1].population, s[2].population] == [10, 18, 26], "zone 0 dungeon population steps +8 from the bonus +10")
	_check([s[0].difficulty, s[1].difficulty, s[2].difficulty] == [0, 8, 16], "zone 0 dungeon difficulty steps +8")
	_check(s[0].experience == 5 and s[2].experience == 5 and s[0].currency == 2 and s[2].currency == 2, "experience and currency do not step")
	s = Rules.stages_for(_marker("dungeon", 3), rules)
	_check(s[0].tier == StageData.Tier.HARD, "zone 3 dungeon: normal + 1 is hard")
	_check([s[0].population, s[1].population, s[2].population] == [37, 45, 53], "zone 3 dungeon population: %s" % [s.map(func(x): return x.population)])
	_check([s[0].difficulty, s[2].difficulty] == [16, 32] and s[0].experience == 31 and s[0].currency == 21, "zone 3 dungeon other modifiers")
	var vault := _marker("final_dungeon")
	s = Rules.stages_for(vault, rules)
	_check(s.size() == 3 and s[0].tier == StageData.Tier.HARD, "the final vault: three stages, hard (clamped)")
	_check([s[0].difficulty, s[1].difficulty, s[2].difficulty] == [28, 38, 48] and s[0].experience == 43 and s[0].currency == 29, "vault difficulty steps +10")
	for st in s:
		_check(st.population <= rules.max_population, "vault population %d never above the cap" % st.population)
	_check(s[2].population == 60, "the uncapped 83 is capped to 60")
	_check(s[0].theme.id == &"crystal_vault", "the vault is on the crystal vault map")

	# --- Entering: a cave is one stage with a marker-fixed seed.
	var main := await _enter(cave0)
	_check(_loaded == [_gs.RUN], "enter_dungeon loads the run scene")
	_check(_gs.dungeon != null and _gs.path == null and _gs.dungeon.stages.size() == 1 and _gs.current_stage == _gs.dungeon.stages[0],
		"a one-stage run, no path")
	_check(_gs.is_last_stage(), "the only stage of a cave is the last")
	var seed_a: int = _gs.map_seed()
	_check(seed_a == hash("%s|%d" % [cave0.name, 0]), "the seed is the marker name and stage index hash")
	_check(main.get_node("UI/Hud")._stage_text == cave0.name + " - stage 1 of 1", "HUD stage text: " + main.get_node("UI/Hud")._stage_text)
	var pause := main.get_node("UI/PauseMenu")
	_check(_buttons(pause).has("Leave the dungeon") and not _buttons(pause).has("Return to Hub"), "pause menu says Leave the dungeon")
	_check("Leave the dungeon?" in _texts(pause.get_node("AbandonPrompt")), "the abandon prompt says Leave the dungeon?")
	await _drop(main)
	main = await _enter(cave0, false)
	_check(_gs.map_seed() == seed_a, "the same seed on a second entry")
	await _drop(main)
	_gs.dungeon = null

	# --- A dungeon: is_last_stage per stage, the seeds differ, progress carries into the journey and saves.
	var dun := _marker("dungeon", 2)
	_gs.enter_overworld(knight)
	_gs.inventory.unlock(&"stormcaller_crown")
	_gs.inventory.equip(knight.id, &"stormcaller_crown")
	main = await _enter(dun, false)
	_check(_gs.dungeon.stages.size() == 3 and not _gs.is_last_stage(), "stage 1 of a dungeon is not the last")
	var seed_1: int = _gs.map_seed()
	var p = _F.player()
	_check(p.relics.granted.has(&"storm_orbs"), "the worn crown grants its relic")
	p.xp.add(8)  # opens the level-up menu
	await _F.frames(self, 3)
	var gained_level: int = p.xp.level
	_check(gained_level > 1, "the player levelled in stage 1")
	main.get_node("UI/LevelUpMenu").visible = false
	var carried: Dictionary = RunProgressProbe.capture_both(p)
	_check(carried.run.relics.has(&"storm_orbs"), "the between-stage run_progress has the granted relic")
	_check(not carried.journey.relics.has(&"storm_orbs"), "capture(player, false) leaves the granted relic out")
	_gs.run_gold = 5
	_loaded.clear()
	_gs.complete_stage()
	_check(_loaded == [_gs.RUN] and _gs.dungeon.index == 1 and _gs.current_stage == _gs.dungeon.stages[1], "stage 1 won: stage 2 loads")
	_check(_gs.run_progress.relics.has(&"storm_orbs") and _gs.run_progress.level == gained_level, "run_progress carries the relic and level")
	_check(_gs.journey.progress.level == gained_level and not _gs.journey.progress.relics.has(&"storm_orbs"), "the journey got the level, not the granted relic")
	var saved = JSave.load_for(knight.id, _world)
	_check(saved.progress.level == gained_level, "the journey was saved to its file")
	_check(not _gs.is_last_stage() and _gs.map_seed() != seed_1, "stage 2 is not the last and has another seed")
	await _drop(main)
	main = _F.start_run(self, knight.id)
	_check(_F.player().xp.level == gained_level, "stage 2 starts at the carried level")
	_check(main.get_node("UI/Hud")._stage_text == dun.name + " - stage 2 of 3", "HUD text of stage 2")
	_gs.complete_stage()
	_check(_gs.dungeon.index == 2 and _gs.is_last_stage(), "stage 3 is the last")
	await _drop(main)

	# Stage 3 won through the real flow: victory screen, finish_run, then the button.
	main = _F.start_run(self, knight.id)
	main.run_manager.running = true
	main.run_manager.elapsed = 299.9
	main.run_manager.kills = 9
	await _F.seconds(self, 0.4)
	var end: Control = main.get_node("UI/EndScreen")
	_check(end.visible and not main.get_node("UI/StageBanner").visible, "victory screen on the last stage, no banner")
	_check(_buttons(end) == ["Return to the world"], "victory button: %s" % [_buttons(end)])
	var text := _texts(end)
	_check(text.contains("Victory") and text.contains("3 of 3"), "victory text: " + text)
	_check(_gs.journey.is_cleared(dun.name), "the marker is cleared")
	_check(_gs.journey.position == _world.marker_world(dun) + Vector2(0, 40), "the journey stands below the marker")
	_check(_gs.dungeon != null, "the dungeon is kept until the button")
	var gold_before: int = _gs.gold
	_gs.run_gold = 11
	for b in end.find_children("*", "Button", true, false):
		b.pressed.emit()
	_check(_loaded == [_gs.OVERWORLD] and _gs.dungeon == null and _gs.current_stage == null, "the button returns to the overworld")
	_check(_gs.gold == gold_before + 11, "the gold is banked")
	saved = JSave.load_for(knight.id, _world)
	_check(saved.is_cleared(dun.name) and saved.position == _world.marker_world(dun) + Vector2(0, 40), "cleared and position saved")
	await _drop(main)

	# --- A cleared marker can be re-entered and stays cleared; death returns to the entrance, keeping the cleared progress.
	var level_saved: int = _gs.journey.progress.level
	main = await _enter(dun, false)
	_check(_gs.dungeon.index == 0 and _gs.journey.is_cleared(dun.name), "a cleared dungeon can be entered again")
	_check(_gs.run_progress.level == level_saved, "it starts from the journey's progress")
	p = _F.player()
	p.xp.add(300)
	await _F.frames(self, 3)
	main.get_node("UI/LevelUpMenu").visible = false
	_check(p.xp.level > level_saved, "XP earned in the new stage")
	main.run_manager.running = true
	main.run_manager.elapsed = 10.0
	main.run_manager.kills = 4
	_gs.run_gold = 6
	p.health.take_damage(100000.0)
	await _F.seconds(self, 1.6)
	end = main.get_node("UI/EndScreen")
	_check(end.visible and _buttons(end) == ["Return to the entrance"], "death button: %s" % [_buttons(end)])
	text = _texts(end)
	_check(text.contains("You died") and text.contains("Stage reached  1") and text.contains("Kills in this stage  4"), "death text: " + text)
	gold_before = _gs.gold
	_loaded.clear()
	for b in end.find_children("*", "Button", true, false):
		b.pressed.emit()
	_check(_loaded == [_gs.OVERWORLD] and _gs.dungeon == null, "death returns to the overworld")
	_check(_gs.journey.progress.level == level_saved, "the lost stage's XP is lost, the journey keeps its level")
	_check(_gs.journey.is_cleared(dun.name), "a cleared marker stays cleared after a death")
	_check(_gs.journey.position == _world.marker_world(dun) + Vector2(0, 40), "death puts the player below the marker")
	_check(_gs.gold == gold_before, "death gold was banked once (on the death screen), not twice")
	await _drop(main)

	# Death after clearing stage 1 of a fresh dungeon keeps stage 1's progress; the marker is not cleared.
	var dun2 := _marker("dungeon", 4)
	main = await _enter(dun2)
	_F.player().xp.add(8)
	await _F.frames(self, 3)
	main.get_node("UI/LevelUpMenu").visible = false
	var lvl1: int = _F.player().xp.level
	_gs.complete_stage()
	await _drop(main)
	main = _F.start_run(self, knight.id)
	_F.player().xp.add(40)
	await _F.frames(self, 3)
	main.get_node("UI/LevelUpMenu").visible = false
	_check(_F.player().xp.level > lvl1, "stage 2 gained more")
	main.run_manager.running = true
	_F.player().health.take_damage(100000.0)
	await _F.seconds(self, 1.6)
	_gs.fail_run()
	_check(_gs.journey.progress.level == lvl1 and not _gs.journey.is_cleared(dun2.name), "death in stage 2: stage 1's progress, not cleared")
	_check(_gs.journey.position == _world.marker_world(dun2) + Vector2(0, 40) and _loaded.back() == _gs.OVERWORLD, "back at the marker")
	await _drop(main)

	# Abandon behaves like death: the pause menu's prompt, Yes.
	main = await _enter(dun2, false)
	_F.player().xp.add(40)
	await _F.frames(self, 3)
	main.get_node("UI/LevelUpMenu").visible = false
	_gs.run_gold = 3
	gold_before = _gs.gold
	_loaded.clear()
	var prompt := main.get_node("UI/PauseMenu/AbandonPrompt")
	for b in prompt.find_children("*", "Button", true, false):
		if b.text == "Yes":
			b.pressed.emit()
	_check(_loaded == [_gs.OVERWORLD] and _gs.dungeon == null, "abandon leaves the dungeon, not for the hub")
	_check(_gs.journey.progress.level == lvl1 and not _gs.journey.is_cleared(dun2.name), "abandon keeps the last cleared progress, not cleared")
	_check(_gs.gold == gold_before + 3, "abandon banks the gold")
	await _drop(main)

	# --- The old path-based run is untouched.
	_gs.new_run(knight, 3)
	_check(_gs.dungeon == null and not _gs.is_last_stage(), "a path run: column 1 is not the last")
	_gs.current_column = 2
	_check(_gs.is_last_stage(), "a path run: column 3 is the last")
	_gs.current_column = 0
	_gs.current_row = 0
	_gs.current_stage = _gs.path.stage_at(0, 0)
	_check(_gs.map_seed() == hash("%d:%s" % [3, _gs.current_stage.theme.id]), "the path run's seed formula is unchanged")
	main = _F.start_run(self, knight.id)
	_check(_buttons(main.get_node("UI/PauseMenu")).has("Return to Hub"), "a path run's pause menu says Return to Hub")
	_check("Abandon this run?" in _texts(main.get_node("UI/PauseMenu/AbandonPrompt")), "and asks Abandon this run?")
	_check(main.get_node("UI/Hud")._stage_text.begins_with("Stage 1/3"), "a path run's HUD text is unchanged")
	_gs.complete_stage()
	_check(_loaded == [_gs.RUN] or _loaded.back() == _gs.SELECT, "a path run's stage win loads the select screen")
	await _drop(main)

	_gs.scene_hook = Callable()
	_gs.journey = null
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Both captures of a player (RunProgress uses autoload classes, so it is called through load()).
class RunProgressProbe:
	static func capture_both(player: Node) -> Dictionary:
		var rp: GDScript = load("res://scripts/systems/run_progress.gd")
		return {run = rp.capture(player), journey = rp.capture(player, false)}

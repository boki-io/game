extends SceneTree
## Spec 1.1 step 5: the Archer as a character: registry, data, animations, a run as the Archer without mana,
## the Q cast playing the dash animation, level-up cards and the hub panel text.
## Run: godot --headless --path . --script tests/archer_character.gd

const VALID_KEYS := [
	"arrow.extra", "arrow.pierce", "arrow.cooldown", "arrow.range", "dashshot.range", "dashshot.arrows",
	"dashshot.chain", "ricochet.extra", "ricochet.bounces", "ricochet.hits", "arrow_rain.radius",
	"arrow_rain.extra", "arrow_rain.ticks", "cooldown", "steady.full", "damage", "max_hp", "move_speed",
	"pickup_radius"]
const ANIMS := [&"idle", &"walk", &"attack1", &"attack2", &"hurt", &"death", &"dash"]

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node("GameSession")
	gs.scene_hook = func(_path: String) -> void: pass
	var archer: CharacterData
	for c in CharacterRegistry.all():
		if c.id == &"archer":
			archer = c
	_check(archer != null, "the Archer is in the registry")
	_check(CharacterRegistry.all().back() == archer, "the Archer is registered last")
	if archer == null:
		quit(1)
		return
	_check(archer.display_name == "Archer" and not archer.uses_mana, "named Archer, no mana")
	_check(archer.ability_auto != null and archer.ability_q != null and archer.ability_e != null and archer.ability_r != null,
		"all four abilities")
	for a: AbilityData in [archer.ability_auto, archer.ability_q, archer.ability_e, archer.ability_r]:
		_check(a.mana_cost == 0.0, "%s costs no mana" % a.display_name)
	_check(archer.trait_script != null and archer.trait_name == "Steady Aim", "has the Steady Aim trait")
	var steady: GDScript = archer.trait_script
	_check(("+%d%%" % roundi((steady.BONUS - 1.0) * 100.0)) in archer.trait_description
		and ("%d" % int(steady.FULL_DISTANCE)) in archer.trait_description, "trait text shows the bonus and distance")
	_check(archer.upgrade_pool.size() == 18, "18 upgrades")
	var ids: Dictionary = {}
	for u: UpgradeData in archer.upgrade_pool:
		ids[u.id] = true
		for key: String in u.adds.keys() + u.mults.keys():
			_check(key in VALID_KEYS, "%s: valid key %s" % [u.id, key])
			_check(not key.contains("mana"), "%s: no mana key %s" % [u.id, key])
	_check(ids.size() == 18, "18 distinct upgrade ids")
	_check(archer.sprite_frames != null, "has sprite frames")
	for anim in ANIMS:
		_check(archer.sprite_frames != null and archer.sprite_frames.has_animation(anim), "animation %s present" % anim)

	var panel_script: GDScript = load("res://scripts/ui/hub_info_panel.gd")
	_check(not panel_script.stats_text(archer).contains("Mana") and not panel_script.stats_text(archer).contains("Regen"),
		"the hub panel text has no Mana")
	_check(panel_script.stats_text(archer) == "HP 85   Speed 95", "panel text " + panel_script.stats_text(archer))

	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"archer")
	await F.frames(self, 2)
	var p = F.player()
	_check(p.character == archer, "the run starts as the Archer")
	_check(p.mana.current == 0.0 and p.mana.base_max == 0.0, "0 mana")
	_check(not p.trait_active(), "trait_active() is false (no FOCUS label)")
	for a: AbilityData in [archer.ability_auto, archer.ability_q, archer.ability_e, archer.ability_r]:
		_check(p.caster.mana_cost_of(a) == 0.0, "%s costs 0 mana in the run" % a.display_name)

	# Q plays the dash animation.
	F.cast(p, &"q", Vector2.RIGHT)
	await F.frames(self, 1)
	_check(p._anim != null and p._anim.animation == &"dash", "Q plays dash (is %s)" % p._anim.animation)

	# A level-up offers Archer upgrades and relics.
	var Roller: GDScript = load("res://scripts/relics/level_up_roller.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cards: Array = Roller.roll(p, 3, rng)
	_check(cards.size() == 3, "three cards")
	_check(cards.any(func(c: LevelUpChoice) -> bool: return c.tag == "RELIC"), "a relic is offered")
	var seen_stat := false
	var titles := archer.upgrade_pool.map(func(u: UpgradeData) -> String: return u.display_name)
	for s in 30:
		rng.seed = s
		for c: LevelUpChoice in Roller.roll(p, 3, rng):
			if c.tag != "RELIC":
				seen_stat = true
				_check(c.title in titles, "card %s is an Archer upgrade" % c.title)

	_check(seen_stat, "stat cards appear")
	main.queue_free()
	await process_frame
	root.get_node("PlayerRegistry").players.clear()
	gs.scene_hook = Callable()
	paused = false
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

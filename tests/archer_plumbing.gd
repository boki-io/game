extends SceneTree
## Spec 1.1 step 1: a character without mana (CharacterData.uses_mana), AbilityData.animation and params, the
## dash animation as a one-shot, and the static behavior_script.clamp_to_arena.
## Run: godot --headless --path . --script tests/archer_plumbing.gd

var _failed := false
var _fail_reasons: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _on_cast_failed(_slot: StringName, reason: StringName) -> void:
	_fail_reasons.append(reason)


func _init() -> void:
	await process_frame
	await process_frame
	var hud_script: GDScript = load("res://scripts/ui/hud.gd")
	var panel_script: GDScript = load("res://scripts/ui/hub_info_panel.gd")
	var player_script: GDScript = load("res://scripts/player/player.gd")

	# The default is true, for every character that exists.
	_check(CharacterData.new().uses_mana, "uses_mana defaults to true")
	for c in CharacterRegistry.all():
		_check(c.uses_mana and hud_script.shows_mana(c), "%s uses mana: the MP bar shows" % c.display_name)

	# A stand-in character without mana: no MP bar, no Mana or Regen in the panel text.
	var stand_in := CharacterData.new()
	stand_in.uses_mana = false
	stand_in.max_hp = 85.0
	stand_in.move_speed = 95.0
	stand_in.max_mana = 0.0
	stand_in.mana_regen = 0.0
	_check(not hud_script.shows_mana(stand_in), "no MP bar without mana")
	_check(panel_script.stats_text(stand_in) == "HP 85   Speed 95", "panel text: " + panel_script.stats_text(stand_in))
	_check(not panel_script.stats_text(stand_in).contains("Mana"), "panel text has no Mana")
	var knight: CharacterData = CharacterRegistry.all()[0]
	_check(panel_script.stats_text(knight).contains("Mana") and panel_script.stats_text(knight).contains("Regen"),
		"a mana character's panel text is unchanged")

	# AbilityData.param: the fallback when the key is missing, the value when set.
	var a := AbilityData.new()
	_check(a.param(&"arrows", 7.0) == 7.0, "param falls back when missing")
	a.params = {&"arrows": 5}
	_check(a.param(&"arrows", 7.0) == 5.0, "param reads the data (an int becomes a float)")
	_check(a.param(&"speed", 300.0) == 300.0, "param falls back for another key")

	# Animations: dash is a one-shot, so it hands back to idle/walk.
	_check(player_script.ONE_SHOT_ANIMS.has(&"dash"), "dash is a one-shot animation")
	_check(player_script.ONE_SHOT_ANIMS.has(&"attack1") and player_script.ONE_SHOT_ANIMS.has(&"meteor"),
		"the old one-shots remain")

	# clamp_to_arena is static on AbilityBehavior and keeps points inside the margin.
	var behavior_script: GDScript = load("res://scripts/abilities/ability_behavior.gd")
	var inset: float = behavior_script.ARENA_INSET + Arena.wall_margin
	_check(behavior_script.clamp_to_arena(Vector2(-500, -500)) == Vector2(inset, inset), "clamp_to_arena low corner")
	var far := Vector2(Arena.world_size) - Vector2(inset, inset)
	_check(behavior_script.clamp_to_arena(Vector2(99999, 99999)) == far, "clamp_to_arena high corner")
	var mid := Vector2(Arena.world_size) / 2.0
	_check(behavior_script.clamp_to_arena(mid) == mid, "clamp_to_arena leaves an inside point")

	# In a run: the animation choice and casting with 0 mana (a Wizard run: the Knight has no attack animations; its abilities made free).
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"wizard")
	await F.frames(self, 3)
	var p = F.player()
	var caster = p.caster
	var anim = p._anim
	_check(anim != null and anim.sprite_frames.has_animation(&"attack1"), "the Wizard has attack animations")

	# data.animation overrides the toggle: attack2 every time, however often it is cast.
	var d := AbilityData.new()
	d.animation = &"attack2"
	var before: bool = p._attack_toggle
	for i in 3:
		p._on_cast_started(&"e", d)
		_check(anim.animation == &"attack2", "animation = attack2 plays attack2 (cast %d)" % i)
	_check(p._attack_toggle == before, "an explicit animation leaves the attack toggle alone")
	# Without one the toggle alternates as before.
	var plain := AbilityData.new()
	p._on_cast_started(&"e", plain)
	var first: StringName = anim.animation
	p._on_cast_started(&"e", plain)
	_check(first != anim.animation, "no animation: attack1 and attack2 alternate")
	# A name the frames lack plays nothing and does not crash.
	d.animation = &"no_such_animation"
	p._on_cast_started(&"e", d)

	# Every cast succeeds with 0 mana when mana_cost is 0.
	var slots := {&"q": &"ability_q", &"e": &"ability_e", &"r": &"ability_r"}
	for slot in slots:
		var free: AbilityData = caster.get(slots[slot]).duplicate()
		free.mana_cost = 0.0
		caster.set(slots[slot], free)
	p.mana.configure(0.0, 0.0)
	_check(p.mana.current == 0.0, "the pool is empty")
	var target = F.spawn_enemy(main, "grunt", p.global_position + Vector2(60, 0), 1000.0, true)  # Chain Lightning needs one
	await F.frames(self, 2)
	caster.cast_failed.connect(_on_cast_failed)
	for slot in slots:
		caster.cancel()
		caster.cooldowns[slot] = 0.0
		_fail_reasons.clear()
		F.cast(p, slot)
		_check(not _fail_reasons.has(&"mana"), "%s is not refused for mana" % slot)
		_check(caster.cooldowns[slot] > 0.0 or caster.is_busy() or caster.chain_open(slot),
			"%s cast with 0 mana" % slot)
		_check(p.mana.current == 0.0, "%s spent no mana" % slot)

	# The HUD: no no-mana flash without mana.
	var hud = main.get_node("UI/Hud")
	hud._mana_flash = 0.0
	hud._on_cast_failed(&"q", &"mana")
	_check(hud._mana_flash > 0.0, "a mana character's HUD flashes the MP bar")
	var real: CharacterData = p.character
	p.character = stand_in
	hud._mana_flash = 0.0
	hud._on_cast_failed(&"q", &"mana")
	_check(hud._mana_flash == 0.0, "no MP flash without mana")
	p.character = real

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

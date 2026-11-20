extends SceneTree
## The item loot drop (spec 1.5): Pickups.roll_item_drop and place_item_drop, the ItemDrop (hop, pickup, no attract, no
## expiry), the unlock with its save and banner, the cap of 6, the charger's data and the director's roll.
## Run: godot --headless --path . --script tests/inventory/item_drop.gd

const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")
const SG := preload("res://scripts/systems/save_game.gd")

var _failed := false
var _F: GDScript
var _ID: GDScript  # not named ItemDrop: it uses an autoload
var _base := ""
var _taken: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _clean() -> void:
	for suffix in ["", ".tmp", ".bad", ".inventory", ".inventory.tmp", ".inventory.bad"]:
		DirAccess.remove_absolute(_base + suffix)


func _add(id: String, rating: StringName, slot: String = "helmet", display: String = "") -> void:
	var it = ItemDataS.new()
	it.id = StringName(id)
	it.display_name = display if display != "" else id.capitalize()
	it.rating = rating
	it.slot = StringName(slot)
	Reg.test_items.append(it)


func _init() -> void:
	await process_frame
	await process_frame
	_F = load("res://tests/fixture.gd")
	_ID = load("res://scripts/systems/item_drop.gd")
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_item_drop_test_%d.json" % OS.get_process_id())
	_clean()
	SG.override_path = _base
	var gs = root.get_node("GameSession")
	_add("plain_cap", &"standard", "helmet", "Plain Cap")
	_add("warden_helm", &"epic", "helmet", "Warden Helm")
	_add("crown", &"legendary", "helmet", "Crown")
	for i in 7:
		_add("extra_%d" % i, &"standard", "shoes")
	gs.inventory.set_state([], {})

	_data()
	await _roll()
	await _pickup()
	await _banner()
	await _director()

	gs.inventory.set_state([], {})
	Reg.test_items.clear()
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _run() -> Array:
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	var p = _F.player()
	p.caster.set_physics_process(false)
	p.xp.level = 60
	p.global_position = Vector2(60, 60)
	var pickups = main.get_node("Pickups")
	_taken = []
	pickups.item_collected.connect(func(id: StringName) -> void: _taken.append(id))
	return [main, p, pickups]


func _end(main: Node) -> void:
	main.queue_free()
	await process_frame
	paused = false


func _drops(pickups: Node) -> Array:
	var script: Script = load("res://scripts/systems/item_drop.gd")
	return pickups.get_children().filter(func(c: Node) -> bool: return c.get_script() == script and c.active)


func _data() -> void:
	var dasher: Resource = load("res://content/enemies/dasher.tres")
	_check(is_equal_approx(dasher.item_drop_chance, 0.10), "dasher.tres item_drop_chance is 0.10 (%s)" % dasher.item_drop_chance)
	var others := 0
	for path in _tres_files("res://content/enemies"):
		var d: Resource = load(path)
		if d is EnemyData and d.id != &"dasher" and d.item_drop_chance != 0.0:
			others += 1
			print("  sets it: ", path)
	_check(others == 0, "no other enemy sets item_drop_chance")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var pk = scene.get_node("Pickups")
	_check(pk.loot == load("res://content/items/loot.tres") and pk.item_drop_scene != null, "main.tscn's Pickups names the loot table and the drop scene")
	_check(scene.get_node("UI/ItemBanner") is Label, "the UI has an ItemBanner label")
	scene.free()


func _level_up_sounds(audio: Node) -> int:
	return audio.recent.filter(func(v: Dictionary) -> bool: return v.name == &"level_up").size()


func _tres_files(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_tres_files(dir_path.path_join(d)))
	return out


func _roll() -> void:
	var r := await _run()
	var main: Node = r[0]
	var pickups = r[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5

	pickups.inventory = null
	_check(not pickups.roll_item_drop(Vector2(1000, 800), 1.0, rng) and _drops(pickups).is_empty(), "inventory null: no drop")
	pickups.inventory = root.get_node("GameSession").inventory
	_check(not pickups.roll_item_drop(Vector2(1000, 800), 0.0, rng) and _drops(pickups).is_empty(), "chance 0: no drop")
	_check(pickups.roll_item_drop(Vector2(1000, 800), 1.0, rng), "chance 1: a drop is placed")
	var drops := _drops(pickups)
	_check(drops.size() == 1, "exactly one ItemDrop (%d)" % drops.size())
	if drops.size() == 1:
		var d = drops[0]
		_check(d.global_position.distance_to(Vector2(1000, 800)) < 1.0, "it starts at the position")
		var item := Reg.find(d.item_id)
		_check(item != null and d.rating == item.rating and d.color == ItemDataS.rating_color(item.rating), "tinted by the item's rating")
		_check(not d.has_method("attract"), "no attract(): the pickup radius never pulls it")
	_check(pickups.lying_item_ids().size() == 1 and pickups.lying_item_ids()[0] == drops[0].item_id, "lying_item_ids lists a hopping drop")
	var first: StringName = drops[0].item_id
	for i in 5:
		pickups.roll_item_drop(Vector2(1200 + i * 30, 800), 1.0, rng)
	var ids: Array = pickups.lying_item_ids()
	var unique := {}
	for id in ids:
		unique[id] = true
	_check(unique.size() == ids.size() and ids.count(first) == 1, "a lying item never repeats: %s" % [ids])

	# Placing directly by rating.
	pickups.place_item_drop(Vector2(1500, 900), &"crown")
	var crown = _drops(pickups).filter(func(c: Node) -> bool: return c.item_id == &"crown")[0]
	_check(crown.rating == &"legendary" and crown.color == ItemDataS.rating_color(&"legendary"), "place_item_drop tints a legendary orange")
	_check(_ID.GLOW_RADIUS[&"standard"] == 8.0 and _ID.GLOW_RADIUS[&"epic"] == 11.0 and _ID.GLOW_RADIUS[&"legendary"] == 14.0, "glow radius 8/11/14")

	# The cap: at most 6 lie at once, a hopping one counts.
	for d in _drops(pickups):
		pickups.release_item_drop(d)
	_check(pickups.lying_item_ids().is_empty(), "released drops are gone")
	var placed := 0
	for i in 20:
		if pickups.roll_item_drop(Vector2(1000 + i * 20, 800), 1.0, rng):
			placed += 1
	_check(placed == 6 and _drops(pickups).size() == 6, "at most 6 lie at once, all still hopping (%d)" % placed)
	_check(not pickups.roll_item_drop(Vector2(1000, 800), 1.0, rng), "at the cap a roll places nothing")
	await _F.seconds(self, 0.5)
	_check(not pickups.roll_item_drop(Vector2(1000, 800), 1.0, rng), "still capped after the hop")
	pickups.release_item_drop(_drops(pickups)[0])
	_check(pickups.roll_item_drop(Vector2(1000, 800), 1.0, rng), "a free place lets one drop again")

	# Everything owned: nothing drops.
	for d in _drops(pickups):
		pickups.release_item_drop(d)
	for it in Reg.test_items:
		pickups.inventory.unlocked.append(it.id)
	_check(not pickups.roll_item_drop(Vector2(1000, 800), 1.0, rng), "every item owned: no drop")
	pickups.inventory.set_state([], {})
	await _end(main)


func _pickup() -> void:
	var r := await _run()
	var main: Node = r[0]
	var p = r[1]
	var pickups = r[2]
	var gs = root.get_node("GameSession")
	gs.inventory.set_state([], {})
	var at := Vector2(1500, 900)

	# Not taken during its hop, even with the player on top of it.
	p.global_position = at - _ID.BODY_POINT
	pickups.place_item_drop(at, &"warden_helm")
	var drop = _drops(pickups)[0]
	var early := false
	for i in 40:
		await _F.frames(self, 1)
		if not _taken.is_empty() and drop.hopping():
			early = true
	_check(not early, "not taken during its hop")
	if _taken.is_empty():  # the hop carried it up to 14 px away from the player: step onto it
		p.global_position = drop.global_position - _ID.BODY_POINT
		await _F.frames(self, 14)
	_check(_taken == [&"warden_helm"], "taken once the hop is over, by the player standing there: %s" % [_taken])
	_check(not drop.active and pickups.lying_item_ids().is_empty(), "the drop is released")
	_check(gs.inventory.is_unlocked(&"warden_helm"), "the item is unlocked in the inventory")
	_check(FileAccess.file_exists(_base + ".inventory") and FileAccess.get_file_as_string(_base + ".inventory").contains("warden_helm"), "the unlock was saved to the scratch file")
	var banner: Label = main.get_node("UI/ItemBanner")
	_check(banner.visible and banner.text.begins_with("Found: Warden Helm (Epic)"), "banner text: %s" % banner.text)
	_check(banner.get_theme_color("font_color") == ItemDataS.rating_color(&"epic"), "banner in the epic colour")
	await _end(main)

	# Within 14 px, not beyond; a dead player takes nothing; the pickup radius does not pull it.
	r = await _run()
	main = r[0]
	p = r[1]
	pickups = r[2]
	gs.inventory.set_state([], {})
	pickups.place_item_drop(at, &"plain_cap")
	drop = _drops(pickups)[0]
	await _F.seconds(self, 0.5)
	_check(not drop.hopping(), "the hop is over")
	p.global_position = drop.global_position - _ID.BODY_POINT + Vector2(30, 0)  # inside the 48 px pickup radius
	await _F.seconds(self, 1.0)
	_check(drop.active and drop.global_position.distance_to(at) < 40.0 and _taken.is_empty(), "30 px away: not pulled and not taken")
	p.global_position = drop.global_position - _ID.BODY_POINT + Vector2(15.5, 0)
	await _F.frames(self, 14)
	_check(drop.active and _taken.is_empty(), "15.5 px away: not taken")
	p.dead = true
	p.global_position = drop.global_position - _ID.BODY_POINT
	await _F.frames(self, 14)
	_check(drop.active and _taken.is_empty(), "a dead player takes nothing")
	p.dead = false
	# No expiry.
	drop._age = 120.0
	await _F.seconds(self, 0.0)
	await _F.frames(self, 1)
	p.global_position = Vector2(60, 60)
	await _F.frames(self, 10)
	_check(drop.active, "no expiry after 120 s of age")
	p.global_position = drop.global_position - _ID.BODY_POINT + Vector2(13.0, 0)
	await _F.frames(self, 14)
	_check(_taken == [&"plain_cap"] and not drop.active, "taken from 13 px by the living player")
	await _end(main)

	# An item already owned: no banner and no sound.
	r = await _run()
	main = r[0]
	p = r[1]
	pickups = r[2]
	gs.inventory.set_state([&"plain_cap"], {})
	var banner2: Label = main.get_node("UI/ItemBanner")
	var audio = root.get_node("Audio")
	audio.recent.clear()
	audio._last_ms.clear()
	pickups.place_item_drop(at, &"plain_cap")
	drop = _drops(pickups)[0]
	await _F.seconds(self, 0.5)
	p.global_position = drop.global_position - _ID.BODY_POINT
	await _F.frames(self, 14)
	_check(_taken == [&"plain_cap"] and not drop.active, "an owned item is still picked up")
	_check(not banner2.visible and banner2.text == "", "owned: no banner (%s)" % banner2.text)
	_check(gs.inventory.unlocked == [&"plain_cap"], "owned: the pool is unchanged")
	_check(_level_up_sounds(audio) == 0, "owned: no sound")
	await _end(main)
	gs.inventory.set_state([], {})


func _banner() -> void:
	var r := await _run()
	var main: Node = r[0]
	var pickups = r[2]
	var gs = root.get_node("GameSession")
	gs.inventory.set_state([], {})
	var banner: Label = main.get_node("UI/ItemBanner")
	var audio = root.get_node("Audio")
	audio.recent.clear()
	audio._last_ms.clear()
	main._on_item_collected(&"crown")
	_check(_level_up_sounds(audio) == 1, "a new item plays the level_up sound")
	_check(banner.visible and banner.text.begins_with("Found: Crown (Legendary)") and banner.modulate.a == 1.0, "legendary banner text: %s" % banner.text)
	_check(banner.get_theme_color("font_color") == ItemDataS.rating_color(&"legendary"), "legendary colour")
	_check(banner.process_mode == Node.PROCESS_MODE_ALWAYS, "the banner keeps running while paused")
	# A pause that spans the 3 s: the banner is still cleared.
	paused = true
	await create_timer(1.5, true).timeout
	_check(banner.visible and banner.modulate.a == 1.0, "still shown at 1.5 s")
	# A second find replaces the text and restarts the time.
	main._on_item_collected(&"plain_cap")
	_check(banner.text.begins_with("Found: Plain Cap (Standard)"), "a second find replaces the text: %s" % banner.text)
	await create_timer(2.0, true).timeout  # 3.5 s after the first find, 2.0 after the second
	_check(banner.visible and banner.modulate.a == 1.0, "the second find restarted the time")
	await create_timer(1.3, true).timeout  # 3.3 s after the second: fading
	_check(banner.visible and banner.modulate.a < 1.0, "fading after 3 s (%s)" % banner.modulate.a)
	await create_timer(0.6, true).timeout
	_check(not banner.visible, "cleared after the fade, across a pause")
	# Already owned: nothing.
	banner.text = ""
	main._on_item_collected(&"crown")
	_check(not banner.visible and banner.text == "", "an owned item shows no banner")
	main._on_item_collected(&"no_such_item")
	_check(not banner.visible, "an unknown id shows no banner")
	paused = false
	await _end(main)
	gs.inventory.set_state([], {})


func _director() -> void:
	var r := await _run()
	var main: Node = r[0]
	var pickups = r[2]
	var gs = root.get_node("GameSession")
	gs.inventory.set_state([], {})
	main.spawn_director.apply_stage(load("res://scripts/stages/stage_data.gd").new())
	var dasher: Resource = load("res://content/enemies/dasher.tres").duplicate()
	dasher.item_drop_chance = 1.0
	var grunt: Resource = load("res://content/enemies/grunt.tres").duplicate()
	grunt.item_drop_chance = 0.0
	for i in 20:
		_kill(main, "grunt", grunt, Vector2(1000, 800))
	_check(_drops(pickups).is_empty(), "a grunt never drops an item")
	_kill(main, "dasher", dasher, Vector2(1000, 800))
	_check(_drops(pickups).size() == 1, "a dasher at chance 1.0 drops one through the director")
	var real: Resource = load("res://content/enemies/dasher.tres")
	_check(is_equal_approx(real.item_drop_chance, 0.10), "the shipped dasher stays at 10%")
	await _end(main)


func _kill(main: Node, id: String, data: Resource, at: Vector2) -> void:
	var e = _F.spawn_enemy(main, id, at, 1.0, true)
	main.spawn_director._pools[data] = []
	main.spawn_director.alive_by_type[data.id] += 1
	e.data = data
	main.spawn_director.alive += 1
	main.spawn_director._on_enemy_died(e)

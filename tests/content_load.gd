extends SceneTree
## Spec 1.2 section 8: all game content loads and is consistent. Walks the content folders with DirAccess (not
## content/maps, which tests/maps/map_content.gd covers) and checks that every .tres loads and every ext_resource
## it names exists, upgrade ids are unique, every registered character has four abilities with a behavior, nothing
## is an orphan (no upgrade, ability, relic, attribute or frames file that nothing uses), per-ability upgrades
## only touch stat keys of an ability in the character's pool, and then (runtime half) a run as each character
## casts every ability once. With FOLDER_RULES the folder layout of spec 1.2 is checked too.
## Run: godot --headless --path . --script tests/content_load.gd

## false: the layout before spec 1.2 (data/ and content/). true: content/characters/<id>/abilities/<id>/ and so on.
const FOLDER_RULES := false
const ROOTS := ["res://data", "res://content"]
const TEMPLATE_DIR := "res://content/characters/_template"
const SKIP_DIRS := ["res://content/maps", TEMPLATE_DIR]
## Ability ids whose behavior is a shared base that stays in scripts/abilities/ (spec 1.2 section 3).
const SHARED_BASE_BEHAVIORS := {&"dash": "res://scripts/abilities/dash_slash_behavior.gd", &"bolt": "res://scripts/abilities/bolt_behavior.gd"}
const SLOTS := [&"auto", &"q", &"e", &"r"]

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 40:
			print("FAIL: ", what)


## Every .tres under `dir`, skipping SKIP_DIRS and hidden folders.
func _scan(dir: String, out: Array) -> void:
	if SKIP_DIRS.has(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_scan(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			out.append(dir.path_join(file))


## The res:// paths a .tres names in its ext_resource lines.
func _ext_paths(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var rx := RegEx.create_from_string('\\[ext_resource [^\\]]*path="(res://[^"]+)"')
	for m in rx.search_all(f.get_as_text()):
		out.append(m.get_string(1))
	return out


func _class_of(res: Resource) -> String:
	var s: Script = res.get_script()
	return String(s.get_global_name()) if s != null else ""


func _check_loads(path: String) -> Resource:
	for ext: String in _ext_paths(path):
		_check(FileAccess.file_exists(ext) or ResourceLoader.exists(ext), "%s names a missing file %s" % [path, ext])
	var res: Resource = load(path)
	_check(res != null, "%s does not load" % path)
	return res


func _init() -> void:
	await process_frame
	var files: Array = []
	for root_dir: String in ROOTS:
		_scan(root_dir, files)
	files.sort()
	_check(not files.is_empty(), "found content files")

	var by_class: Dictionary = {}  # class name -> Array of paths
	for path: String in files:
		var res := _check_loads(path)
		if res != null:
			var cls := _class_of(res)
			if not by_class.has(cls):
				by_class[cls] = []
			by_class[cls].append(path)

	# The template (folder rules on): loaded explicitly, exempt from the orphan, unique-id and pool rules.
	if FOLDER_RULES or DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		var template_files: Array = []
		_scan_template(TEMPLATE_DIR, template_files)
		_check(not template_files.is_empty() or not FOLDER_RULES, "the template has files")
		_check(not FOLDER_RULES or FileAccess.file_exists(TEMPLATE_DIR + "/character.tres"), "the template has a character.tres")
		for path: String in template_files:
			_check_loads(path)

	# Registered characters: four abilities each with a behavior.
	var chars: Array[CharacterData] = CharacterRegistry.all()
	_check(chars.size() >= 3, "at least three registered characters")
	var pool_paths: Dictionary = {}  # upgrade path -> Array of character ids that list it
	var char_paths: Dictionary = {}
	var ability_paths: Dictionary = {}
	var frames_paths: Dictionary = {}
	for c in chars:
		char_paths[c.resource_path] = true
		if c.sprite_frames != null:
			frames_paths[c.sprite_frames.resource_path] = true
		var abilities: Array = [c.ability_auto, c.ability_q, c.ability_e, c.ability_r]
		var ids_here: Array = []
		for a: AbilityData in abilities:
			_check(a != null, "%s has all four abilities" % c.id)
			if a == null:
				continue
			ability_paths[a.resource_path] = true
			ids_here.append(String(a.id))
			_check(a.behavior != null, "%s/%s has a behavior" % [c.id, a.id])
			if FOLDER_RULES:
				_check_ability_folder(c, a)
		_check(ids_here.size() == 4 and _unique(ids_here), "%s: four distinct ability ids %s" % [c.id, ids_here])
		var seen: Dictionary = {}
		for u: UpgradeData in c.upgrade_pool:
			_check(not seen.has(u.id), "%s lists upgrade %s twice" % [c.id, u.id])
			seen[u.id] = true
			if not pool_paths.has(u.resource_path):
				pool_paths[u.resource_path] = []
			pool_paths[u.resource_path].append(c.id)
			_check_upgrade_keys(c, ids_here, u)

	# Upgrade ids are unique across all content.
	var upgrade_ids: Dictionary = {}
	for path: String in by_class.get("UpgradeData", []):
		var u: UpgradeData = load(path)
		_check(not upgrade_ids.has(u.id), "upgrade id %s is used twice (%s and %s)" % [u.id, upgrade_ids.get(u.id), path])
		upgrade_ids[u.id] = path
		_check(pool_paths.has(path), "orphan upgrade %s is in no character's pool" % path)
		if FOLDER_RULES:
			_check_upgrade_folder(path, u, pool_paths.get(path, []))

	# Orphans of the other kinds.
	for path: String in by_class.get("AbilityData", []):
		_check(ability_paths.has(path), "orphan ability %s is used by no registered character" % path)
	for path: String in by_class.get("CharacterData", []):
		_check(char_paths.has(path), "orphan character %s is not in CharacterRegistry" % path)
	var relic_paths: Dictionary = {}
	for r in RelicRegistry.all():
		relic_paths[r.resource_path] = true
	for path: String in by_class.get("RelicData", []):
		_check(relic_paths.has(path), "orphan relic %s is not in RelicRegistry" % path)
	var attr_paths: Dictionary = {}
	for a in AttributeRegistry.all():
		attr_paths[a.resource_path] = true
	for path: String in by_class.get("AttributeData", []):
		_check(attr_paths.has(path), "orphan attribute %s is not in AttributeRegistry" % path)
	for path: String in by_class.get("SpriteFrames", []):
		_check(frames_paths.has(path), "orphan frames %s is used by no registered character" % path)
	for r_path: String in relic_paths:
		_check(FileAccess.file_exists(r_path), "registered relic %s exists" % r_path)

	if FOLDER_RULES:
		_check(not DirAccess.dir_exists_absolute("res://data"), "res://data is gone")
		_check(not DirAccess.dir_exists_absolute("res://assets/sprites"), "res://assets/sprites is gone")

	await _runtime(chars)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _scan_template(dir: String, out: Array) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scan_template(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			out.append(dir.path_join(file))


func _unique(list: Array) -> bool:
	var d: Dictionary = {}
	for x in list:
		d[x] = true
	return d.size() == list.size()


## A per-ability upgrade (every tag but "Passive") only changes stat keys of an ability of this character:
## every key in adds and mults starts with `<ability id>.`.
func _check_upgrade_keys(c: CharacterData, ability_ids: Array, u: UpgradeData) -> void:
	if u.tag == "Passive":
		return
	for key: String in u.adds.keys() + u.mults.keys():
		var ok := false
		for id: String in ability_ids:
			if key.begins_with(id + "."):
				ok = true
		_check(ok, "%s: upgrade %s key %s starts with no ability id of %s %s" % [c.id, u.id, key, c.id, ability_ids])


func _check_ability_folder(c: CharacterData, a: AbilityData) -> void:
	var dir := "res://content/characters/%s/abilities/%s/" % [c.id, a.id]
	_check(a.resource_path == dir + "ability.tres", "%s/%s: ability.tres is %s, expected %sability.tres" % [c.id, a.id, a.resource_path, dir])
	if a.behavior == null:
		return
	if SHARED_BASE_BEHAVIORS.has(a.id):
		_check(a.behavior.resource_path == SHARED_BASE_BEHAVIORS[a.id], "%s/%s: shared behavior is %s" % [c.id, a.id, a.behavior.resource_path])
	else:
		_check(a.behavior.resource_path.begins_with(dir), "%s/%s: behavior %s is not in %s" % [c.id, a.id, a.behavior.resource_path, dir])


## Where an upgrade lies decides who may list it (spec 1.2 section 2).
func _check_upgrade_folder(path: String, u: UpgradeData, owners: Array) -> void:
	var char_rx := RegEx.create_from_string("^res://content/characters/([^/]+)/(?:abilities/([^/]+)/)?upgrades/[^/]+\\.tres$")
	if path.begins_with("res://content/shared/upgrades/"):
		_check(owners.size() >= 2, "shared upgrade %s is in %d pools, expected at least 2" % [path, owners.size()])
		return
	var m := char_rx.search(path)
	if m == null:
		_check(false, "upgrade %s lies in no allowed folder" % path)
		return
	var owner_id: String = m.get_string(1)
	_check(owners.size() == 1 and String(owners[0]) == owner_id, "upgrade %s must be in only %s's pool (is in %s)" % [path, owner_id, owners])
	var ability_id: String = m.get_string(2)
	if not ability_id.is_empty():
		for key: String in u.adds.keys() + u.mults.keys():
			_check(key.begins_with(ability_id + "."), "%s: key %s does not start with its folder's ability %s" % [path, key, ability_id])


func _enemy_path() -> String:
	for p in ["res://content/enemies/grunt.tres", "res://data/enemies/grunt.tres"]:
		if FileAccess.file_exists(p):
			return p
	return ""


## For each registered character: start a run and cast each ability once next to a frozen enemy. A script error
## in a behavior shows up as an error in the output (or a hang, which the time limit turns into a failure).
func _runtime(chars: Array[CharacterData]) -> void:
	var gs: Node = root.get_node("GameSession")
	gs.scene_hook = func(_path: String) -> void: pass
	var F: GDScript = load("res://tests/fixture.gd")
	var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy_path := _enemy_path()
	_check(enemy_path != "", "a grunt enemy file exists")
	for c in chars:
		var main: Node = F.start_run(self, c.id)
		await F.frames(self, 2)
		var p = F.player()
		_check(p != null and p.character == c, "%s: the run starts as this character" % c.id)
		if p == null:
			continue
		var e = enemy_scene.instantiate()
		e.data = load(enemy_path)
		main.get_node("World/Enemies").add_child(e)
		e.activate(p.global_position + Vector2(40, 0), 1.0)
		e.set_physics_process(false)
		var started: Array = []
		var failed_reason: Dictionary = {}
		p.caster.cast_started.connect(func(slot: StringName, _d: AbilityData) -> void: started.append(slot))
		p.caster.cast_failed.connect(func(slot: StringName, reason: StringName) -> void: failed_reason[slot] = reason)
		for slot: StringName in SLOTS:
			var waited := 0
			while p.caster.is_busy() and waited < 180:
				await F.frames(self, 1)
				waited += 1
			p.mana.current = p.mana.base_max
			p.caster.cooldowns[slot] = 0.0
			p.global_position = main.get_node("World/Enemies").get_child(0).global_position - Vector2(40, 0)
			F.cast(p, slot, Vector2.RIGHT)
			await F.frames(self, 3)
			_check(started.has(slot), "%s: slot %s cast started (failed: %s)" % [c.id, slot, failed_reason.get(slot, "no")])
			await F.seconds(self, 0.5)
		var waited := 0
		while p.caster.is_busy() and waited < 180:
			await F.frames(self, 1)
			waited += 1
		main.queue_free()
		await process_frame
		root.get_node("PlayerRegistry").players.clear()
	gs.scene_hook = Callable()
	paused = false

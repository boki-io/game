extends SceneTree
## Map content (spec 0.6 section 3.4): content/maps/ on disk against MapRegistry, the required files, thumbnail size,
## ids, unique names, a variant for every enemy type, no stray files. Also run on _template and _default.
## Run: godot --headless --path . --script tests/maps/map_content.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const ThemeScript := preload("res://scripts/maps/map_theme.gd")
const VariantScript := preload("res://scripts/maps/monster_variant.gd")
const ROOT := "res://content/maps/"
const ENEMY_DIR := "res://data/enemies/"
const THUMB_SIZE := Vector2i(64, 40)

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 20:
			print("FAIL: ", what)


## Ids of the enemy types the director can spawn: every EnemyData in data/enemies/ that moves.
func _enemy_ids() -> Array:
	var out: Array = []
	for file in DirAccess.get_files_at(ENEMY_DIR):
		if file.ends_with(".tres"):
			var data = load(ENEMY_DIR + file)
			if data != null and not data.immovable:
				out.append(String(data.id))
	out.sort()
	return out


func _folders() -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at(ROOT):
		out.append(d)
	out.sort()
	return out


func _is_import_file(file: String) -> bool:
	return file.ends_with(".import") or file.ends_with(".uid")


func _init() -> void:
	await process_frame
	var enemy_ids := _enemy_ids()
	_check(enemy_ids == ["dasher", "grunt", "ranged"], "the director's enemy types are grunt, ranged, dasher (got %s)" % [enemy_ids])

	# Folders on disk against the registry (both ways).
	var playable: Array = []
	for folder: String in _folders():
		if not folder.begins_with("_"):
			playable.append(folder)
			_check(Registry.IDS.has(folder), "folder %s is missing from MapRegistry.IDS" % folder)
	for id: String in Registry.IDS:
		_check(playable.has(id), "registry id %s has no folder" % id)
	_check(Registry.IDS.size() >= 8, "at least the eight v0.6 maps")
	_check(_folders().has("_default") and _folders().has("_template"), "_default and _template exist")

	var names := {}
	var all_ids: Array = Registry.IDS.duplicate()
	all_ids.append_array(["_default", "_template"])
	for id: String in all_ids:
		var tag := id + ": "
		var folder := ROOT + id + "/"
		var is_default := id == "_default"

		# Required files, and nothing else at the top level.
		_check(FileAccess.file_exists(folder + "map.tres"), tag + "map.tres exists")
		if not is_default:
			_check(FileAccess.file_exists(folder + "thumbnail.png"), tag + "thumbnail.png exists")
		for file in DirAccess.get_files_at(folder):
			var allowed: bool = file == "map.tres" or (file == "thumbnail.png" and not is_default)
			_check(allowed or _is_import_file(file), tag + "stray file %s" % file)
		for sub in DirAccess.get_directories_at(folder):
			_check(sub == "monsters" and not is_default, tag + "stray folder %s" % sub)

		var theme = load(folder + "map.tres")
		_check(theme != null and theme.get_script() == ThemeScript, tag + "map.tres is a MapTheme")
		if theme == null:
			continue
		_check(String(theme.id) == id, tag + "id equals the folder name (%s)" % theme.id)
		_check(theme.display_name != "", tag + "has a display name")
		if not is_default:
			names[theme.display_name] = names.get(theme.display_name, 0) + 1

		# Thumbnail
		if is_default:
			_check(theme.thumbnail == null, tag + "the default has no thumbnail")
			_check(theme.monsters.is_empty(), tag + "the default has no monsters")
			_check(theme.legacy_layout, tag + "the default uses the legacy layout")
		else:
			_check(theme.thumbnail != null, tag + "thumbnail loads")
			if theme.thumbnail != null:
				_check(Vector2i(theme.thumbnail.get_size()) == THUMB_SIZE, tag + "thumbnail is 64x40")
				_check(theme.thumbnail.resource_path == folder + "thumbnail.png", tag + "thumbnail is the folder's own file")
			_check(not theme.legacy_layout, tag + "only the default uses the legacy layout")

		# Monster variants: one per enemy type, file name = enemy_id, nothing unknown.
		if not is_default:
			var variant_files := DirAccess.get_files_at(folder + "monsters/")
			var on_disk: Array = []
			for file in variant_files:
				if _is_import_file(file):
					continue
				_check(file.ends_with(".tres"), tag + "stray monster file %s" % file)
				on_disk.append(file.get_basename())
			on_disk.sort()
			_check(on_disk == enemy_ids, tag + "monsters/ holds exactly %s (has %s)" % [enemy_ids, on_disk])
			_check(theme.monsters.size() == enemy_ids.size(), tag + "map.tres lists one variant per enemy type")
			for enemy_id: String in enemy_ids:
				var variant = load(folder + "monsters/%s.tres" % enemy_id)
				_check(variant != null and variant.get_script() == VariantScript, tag + "%s.tres is a MonsterVariant" % enemy_id)
				if variant != null:
					_check(String(variant.enemy_id) == enemy_id, tag + "%s.tres has enemy_id %s" % [enemy_id, variant.enemy_id])
				_check(theme.variant_for(StringName(enemy_id)) != null, tag + "variant_for(%s) finds it" % enemy_id)
			_check(theme.variant_for(&"no_such_enemy") == null, tag + "variant_for an unknown id is null")

	for display_name: String in names:
		_check(names[display_name] == 1, "display name %s is used once" % display_name)

	# The registry itself.
	var themes: Array = Registry.all()
	_check(themes.size() == Registry.IDS.size() and themes.size() >= 8, "MapRegistry.all() has a theme per id (at least 8)")
	for i in themes.size():
		_check(String(themes[i].id) == Registry.IDS[i], "all() keeps the list order (%d)" % i)
		_check(Registry.by_id(StringName(Registry.IDS[i])) != null, "by_id finds %s" % Registry.IDS[i])
	_check(Registry.default() != null and String(Registry.default().id) == "_default", "default() is the _default map")
	_check(Registry.by_id(&"_default") != null, "by_id finds the default")
	_check(Registry.by_id(&"_template") == null and Registry.by_id(&"nope") == null, "by_id is null for the template and unknown ids")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

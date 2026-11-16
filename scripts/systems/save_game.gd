class_name SaveGame
extends RefCounted
## The camp save (spec 0.7, section 8): banked gold and attribute levels in one JSON file. Static, no autoload.
## Only GameSession reads it. Tests and tools must not touch the player's file: see `path()`.

const VERSION := 1
const GOLD_MAX := 999999999
const USER_PATH := "user://camp.json"

## A test sets this to use its own file (or "" to disable saving). Null means "not set".
static var override_path: Variant = null


## Where the save lives: the test override, else HERO_HORDE_SAVE, else "" (saving off) under a headless run, else
## user://camp.json. (`OS.has_feature("headless")` is false under `--headless`; the display server name is checked.)
static func path() -> String:
	if override_path != null:
		return override_path
	var env := OS.get_environment("HERO_HORDE_SAVE")
	if env != "":
		return env
	if DisplayServer.get_name() == "headless":
		return ""
	return USER_PATH


## Writes `camp.json` via a temp file renamed over it. False (with a warning) when saving is off or fails;
## the state then stays in memory.
static func save(gold: int, levels: Dictionary) -> bool:
	var file_path := path()
	if file_path == "":
		return false
	var levels_out := {}
	for id in levels:
		levels_out[str(id)] = int(levels[id])
	var text := JSON.stringify({version = VERSION, gold = gold, levels = levels_out}, "\t")
	var tmp := file_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	var err := DirAccess.rename_absolute(tmp, file_path)
	if err != OK:
		push_warning("SaveGame: cannot rename %s over %s (error %d)" % [tmp, file_path, err])
		return false
	return true


## Reads the save: {gold: int, levels: Dictionary (StringName id -> int)}. A missing, empty or disabled save is a
## new game; a file that fails the checks is renamed to `.bad` and also gives a new game. Values are clamped
## and ids no longer in the registry are dropped.
static func load_data() -> Dictionary:
	var result := {gold = 0, levels = {}}
	var file_path := path()
	if file_path == "":
		return result
	var source := file_path
	if not FileAccess.file_exists(file_path):
		# A write that was interrupted after the tmp was complete but before the rename.
		if not FileAccess.file_exists(file_path + ".tmp"):
			return result
		source = file_path + ".tmp"
	var text := FileAccess.get_file_as_string(source)
	if text.strip_edges() == "":
		return result
	var parsed := _parse(text)
	if parsed.is_empty():
		push_warning("SaveGame: %s is not a valid save; keeping it as .bad and starting new" % source)
		DirAccess.rename_absolute(source, file_path + ".bad")
		return result
	return parsed


## The checked and clamped content of a save text, or {} if it is not a valid version 1 save.
static func _parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var root: Variant = json.data
	if not root is Dictionary or not _is_number(root.get("version")) or root.version != VERSION:
		return {}
	if not _is_number(root.get("gold")) or not root.get("levels") is Dictionary:
		return {}
	var levels := {}
	for key in root.levels:
		var value: Variant = root.levels[key]
		if not _is_number(value):
			return {}
		var attr := AttributeRegistry.find(StringName(str(key)))
		if attr != null:
			levels[attr.id] = int(clampf(value, 0.0, attr.max_level))
	return {gold = int(clampf(root.gold, 0.0, GOLD_MAX)), levels = levels}


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT) or (typeof(value) == TYPE_FLOAT and is_finite(value))

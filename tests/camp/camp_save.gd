extends SceneTree
## SaveGame: round trip, missing and zero-length files, corrupt files (renamed .bad), clamping, unknown ids, the temp
## file, the tmp fallback, saving off when headless with no path, and GameSession loading and saving.
## Run: godot --headless --path . --script tests/camp/camp_save.gd

const SG := preload("res://scripts/systems/save_game.gd")

var _failed := false
var _base := ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _write(file_path: String, text: String) -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean() -> void:
	for suffix in ["", ".tmp", ".bad"]:
		DirAccess.remove_absolute(_base + suffix)


func _init() -> void:
	await process_frame
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_camp_save_test_%d.json" % OS.get_process_id())
	_clean()

	# Saving is off with no path under headless.
	SG.override_path = null
	if OS.get_environment("HERO_HORDE_SAVE") == "":
		_check(SG.path() == "", "headless with no path: saving is off")
		_check(not SG.save(5, {}), "save returns false when off")
	SG.override_path = ""
	_check(SG.load_data() == {gold = 0, levels = {}}, "disabled load is a new game")
	SG.override_path = _base

	# Missing file: new game.
	var d := SG.load_data()
	_check(d.gold == 0 and d.levels.is_empty(), "missing file is a new game")

	# Round trip, no temp file left behind.
	_check(SG.save(1234, {&"might": 3, &"greed": 7}), "save succeeds")
	_check(FileAccess.file_exists(_base) and not FileAccess.file_exists(_base + ".tmp"), "file written, tmp not left")
	d = SG.load_data()
	_check(d.gold == 1234 and d.levels == {&"might": 3, &"greed": 7}, "round trip")
	_check(SG.save(5, {}) and SG.load_data().gold == 5, "overwrite replaces the file")

	# Zero-length file: a new game, no .bad.
	_write(_base, "")
	d = SG.load_data()
	_check(d.gold == 0 and d.levels.is_empty() and not FileAccess.file_exists(_base + ".bad"), "zero-length file is a new game")

	# Corrupt files go to .bad.
	for bad in ["{not json", "[1, 2]", "42", '{"version": 2, "gold": 1, "levels": {}}', '{"gold": 1, "levels": {}}',
			'{"version": 1, "gold": "x", "levels": {}}', '{"version": 1, "gold": 1, "levels": []}',
			'{"version": 1, "gold": 1, "levels": {"might": "x"}}']:
		DirAccess.remove_absolute(_base + ".bad")
		_write(_base, bad)
		d = SG.load_data()
		_check(d.gold == 0 and d.levels.is_empty(), "bad file gives a new game: " + bad)
		_check(FileAccess.file_exists(_base + ".bad") and not FileAccess.file_exists(_base), "bad file moved to .bad: " + bad)

	# Clamping, unknown ids, floats.
	_write(_base, '{"version": 1, "gold": 99999999999, "levels": {"might": 99, "fury": -4, "toughness": 2.0, "gone": 3}}')
	d = SG.load_data()
	_check(d.gold == SG.GOLD_MAX, "gold clamped to the maximum")
	_check(d.levels.get(&"might") == 7 and d.levels.get(&"fury") == 0 and d.levels.get(&"toughness") == 2, "levels clamped, float accepted")
	_check(not d.levels.has(&"gone"), "unknown id dropped")
	_write(_base, '{"version": 1, "gold": -50, "levels": {}}')
	_check(SG.load_data().gold == 0, "negative gold clamped to 0")
	_write(_base, '{"version": 1, "gold": 1e400, "levels": {}}')
	_check(SG.load_data().gold == SG.GOLD_MAX or FileAccess.file_exists(_base + ".bad"), "huge gold does not crash")

	# Interrupted write: only the tmp exists.
	_clean()
	_write(_base + ".tmp", '{"version": 1, "gold": 77, "levels": {}}')
	_check(SG.load_data().gold == 77, "tmp is loaded when the file is missing")
	_clean()

	# GameSession: loads in _ready (via the same call), saves on buy and bank.
	var gs: Node = get_root().get_node("GameSession")
	SG.save(500, {&"might": 1})
	var saved := SG.load_data()
	gs.gold = saved.gold
	gs.attribute_levels = saved.levels
	_check(gs.gold == 500 and gs.level_of(&"might") == 1, "session state from the save")
	_check(gs.buy_attribute(&"might"), "buy a level")
	d = SG.load_data()
	_check(d.gold == 500 - 60 and d.levels.get(&"might") == 2, "buy is saved")
	gs.undo_attribute(&"might")
	_check(SG.load_data().gold == 500, "undo is saved")
	gs.reset_attributes()
	_check(SG.load_data().levels.get(&"might", 0) == 0, "reset is saved")
	gs.run_gold = 25
	_check(gs.bank_run() == 25, "bank_run returns the reward")
	_check(SG.load_data().gold == gs.gold, "banking is saved")
	gs.run_gold = 40
	var gold_now: int = gs.gold
	_check(SG.load_data().gold == gold_now, "the purse is not saved")

	gs.gold = 0
	gs.run_gold = 0
	gs.last_reward = 0
	gs.attribute_levels = {}
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## InventorySave (spec 1.4): the round trip, a missing, empty or disabled file, corrupt files (renamed .bad), what loading
## drops (unknown ids, worn but not unlocked, a ring in the helmet slot, an item worn twice), the temp-file fallback, that
## the camp save file is not touched, and GameSession loading and autosaving the inventory.
## Run: godot --headless --path . --script tests/inventory/inventory_save.gd

const SG := preload("res://scripts/systems/save_game.gd")
const ISave := preload("res://scripts/inventory/inventory_save.gd")
const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")
const InventoryS := preload("res://scripts/inventory/inventory.gd")

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
	for suffix in ["", ".tmp", ".bad", ".inventory", ".inventory.tmp", ".inventory.bad"]:
		DirAccess.remove_absolute(_base + suffix)


func _item(id: String, slot: String) -> Resource:
	var it = ItemDataS.new()
	it.id = StringName(id)
	it.slot = StringName(slot)
	return it


func _init() -> void:
	await process_frame
	await process_frame
	for it in [_item("cap", "helmet"), _item("mail", "chestplate"), _item("band", "ring"), _item("loop", "ring")]:
		Reg.test_items.append(it)
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_inventory_save_test_%d.json" % OS.get_process_id())
	_clean()
	var file := _base + ".inventory"

	# Saving is off with no path under headless; the camp save's path rules apply.
	SG.override_path = ""
	_check(ISave.path() == "", "disabled: no inventory path")
	var inv = InventoryS.new()
	inv.unlock(&"cap")
	_check(not ISave.save(inv), "save returns false when off")
	SG.override_path = _base
	_check(ISave.path() == file, "the inventory file sits next to the camp save: %s" % ISave.path())

	# A missing file is an empty inventory; loading replaces what was there.
	ISave.load_into(inv)
	_check(inv.unlocked.is_empty() and inv.worn_state().is_empty(), "a missing file is an empty inventory")

	# Round trip.
	inv.unlock(&"cap")
	inv.unlock(&"mail")
	inv.unlock(&"band")
	inv.unlock(&"loop")
	inv.equip(&"knight", &"cap")
	inv.equip(&"knight", &"band")
	inv.equip(&"wizard", &"loop")
	_check(ISave.save(inv), "save succeeds")
	_check(FileAccess.file_exists(file) and not FileAccess.file_exists(file + ".tmp"), "file written, tmp not left")
	_check(not FileAccess.file_exists(_base), "the camp save file is not created or touched")
	var back = InventoryS.new()
	var emitted := [0]
	back.changed.connect(func() -> void: emitted[0] += 1)
	ISave.load_into(back)
	_check(back.unlocked == [&"cap", &"mail", &"band", &"loop"], "the pool round-trips in order: %s" % [back.unlocked])
	_check(back.worn_state() == inv.worn_state(), "the loadouts round-trip: %s" % [back.worn_state()])
	_check(emitted[0] == 0, "loading does not emit changed")

	# Zero-length file: empty, no .bad.
	_write(file, "")
	ISave.load_into(back)
	_check(back.unlocked.is_empty() and not FileAccess.file_exists(file + ".bad"), "a zero-length file is an empty inventory")

	# Corrupt files go to .bad.
	for bad in ["{not json", "[1, 2]", "42", '{"version": 2, "unlocked": [], "worn": {}}', '{"unlocked": [], "worn": {}}',
			'{"version": 1, "unlocked": {}, "worn": {}}', '{"version": 1, "unlocked": [], "worn": []}',
			'{"version": 1, "unlocked": [5], "worn": {}}', '{"version": 1, "unlocked": [], "worn": {"knight": 3}}',
			'{"version": 1, "unlocked": ["cap"], "worn": {"knight": {"helmet": 7}}}']:
		DirAccess.remove_absolute(file + ".bad")
		_write(file, bad)
		ISave.load_into(back)
		_check(back.unlocked.is_empty() and FileAccess.file_exists(file + ".bad") and not FileAccess.file_exists(file), "invalid file %s is renamed to .bad and gives an empty inventory" % bad)
	DirAccess.remove_absolute(file + ".bad")

	# What loading drops.
	_write(file, JSON.stringify({version = 1, unlocked = ["cap", "ghost", "cap", "mail", "band"],
		worn = {knight = {helmet = "cap", ring_1 = "band", chestplate = "nope"}, wizard = {helmet = "band", chestplate = "mail", ring_1 = "cap", ring_2 = "loop"}}}))
	ISave.load_into(back)
	_check(back.unlocked == [&"cap", &"mail", &"band"], "unknown ids and duplicates are dropped from the pool: %s" % [back.unlocked])
	_check(back.worn(&"knight", &"helmet").id == &"cap" and back.worn(&"knight", &"ring_1").id == &"band", "valid worn entries stay")
	_check(back.worn(&"knight", &"chestplate") == null, "a worn unknown id is dropped")
	_check(back.worn(&"wizard", &"helmet") == null, "a ring in the helmet slot is dropped")
	_check(back.worn(&"wizard", &"chestplate").id == &"mail", "a valid entry of another character stays")
	_check(back.worn(&"wizard", &"ring_1") == null, "an item that does not fit its slot is dropped (cap in ring_1)")
	_check(back.worn(&"wizard", &"ring_2") == null, "'loop' is not unlocked, so its worn entry is dropped")
	_write(file, JSON.stringify({version = 1, unlocked = ["cap"], worn = {knight = {helmet = "cap"}, wizard = {helmet = "cap"}}}))
	ISave.load_into(back)
	_check(back.worn(&"knight", &"helmet") != null and back.worn(&"wizard", &"helmet") == null, "an item worn twice is kept once, by the first in the file")

	# The tmp fallback.
	DirAccess.remove_absolute(file)
	_write(file + ".tmp", JSON.stringify({version = 1, unlocked = ["cap"], worn = {}}))
	ISave.load_into(back)
	_check(back.unlocked == [&"cap"], "an interrupted write is recovered from the tmp file")
	DirAccess.remove_absolute(file + ".tmp")

	# GameSession: load_inventory reads the file without saving it again; a change writes it.
	var gs = root.get_node("GameSession")
	_write(file, JSON.stringify({version = 1, unlocked = ["cap", "mail"], worn = {knight = {helmet = "cap"}}}))
	var before := FileAccess.get_file_as_string(file)
	gs.load_inventory()
	_check(gs.inventory.unlocked == [&"cap", &"mail"] and gs.inventory.worn(&"knight", &"helmet").id == &"cap", "GameSession.load_inventory loads the file")
	_check(FileAccess.get_file_as_string(file) == before, "loading did not write the file")
	gs.inventory.unequip(&"knight", &"helmet")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(file))
	_check(saved is Dictionary and saved.worn.is_empty() and saved.unlocked == ["cap", "mail"], "a change autosaves to InventorySave.path(): %s" % [saved])
	_check(not FileAccess.file_exists(file + ".tmp"), "no tmp left after autosave")
	SG.override_path = null
	gs.inventory.set_state([], {})
	_clean()
	Reg.test_items.clear()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

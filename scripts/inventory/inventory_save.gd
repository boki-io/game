class_name InventorySave
extends RefCounted
## The inventory's save (spec 1.4): the pool and the loadouts in `<SaveGame.path()>.inventory`, a file of its own so the camp
## save and its tests stay as they are. Static, no autoload; only GameSession calls it. Saving is off exactly when SaveGame's is.

const VERSION := 1


## The file, or "" when saving is off (a headless run with no override). Read at the moment of every save and load.
static func path() -> String:
	var base := SaveGame.path()
	return "" if base == "" else base + ".inventory"


## Writes the file via a temp file renamed over it. False when saving is off or fails.
static func save(inv: Inventory) -> bool:
	var file_path := path()
	if file_path == "":
		return false
	var unlocked: Array[String] = []
	for id in inv.unlocked:
		unlocked.append(str(id))
	var worn := {}
	var state := inv.worn_state()
	for character_id in state:
		var slots := {}
		for slot in state[character_id]:
			slots[str(slot)] = str(state[character_id][slot])
		worn[str(character_id)] = slots
	var text := JSON.stringify({version = VERSION, unlocked = unlocked, worn = worn}, "\t")
	var tmp := file_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("InventorySave: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	var err := DirAccess.rename_absolute(tmp, file_path)
	if err != OK:
		push_warning("InventorySave: cannot rename %s over %s (error %d)" % [tmp, file_path, err])
		return false
	return true


## Replaces `inv`'s contents with the file's, without emitting `changed`. A missing, empty or disabled file is a new
## (empty) inventory; a file that fails the checks is renamed to `.bad` and also gives an empty one. Ids the registry no
## longer knows are dropped; a worn id that is not unlocked, does not fit its slot, or is already worn (the first one in
## the file wins) is dropped.
static func load_into(inv: Inventory) -> void:
	inv.set_state([], {})
	var file_path := path()
	if file_path == "":
		return
	var source := file_path
	if not FileAccess.file_exists(file_path):
		# A write that was interrupted after the tmp was complete but before the rename.
		if not FileAccess.file_exists(file_path + ".tmp"):
			return
		source = file_path + ".tmp"
	var text := FileAccess.get_file_as_string(source)
	if text.strip_edges() == "":
		return
	var parsed := _parse(text)
	if parsed.is_empty():
		push_warning("InventorySave: %s is not a valid save; keeping it as .bad and starting new" % source)
		DirAccess.rename_absolute(source, file_path + ".bad")
		return
	inv.set_state(parsed.unlocked, parsed.worn)


## The checked content of a save text ({unlocked, worn}), or {} when it is not a valid version 1 file.
static func _parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var root: Variant = json.data
	if not root is Dictionary or not _is_number(root.get("version")) or root.version != VERSION:
		return {}
	if not root.get("unlocked") is Array or not root.get("worn") is Dictionary:
		return {}
	var unlocked: Array[StringName] = []
	for value in root.unlocked:
		if not value is String:
			return {}
		var id := StringName(value)
		if ItemRegistry.find(id) != null and not id in unlocked:
			unlocked.append(id)
	var worn := {}
	var seen: Array[StringName] = []
	for character_key in root.worn:
		if not root.worn[character_key] is Dictionary:
			return {}
		var slots := {}
		for slot_key in root.worn[character_key]:
			var value: Variant = root.worn[character_key][slot_key]
			if not value is String:
				return {}
			var slot := StringName(slot_key)
			var id := StringName(value)
			var item := ItemRegistry.find(id)
			if item == null or not id in unlocked or id in seen or not slot in Inventory.slots_for(item.slot):
				continue
			seen.append(id)
			slots[slot] = id
		if not slots.is_empty():
			worn[StringName(character_key)] = slots
	return {unlocked = unlocked, worn = worn}


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT) or (typeof(value) == TYPE_FLOAT and is_finite(value))

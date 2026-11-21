class_name JourneySave
extends RefCounted
## The overworld's save (spec 1.6): one JSON file per character, `<SaveGame.path()>.journey.<character id>`. Static, no autoload.
## Saving is off exactly when SaveGame's is (`path()` is ""). Written through a temp file renamed over the file; loaded
## leniently: a missing or empty file is a new journey, a file that fails the checks is renamed `.bad` and also gives a new one,
## and what the world or the registries no longer know is dropped.

const VERSION := 1
const LEVEL_MAX := 99
const RELIC_LEVEL_MAX := 3  # PlayerRelics.MAX_LEVEL (not named here: that class needs autoloads, so tests could not preload this file)


## The file of a character, or "" when saving is off. Read at every save and load.
static func path(character_id: StringName) -> String:
	var base := SaveGame.path()
	return "" if base == "" else "%s.journey.%s" % [base, character_id]


static func save(j: Journey) -> bool:
	var file_path := path(j.character_id)
	if file_path == "":
		return false
	var progress := {level = j.progress.level, xp = j.progress.xp, upgrades = {}, relics = {}}
	for id in j.progress.upgrades:
		progress.upgrades[str(id)] = int(j.progress.upgrades[id])
	for id in j.progress.relics:
		progress.relics[str(id)] = int(j.progress.relics[id])
	var text := JSON.stringify({version = VERSION, position = [j.position.x, j.position.y], respawn = j.respawn,
		checkpoints = j.checkpoints, cleared = j.cleared, opened_gates = j.opened_gates,
		cleared_dens = j.cleared_dens,
		fog = Marshalls.raw_to_base64(j.fog), progress = progress, playtime = j.playtime,
		markers_version = j.markers_version}, "\t")
	var tmp := file_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("JourneySave: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	var err := DirAccess.rename_absolute(tmp, file_path)
	if err != OK:
		push_warning("JourneySave: cannot rename %s over %s (error %d)" % [tmp, file_path, err])
		return false
	return true


## The journey of `character_id`: the file's, or a new one.
static func load_for(character_id: StringName, world: WorldData) -> Journey:
	var fresh := Journey.new_for(character_id, world)
	var file_path := path(character_id)
	if file_path == "":
		return fresh
	var source := file_path
	if not FileAccess.file_exists(file_path):
		# A write that was interrupted after the tmp was complete but before the rename.
		if not FileAccess.file_exists(file_path + ".tmp"):
			return fresh
		source = file_path + ".tmp"
	var text := FileAccess.get_file_as_string(source)
	if text.strip_edges() == "":
		return fresh
	var j := _parse(text, character_id, world)
	if j == null:
		push_warning("JourneySave: %s is not a valid save; keeping it as .bad and starting new" % source)
		DirAccess.rename_absolute(source, file_path + ".bad")
		return fresh
	return j


static func _parse(text: String, character_id: StringName, world: WorldData) -> Journey:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var root: Variant = json.data
	if not root is Dictionary or not _is_number(root.get("version")) or root.version != VERSION:
		return null
	if not root.get("position") is Array or root.position.size() != 2 or not _is_number(root.position[0]) or not _is_number(root.position[1]):
		return null
	if not root.get("checkpoints") is Array or not root.get("cleared") is Array or not root.get("progress") is Dictionary:
		return null
	if not root.get("respawn") is String or not root.get("fog") is String:
		return null
	var j := Journey.new_for(character_id, world)
	# Names the world still knows: checkpoints are checkpoints or the start camp, cleared ones are caves, dungeons or the vault.
	for value in root.checkpoints:
		if not value is String:
			return null
		var m := world.marker_named(value)
		if not m.is_empty() and m.kind in ["checkpoint", "start_camp"] and not value in j.checkpoints:
			j.checkpoints.append(value)
	for value in root.cleared:
		if not value is String:
			return null
		var m := world.marker_named(value)
		if not m.is_empty() and m.kind in ["cave", "dungeon", "final_dungeon"] and not value in j.cleared:
			j.cleared.append(value)
	for value in root.get("opened_gates", []):
		if value is String and not value in j.opened_gates:
			j.opened_gates.append(value)
	for value in root.get("cleared_dens", []) if root.get("cleared_dens") is Array else []:
		if value is String and not value in j.cleared_dens:
			j.cleared_dens.append(value)
	j.respawn = root.respawn if root.respawn in j.checkpoints else j.checkpoints[0]
	# The position: on a walkable tile, else the respawn checkpoint.
	var pos := Vector2(float(root.position[0]), float(root.position[1]))
	pos = pos.clamp(Vector2.ZERO, Vector2(WorldData.SIZE * WorldData.TILE_PX - 1, WorldData.SIZE * WorldData.TILE_PX - 1))
	j.position = pos if world.is_walkable(WorldData.tile_of(pos)) else WorldData.marker_world(world.marker_named(j.respawn))
	# The fog: 62,500 bytes or reset.
	var fog := Marshalls.base64_to_raw(root.fog)
	if fog.size() == Journey.FOG_BYTES:
		j.fog = fog
	# Progress: clamped, ids converted back to StringName and unknown ones dropped (a bad value is a bad file).
	var progress: Dictionary = root.progress
	if not _is_number(progress.get("level")) or not _is_number(progress.get("xp")):
		return null
	if not progress.get("upgrades") is Dictionary or not progress.get("relics") is Dictionary:
		return null
	j.progress.level = clampi(int(progress.level), 1, LEVEL_MAX)
	j.progress.xp = maxi(int(progress.xp), 0)
	var pool_ids := {}
	for c in CharacterRegistry.all():
		if c.id == character_id:
			for u in c.upgrade_pool:
				pool_ids[u.id] = true
	for key in progress.upgrades:
		if not _is_number(progress.upgrades[key]):
			return null
		if pool_ids.has(StringName(key)):
			j.progress.upgrades[StringName(key)] = maxi(int(progress.upgrades[key]), 0)
	for key in progress.relics:
		if not _is_number(progress.relics[key]):
			return null
		if RelicRegistry.find(StringName(key)) != null:
			j.progress.relics[StringName(key)] = clampi(int(progress.relics[key]), 0, RELIC_LEVEL_MAX)
	j.playtime = maxf(float(root.get("playtime", 0.0)), 0.0) if _is_number(root.get("playtime")) else 0.0
	return j


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT) or (typeof(value) == TYPE_FLOAT and is_finite(value))

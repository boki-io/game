extends SceneTree
## Journey and JourneySave (spec 1.6): a new journey at the lit start camp, a round trip (progress keys come back as StringName,
## the fog, checkpoints, cleared markers), one file per character, a missing, empty or disabled file, corrupt files renamed `.bad`,
## repairs (unknown names, a blocked position, a bad fog), the `.tmp` fallback, and the camp save and inventory files untouched.
## Run: godot --headless --path . --script tests/overworld/journey_save.gd

const SG := preload("res://scripts/systems/save_game.gd")
const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const JourneyS := preload("res://scripts/overworld/journey.gd")
const JSave := preload("res://scripts/overworld/journey_save.gd")

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
	for who in ["knight", "wizard", "archer"]:
		for suffix in ["", ".tmp", ".bad"]:
			DirAccess.remove_absolute("%s.journey.%s%s" % [_base, who, suffix])
	for suffix in ["", ".tmp", ".bad", ".inventory"]:
		DirAccess.remove_absolute(_base + suffix)


func _init() -> void:
	await process_frame
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_journey_test_%d.json" % OS.get_process_id())
	_clean()
	var w = WorldDataS.shared()
	var start = w.start_marker()
	var cp = w.markers.filter(func(m): return m.kind == "checkpoint")[0]
	var cave = w.markers.filter(func(m): return m.kind == "cave")[0]

	# Saving is off with no path under headless.
	SG.override_path = ""
	_check(JSave.path(&"knight") == "", "disabled: no journey path")
	var j = JourneyS.new_for(&"knight", w)
	_check(not JSave.save(j), "save returns false when off")
	_check(JSave.load_for(&"knight", w).respawn == start.name, "a disabled load is a new journey")
	SG.override_path = _base
	_check(JSave.path(&"wizard") == _base + ".journey.wizard", "one file per character, next to the camp save: %s" % JSave.path(&"wizard"))

	# A new journey: at the start camp, lit, with the full progress shape and an empty fog.
	_check(j.position == w.marker_world(start) and j.respawn == start.name and j.checkpoints == [start.name], "a new journey starts at the lit start camp")
	_check(j.progress == {level = 1, xp = 0, upgrades = {}, relics = {}}, "a new journey has the full progress shape: %s" % [j.progress])
	_check(j.fog.size() == 62500 and j.cleared.is_empty() and j.markers_version == w.markers_version, "62,500 fog bytes, nothing cleared")
	_check(JSave.load_for(&"knight", w).position == j.position, "a missing file is a new journey")

	# Round trip.
	j.position = w.marker_world(cp)
	j.activate_checkpoint(cp.name)
	j.mark_cleared(cave.name)
	j.mark_den_cleared("camp", 12)
	j.mark_den_cleared("camp", 12)
	j.mark_den_cleared("cache", 3)
	j.fog[1234] = 1
	j.fog[62499] = 1
	j.progress = {level = 7, xp = 12, upgrades = {&"damage": 2}, relics = {&"fire_trail": 2}}
	j.playtime = 321.5
	_check(JSave.save(j), "save succeeds")
	_check(FileAccess.file_exists(_base + ".journey.knight") and not FileAccess.file_exists(_base + ".journey.knight.tmp"), "file written, tmp not left")
	_check(not FileAccess.file_exists(_base) and not FileAccess.file_exists(_base + ".inventory"), "the camp save and inventory files are not created")
	var back = JSave.load_for(&"knight", w)
	_check(back.position == j.position and back.respawn == cp.name and back.checkpoints == [start.name, cp.name] and back.cleared == [cave.name], "position, respawn, checkpoints and cleared round-trip")
	_check(back.fog == j.fog, "the fog round-trips")
	_check(back.cleared_dens == ["camp:12", "cache:3"] and back.is_den_cleared("camp", 12) and back.is_den_cleared("cache", 3) and not back.is_den_cleared("camp", 3), "cleared dens round-trip once each: %s" % [back.cleared_dens])
	_check(back.progress.level == 7 and back.progress.xp == 12, "level and xp round-trip")
	var upgrade_key = back.progress.upgrades.keys()[0] if not back.progress.upgrades.is_empty() else null
	_check(upgrade_key == null or typeof(upgrade_key) == TYPE_STRING_NAME, "upgrade keys come back as StringName")
	_check(back.progress.relics == {&"fire_trail": 2} and typeof(back.progress.relics.keys()[0]) == TYPE_STRING_NAME, "relic keys come back as StringName: %s" % [back.progress.relics])
	_check(is_equal_approx(back.playtime, 321.5), "playtime round-trips")

	# One file per character.
	var other = JSave.load_for(&"wizard", w)
	_check(other.position == w.marker_world(start) and other.cleared.is_empty(), "another character has their own (new) journey")
	var wiz = JourneyS.new_for(&"wizard", w)
	wiz.mark_cleared(cave.name)
	JSave.save(wiz)
	_check(JSave.load_for(&"knight", w).cleared == [cave.name] and JSave.load_for(&"wizard", w).character_id == &"wizard", "files are separate")

	# Zero-length file: new, no .bad.
	var file := _base + ".journey.knight"
	_write(file, "")
	_check(JSave.load_for(&"knight", w).position == w.marker_world(start) and not FileAccess.file_exists(file + ".bad"), "a zero-length file is a new journey")

	# Corrupt files go to .bad.
	for bad in ["{not json", "[1, 2]", "42", '{"version": 2}', '{"version": 1, "position": "x"}',
			'{"version": 1, "position": [1, 2], "checkpoints": {}, "cleared": [], "progress": {}, "respawn": "", "fog": ""}',
			'{"version": 1, "position": [1, 2], "checkpoints": [], "cleared": [], "progress": {"level": "x", "xp": 0, "upgrades": {}, "relics": {}}, "respawn": "", "fog": ""}',
			'{"version": 1, "position": [1, 2], "checkpoints": [3], "cleared": [], "progress": {"level": 1, "xp": 0, "upgrades": {}, "relics": {}}, "respawn": "", "fog": ""}']:
		DirAccess.remove_absolute(file + ".bad")
		_write(file, bad)
		var r = JSave.load_for(&"knight", w)
		_check(r.position == w.marker_world(start) and FileAccess.file_exists(file + ".bad") and not FileAccess.file_exists(file), "invalid file %s is renamed to .bad and gives a new journey" % bad)
	DirAccess.remove_absolute(file + ".bad")

	# Repairs: unknown names, a blocked position, a bad fog, clamps, unknown ids.
	var good_fog := Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))
	_write(file, JSON.stringify({version = 1, position = [5.0, 5.0], respawn = "Nowhere", checkpoints = ["Starting Camp", "Nowhere", cave.name, cp.name],
		cleared = [cave.name, "Gone Cave", cp.name], fog = good_fog,
		progress = {level = 500, xp = -4, upgrades = {damage = 3, nope = 9}, relics = {fire_trail = 9, nope = 1}}, playtime = -5}))
	var rep = JSave.load_for(&"knight", w)
	_check(rep.checkpoints == [start.name, cp.name], "unknown names and non-checkpoints are dropped from checkpoints: %s" % [rep.checkpoints])
	_check(rep.cleared == [cave.name], "unknown names and non-caves are dropped from cleared: %s" % [rep.cleared])
	_check(rep.respawn == start.name, "an unknown respawn falls back to the first checkpoint")
	_check(rep.position == w.marker_world(start), "a position on a blocked tile snaps to the respawn checkpoint (%s)" % [rep.position])
	_check(rep.fog.size() == 62500 and rep.fog[0] == 0, "a fog of the wrong length is reset")
	_check(rep.progress.level == 99 and rep.progress.xp == 0 and rep.playtime == 0.0, "level, xp and playtime are clamped")
	_check(not rep.progress.upgrades.has(&"nope") and not rep.progress.relics.has(&"nope"), "unknown upgrade and relic ids are dropped")
	_check(rep.progress.relics.get(&"fire_trail", 0) == 3, "a relic level is clamped to 3")

	# The tmp fallback.
	DirAccess.remove_absolute(file)
	_write(file + ".tmp", JSON.stringify({version = 1, position = [w.marker_world(cp).x, w.marker_world(cp).y], respawn = cp.name, checkpoints = ["Starting Camp", cp.name], cleared = [], fog = "",
		progress = {level = 3, xp = 1, upgrades = {}, relics = {}}}))
	var rec = JSave.load_for(&"knight", w)
	_check(rec.progress.level == 3 and rec.respawn == cp.name, "an interrupted write is recovered from the tmp file")
	_check(rec.cleared_dens.is_empty(), "an old file without cleared_dens loads with none")
	DirAccess.remove_absolute(file + ".tmp")

	# Journey helpers.
	var h = JourneyS.new_for(&"archer", w)
	_check(h.activate_checkpoint(cp.name) and not h.activate_checkpoint(cp.name) and h.respawn == cp.name, "activate_checkpoint lights once and moves the respawn")
	h.mark_cleared(cave.name)
	h.mark_cleared(cave.name)
	_check(h.is_cleared(cave.name) and h.cleared.size() == 1, "mark_cleared once")
	_check(h.gate_open("Mossgate Pass"), "every gate is open in spec 1.6")
	SG.override_path = null
	_clean()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

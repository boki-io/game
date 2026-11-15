extends SceneTree
## Path generator: shape, connections (spec 3.2), tier rules and value ranges (4.1), names, thumbnails and seeds.
## Run: godot --headless --path . --script tests/path_generator.gd

const Generator := preload("res://scripts/stages/path_generator.gd")
const StageDataScript := preload("res://scripts/stages/stage_data.gd")
const SEED_COUNT := 30  # the spec asks for 1000+; reduced to 30 on the user's instruction (see AGENT_DECISION_LOG.md)

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 12:
			print("FAIL: ", what)


func _in_range(v: int, r: Array) -> bool:
	return v >= r[0] and v <= r[1] and (v - r[0]) % 5 == 0


func _signature(path) -> Array:
	var out: Array = [path.edges]
	for s in path.all_stages():
		out.append([s.name, s.tier, s.population, s.difficulty, s.experience, s.currency, s.thumbnail.resource_path])
	return out


func _init() -> void:
	await process_frame
	var middle_seen := {0: 0, 2: 0}
	for sd in SEED_COUNT:
		var tag := "seed %d: " % sd
		var path = Generator.generate(sd)
		_check(path.column_count() == 3 and path.stage_count() == 7, tag + "3 columns, 7 stages")
		_check(path.columns[0].size() == 3 and path.columns[1].size() == 3 and path.columns[2].size() == 1,
			tag + "3 + 3 + 1")

		# 3.2 connections
		_check(path.next_rows(0, 0) == [0, 1], tag + "top -> top, middle")
		_check(path.next_rows(0, 2) == [1, 2], tag + "bottom -> middle, bottom")
		var mid: Array = path.next_rows(0, 1)
		_check(mid.size() == 2 and mid.has(1) and (mid.has(0) or mid.has(2)), tag + "middle -> middle + one neighbour")
		middle_seen[0 if mid.has(0) else 2] += 1
		for row in 3:
			_check(path.next_rows(0, row).size() == 2, tag + "exactly 2 options after column 1 (row %d)" % row)
			_check(path.next_rows(1, row) == [0], tag + "every column 2 stage leads to the final stage")
		_check(path.next_rows(2, 0).is_empty(), tag + "the final stage has no edges")
		# Every column 2 stage is reachable from at least one column 1 stage.
		var reachable := {}
		for row in 3:
			for r in path.next_rows(0, row):
				reachable[r] = true
		_check(reachable.size() == 3, tag + "every column 2 stage is reachable")

		# 4.1 tiers and ranges
		for column in 2:
			var tiers := {}
			for s in path.columns[column]:
				tiers[s.tier] = true
			_check(tiers.size() == 3, tag + "column %d has one Easy, one Normal, one Hard" % (column + 1))
			# So the two options after column 1 differ in tier.
		for row in 3:
			var options: Array = path.next_rows(0, row)
			_check(path.columns[1][options[0]].tier != path.columns[1][options[1]].tier, tag + "the two options differ in tier")
		_check(path.columns[2][0].tier == StageDataScript.Tier.HARD, tag + "the final stage is Hard")
		for s in path.all_stages():
			var r: Dictionary = Generator.RANGES[s.tier]
			_check(_in_range(s.population, r.population), tag + "%s population %d" % [s.name, s.population])
			_check(_in_range(s.difficulty, r.difficulty), tag + "%s difficulty %d" % [s.name, s.difficulty])
			_check(_in_range(s.experience, r.experience), tag + "%s experience %d" % [s.name, s.experience])
			_check(_in_range(s.currency, r.currency), tag + "%s gold %d" % [s.name, s.currency])

		# Names and thumbnails
		var names := {}
		var thumbs := {}
		for s in path.all_stages():
			names[s.name] = true
			_check(s.thumbnail != null, tag + "has a thumbnail")
			if s.thumbnail:
				thumbs[s.thumbnail.resource_path] = true
		_check(names.size() == 7, tag + "7 distinct names")
		_check(thumbs.size() == 7, tag + "7 distinct thumbnail paths")

		# Seed reproducibility
		_check(_signature(path) == _signature(Generator.generate(sd)), tag + "same seed, same path")

	_check(Generator.NAMES.size() >= 7 and Generator.THUMBNAIL_COUNT >= 7, "pools hold at least 7 names and thumbnails")
	_check(middle_seen[0] > 0 and middle_seen[2] > 0, "the middle stage's neighbour is rolled both ways over %d seeds" % SEED_COUNT)
	# Different seeds give different paths (not every pair, but not all the same).
	var distinct := {}
	for sd in SEED_COUNT:
		distinct[str(_signature(Generator.generate(sd)))] = true
	_check(distinct.size() > SEED_COUNT / 2, "different seeds give different paths")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## Stage modifiers: additive percentages, the alive cap ceiling, XP scaling, and the SpawnDirector applying them.
## Run: godot --headless --path . --script tests/stage_modifiers.gd

const StageDataScript := preload("res://scripts/stages/stage_data.gd")
var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var s = StageDataScript.new()
	_check(s.scaled_rate(1.0) == 1.0 and s.scaled_cap(300) == 300 and s.scaled_xp(3) == 3, "0% changes nothing")
	_check(is_equal_approx(s.coin_chance(), 0.25), "default coin chance is 25%")

	s.population = 20
	_check(is_equal_approx(s.scaled_rate(1.0), 1.2), "+20 population: rate x1.2")
	_check(is_equal_approx(s.scaled_rate(8.0), 9.6), "+20 population: end rate")
	_check(s.scaled_cap(200) == 240, "+20 population: cap 200 -> 240")
	_check(s.scaled_cap(300) == 300, "+20 population: cap stays at the 300 ceiling")
	s.population = -20
	_check(s.scaled_cap(300) == 240, "-20 population: cap 300 -> 240")
	_check(is_equal_approx(s.scaled_rate(1.0), 0.8), "-20 population: rate x0.8")

	# Additive, not multiplied: +10% then +10% is not 21%.
	_check(is_equal_approx(StageDataScript.add_percent(100.0, 10), 110.0), "+10% of 100 is 110")

	s.experience = 20
	_check(s.scaled_xp(1) == 1 and s.scaled_xp(5) == 6, "+20 xp: 1 -> 1, 5 -> 6")
	s.experience = -15
	_check(s.scaled_xp(1) == 1, "negative xp never goes below 1 for a mob that drops XP")
	_check(s.scaled_xp(0) == 0, "a mob with xp_drop 0 stays at 0")
	s.experience = 30
	_check(s.scaled_xp(0) == 0, "xp_drop 0 stays 0 with a bonus")

	# The director applies a stage's population to its rate and cap.
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var d = main.spawn_director
	_check(is_equal_approx(d.start_rate, 0.85) and is_equal_approx(d.end_rate, 6.8) and d.alive_cap == 300,
		"no stage: base rate and cap")
	var hard = StageDataScript.new()
	hard.population = 15
	d.apply_stage(hard)
	_check(is_equal_approx(d.start_rate, 0.85 * 1.15) and is_equal_approx(d.end_rate, 6.8 * 1.15) and d.alive_cap == 300,
		"+15 population: rate x1.15, cap held at 300")
	main.queue_free()
	await process_frame

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

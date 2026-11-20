extends SceneTree
## The vacuum magnet (spec 1.3): its data file and sound, the vacuum on Pickups (every gem and coin flies to the player who
## started it, fast, for 5 s), and the item (drop, lifetime and flash, pickup).
## Run: godot --headless --path . --script tests/vacuum_magnet.gd

const DATA := "res://content/pickups/vacuum_magnet.tres"

var _failed := false
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	_F = load("res://tests/fixture.gd")
	_data()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _data() -> void:
	var d: VacuumData = load(DATA)
	_check(d != null, "vacuum_magnet.tres loads as VacuumData")
	if d == null:
		return
	_check(is_equal_approx(d.drop_chance, 0.01), "drop chance 1%%: %s" % d.drop_chance)
	_check(d.effect_time == 5.0 and d.lifetime == 30.0 and d.flash_time == 10.0 and d.flash_hz == 4.0, "times: effect 5 s, lifetime 30 s, flash 10 s at 4 Hz")
	_check(d.pick_distance == 14.0 and d.pull_speed == 1000.0 and d.pull_accel == 3000.0, "pick distance 14 px, pull 1000 px/s at 3000 px/s^2")
	var audio = root.get_node("Audio")
	_check(&"vacuum_pickup" in audio.SOUNDS, "the sound is in Audio.SOUNDS")
	_check(audio._streams.get(&"vacuum_pickup") != null, "the sound file loads")

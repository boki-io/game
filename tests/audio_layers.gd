extends SceneTree
## Audio (spec v0.9): pitch variation within each sound's spread, exactly 1.0 for sounds without one (also on a reused voice),
## and the log of started voices the tests read. Layered impacts are added in a later step.
## Run: godot --headless --path . --script tests/audio_layers.gd

var _failed := false
var _audio: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## The pitch of the voice the last play started (read from the log the code owns).
func _last_pitch() -> float:
	return _audio.recent.back().pitch


func _init() -> void:
	await process_frame
	_audio = root.get_node("Audio")

	# 40 plays of enemy_hit (spread 0.08): in range and not all equal.
	var lo := 9.0
	var hi := 0.0
	for i in 40:
		_audio.recent.clear()
		_audio._last_ms.clear()  # the 40 ms throttle is tested on its own; headless timers are too coarse to wait it out
		_audio.play(&"enemy_hit")
		if _audio.recent.is_empty():
			_check(false, "enemy_hit was not played")
			break
		lo = minf(lo, _last_pitch())
		hi = maxf(hi, _last_pitch())
	_check(lo >= 0.92 - 0.0001 and hi <= 1.08 + 0.0001, "enemy_hit pitch stays within 0.08 (%s to %s)" % [lo, hi])
	_check(hi - lo > 0.04, "enemy_hit pitch varies (%s to %s)" % [lo, hi])

	# A sound without a spread is exactly 1.0 every time.
	var exact := true
	for i in 6:
		_audio.recent.clear()
		_audio._last_ms.clear()
		_audio.play(&"menu_click")
		exact = exact and not _audio.recent.is_empty() and _last_pitch() == 1.0
	_check(exact, "menu_click always plays at exactly 1.0")

	# Voices are reused: fill the whole pool with varied pitches, then play a spread-0 stream on every voice.
	var stream: AudioStream = load("res://assets/audio/enemy_hit.wav")
	for i in _audio.POOL_SIZE * 2:
		_audio.play_stream(stream, -30.0, 0.08)
	_audio.recent.clear()
	for i in _audio.POOL_SIZE:
		_audio.play_stream(stream, -30.0, 0.0)
	var stale := 0
	for p in _audio._players:
		if p.pitch_scale != 1.0:
			stale += 1
	_check(stale == 0, "%d reused voices kept a stale pitch" % stale)
	var all_one := true
	for e in _audio.recent:
		all_one = all_one and e.pitch == 1.0
	_check(_audio.recent.size() == _audio.POOL_SIZE and all_one, "the spread-0 plays are all logged at 1.0")

	# The log is capped.
	for i in 60:
		_audio.play_stream(stream, -30.0, 0.0)
	_check(_audio.recent.size() == _audio.RECENT_MAX, "the voice log keeps %d, got %d" % [_audio.RECENT_MAX, _audio.recent.size()])

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

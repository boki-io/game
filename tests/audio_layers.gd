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

	await _layer_tests()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## How many voices an impact starts (the throttle record is cleared so layers that share a name are not skipped).
func _voices(kind: StringName, strength: float) -> int:
	_audio.recent.clear()
	_audio._last_ms.clear()
	_audio.impact(kind, strength)
	return _audio.recent.size()


func _layer_tests() -> void:
	# Every sound in the list has its file and a line in the generator (CLAUDE.md: three places).
	var generator := FileAccess.get_file_as_string("res://tools/gen_sfx.py")
	var missing: Array[String] = []
	for sound in _audio.SOUNDS:
		if not FileAccess.file_exists("res://assets/audio/%s.wav" % sound) or not generator.contains('save("%s"' % sound):
			missing.append(str(sound))
	_check(missing.is_empty(), "sounds without a file or a generator line: %s" % [missing])
	_check(_audio.POOL_SIZE == 16, "the pool is 16 voices")

	# A hit that does not kill: the hit sound and a crack, plus a thud once it is thick. A kill: the death sound and a pop, plus a thud under a big body.
	_check(_voices(&"hit", 0.1) == 2, "a light hit starts 2 voices")
	_check(_voices(&"hit", 0.5) == 3, "a heavy hit starts 3 voices")
	_check(_voices(&"hit", 0.39) == 2 and _voices(&"hit", 0.4) == 3, "the hit thud starts at strength 0.4")
	_check(_voices(&"kill", 0.3) == 2, "a small kill starts 2 voices")
	_check(_voices(&"kill", 1.0) == 3, "a big kill starts 3 voices")
	_check(_voices(&"kill", 0.49) == 2 and _voices(&"kill", 0.5) == 3, "the kill thud starts at strength 0.5")
	_check(_voices(&"hit", 5.0) == 3, "a strength over 1 is clamped")
	# The layers do not vary in pitch; the hit and death sounds do.
	_audio.recent.clear()
	_audio._last_ms.clear()
	_audio.impact(&"hit", 1.0)
	var layers_exact := true
	for e in _audio.recent:
		if e.name in [&"impact_crack", &"impact_thud"]:
			layers_exact = layers_exact and e.pitch == 1.0
	_check(layers_exact, "the crack and the thud play at exactly 1.0")

	# A layer whose file is missing is skipped without an error.
	var saved = _audio._streams[&"impact_crack"]
	_audio._streams.erase(&"impact_crack")
	_check(_voices(&"hit", 0.5) == 2, "a missing layer file is skipped")
	_audio._streams[&"impact_crack"] = saved

	# An ability with a layer starts 2 voices (Slam: slam and the boom), one without starts 1 (Slash).
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 3)
	var p = F.player()
	var slam = load("res://content/characters/knight/abilities/slam/ability.tres")
	var slash = load("res://content/characters/knight/abilities/slash/ability.tres")
	_check(slam.sfx_layer != null and slash.sfx_layer == null, "only Slam has a layer")
	_audio.recent.clear()
	p.caster.play_sfx(slam)
	_check(_audio.recent.size() == 2, "Slam starts 2 voices, got %d" % _audio.recent.size())
	_check(absf(_audio.recent[0].pitch - 1.0) <= 0.04 and _audio.recent[1].pitch == 1.0, "the ability stream varies by 0.04 and its layer does not")
	_audio.recent.clear()
	p.caster.play_sfx(slash)
	_check(_audio.recent.size() == 1, "Slash starts 1 voice, got %d" % _audio.recent.size())
	main.queue_free()
	await process_frame

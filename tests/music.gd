extends SceneTree
## Music (the Audio autoload): every playlist track is an mp3 that loads, a playlist starts a track of its own list, asking for it again
## changes nothing, another playlist replaces it, a finished track hands over to the next (never the same one back to back), stop and an
## unknown name end the music. The scenes pick the playlist: the hub and the select screen `menu`, the overworld `world`, the arena none.
## Run: godot --headless --path . --script tests/music.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _init() -> void:
	await process_frame
	var audio := root.get_node("Audio")
	var lists: Dictionary = audio.PLAYLISTS
	_check(lists.has(&"menu") and lists.has(&"world"), "a menu and a world playlist")
	_check((lists[&"menu"] as Array).size() >= 2 and (lists[&"world"] as Array).size() >= 4, "two menu tracks and four world songs")
	for name in lists:
		for t in lists[name]:
			var stream = load(audio._track_path(t))
			_check(stream is AudioStream and stream.get_length() > 30.0, "%s loads and is a real song" % t)

	_check(audio.music_playlist == &"", "no music before anything asks")
	audio.music(&"menu")
	await _wait(0.8)
	_check(audio.music_playlist == &"menu" and audio.music_track in lists[&"menu"] and audio._music.playing, "menu music plays a menu track (%s)" % audio.music_track)
	var first: String = audio.music_track
	audio.music(&"menu")
	await _wait(0.2)
	_check(audio.music_track == first, "asking for the playing playlist changes nothing")

	audio.music(&"world")
	await _wait(0.8)
	_check(audio.music_playlist == &"world" and audio.music_track in lists[&"world"] and audio._music.playing, "world music replaces it (%s)" % audio.music_track)

	var seen := {}
	for i in 8:
		var before: String = audio.music_track
		audio._music.finished.emit()
		await process_frame
		_check(audio.music_track != before and audio.music_track in lists[&"world"], "a finished track hands over to another world song (%s -> %s)" % [before, audio.music_track])
		seen[audio.music_track] = true
	_check(seen.size() >= 3, "the playlist moves through its songs (%d different)" % seen.size())

	audio.stop_music(0.1)
	await _wait(0.4)
	_check(audio.music_playlist == &"" and not audio._music.playing, "stop ends the music")
	audio.music(&"nothing")
	await _wait(0.2)
	_check(audio.music_playlist == &"" and not audio._music.playing, "an unknown playlist plays nothing")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## The sound settings: a Music and an SFX bus under Master with the music player and every effect voice on them, the two levels
## (0 to 1) set the buses (0 mutes) and are saved next to the camp save and read back (a missing or broken file means full volume),
## and the pause menu's Settings button opens a panel whose sliders change and save the levels; Esc closes the panel and not the menu.
## Run: godot --headless --path . --script tests/sound_settings.gd

const SG := preload("res://scripts/systems/save_game.gd")

var _failed := false
var _base := ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _clean() -> void:
	for suffix in ["", ".tmp"]:
		DirAccess.remove_absolute(_base + ".settings" + suffix)


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame
	await process_frame


func _init() -> void:
	await process_frame
	var audio := root.get_node("Audio")
	var tmp_dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_base = tmp_dir.path_join("hero_horde_sound_test_%d.json" % OS.get_process_id())
	SG.override_path = _base
	_clean()

	var m := AudioServer.get_bus_index("Music")
	var s := AudioServer.get_bus_index("SFX")
	_check(m != -1 and s != -1, "a Music and an SFX bus exist")
	_check(AudioServer.get_bus_send(m) == &"Master" and AudioServer.get_bus_send(s) == &"Master", "both send to Master")
	_check(audio._music.bus == &"Music", "the music player is on the Music bus")
	var all_sfx := true
	for p in audio._players:
		all_sfx = all_sfx and p.bus == &"SFX"
	_check(all_sfx, "every effect voice is on the SFX bus")

	audio.load_settings()
	_check(audio.music_volume == 1.0 and audio.effects_volume == 1.0, "no file means full volume")
	audio.set_music_volume(0.5)
	audio.set_effects_volume(0.0)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(m), linear_to_db(0.5)) and not AudioServer.is_bus_mute(m), "half music is about -6 dB")
	_check(AudioServer.is_bus_mute(s), "zero effects mutes the SFX bus")
	_check(FileAccess.file_exists(_base + ".settings"), "the levels are saved")
	audio.set_music_volume(1.0, false)
	audio.set_effects_volume(1.0, false)
	audio.load_settings()
	_check(is_equal_approx(audio.music_volume, 0.5) and audio.effects_volume == 0.0, "the saved levels are read back")
	audio.set_music_volume(7.0, false)
	_check(audio.music_volume == 1.0, "a level is clamped to 0..1")

	var f := FileAccess.open(_base + ".settings", FileAccess.WRITE)
	f.store_string("not json {")
	f.close()
	audio.load_settings()
	_check(audio.music_volume == 1.0 and audio.effects_volume == 1.0, "a broken file means full volume")

	# the pause menu and the panel
	var menu = load("res://scripts/ui/pause_menu.gd").new()
	menu.hub_mode = true
	root.add_child(menu)
	await process_frame
	var panel: Control = menu.get_node("SettingsPanel")
	_check(menu._settings_button != null and not panel.visible, "the pause menu has a Settings button and the panel starts closed")
	audio.set_music_volume(0.3, false)
	audio.set_effects_volume(0.8, false)
	menu.visible = true
	menu._settings_button.pressed.emit()
	await process_frame
	_check(panel.visible, "Settings opens the panel")
	_check(is_equal_approx(panel._music.value, 0.3) and is_equal_approx(panel._effects.value, 0.8), "the sliders show the current levels")
	panel._music.value = 0.65
	panel._effects.value = 0.25
	_check(is_equal_approx(audio.music_volume, 0.65) and is_equal_approx(audio.effects_volume, 0.25), "moving a slider sets the level")
	_check(FileAccess.file_exists(_base + ".settings"), "and saves it")
	while root.get_node("SceneFader").busy:  # the pause keys are ignored during a scene fade
		await process_frame
	await _press(&"pause")
	_check(not panel.visible and menu.visible, "Esc closes the panel and leaves the pause menu open")
	panel.open()
	panel._back.pressed.emit()
	_check(not panel.visible, "Back closes the panel")

	audio.set_music_volume(1.0, false)
	audio.set_effects_volume(1.0, false)
	_clean()
	SG.override_path = null
	menu.queue_free()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

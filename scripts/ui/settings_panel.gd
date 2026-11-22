class_name SettingsPanel
extends Control
## The sound settings (opened from the pause menu): a Music and an Effects slider (0 to 100 %), saved at once through the Audio
## autoload. Esc or Back closes it. It works while the tree is paused.

signal dismissed

const STEP := 0.05

var _music: HSlider
var _effects: HSlider
var _back: Button
var _music_label: Label
var _effects_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiKit.label("SETTINGS", 16))
	_music = _slider()
	_music_label = UiKit.label("", 10)
	box.add_child(_row("Music", _music, _music_label))
	_effects = _slider()
	_effects_label = UiKit.label("", 10)
	box.add_child(_row("Effects", _effects, _effects_label))
	_back = UiKit.button("Back")
	_back.pressed.connect(close)
	box.add_child(_back)
	add_child(UiKit.centered(box))
	_music.value_changed.connect(_on_music)
	_effects.value_changed.connect(_on_effects)


func _slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = STEP
	s.custom_minimum_size = Vector2(110, 12)
	s.focus_mode = Control.FOCUS_ALL
	return s


func _row(title: String, slider: HSlider, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := UiKit.label(title, 10)
	name_label.custom_minimum_size = Vector2(44, 0)
	row.add_child(name_label)
	row.add_child(slider)
	value_label.custom_minimum_size = Vector2(30, 0)
	row.add_child(value_label)
	return row


func open() -> void:
	var audio := get_node("/root/Audio")
	_music.set_value_no_signal(audio.music_volume)
	_effects.set_value_no_signal(audio.effects_volume)
	_show_values()
	visible = true
	_music.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	dismissed.emit()


func _show_values() -> void:
	_music_label.text = "%d%%" % roundi(_music.value * 100.0)
	_effects_label.text = "%d%%" % roundi(_effects.value * 100.0)


func _on_music(v: float) -> void:
	get_node("/root/Audio").set_music_volume(v)
	_show_values()


func _on_effects(v: float) -> void:
	var audio := get_node("/root/Audio")
	audio.set_effects_volume(v)
	audio.play(&"menu_click")  # a sample at the new level
	_show_values()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not SceneFader.busy and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()

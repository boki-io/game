extends Control
## Esc / Start pauses. In a run: Continue, Settings (sound levels), Return to Hub (asks "Abandon this run?"), Exit. In the hub: Continue, Exit. In the
## overworld (`overworld_mode`): Continue, Return to Hub and Exit, which only ask the overworld to save and leave (signals).
## Ignored while the level-up or end screen is up (absent in the hub) and during a scene fade.

@export var level_up_menu: LevelUpMenu
@export var end_screen: Control
## The hub has no run to abandon, so the Return to Hub button is left out.
@export var hub_mode := false
## The overworld (spec 1.6): Return to Hub and Exit emit a signal instead of acting, so the overworld saves the journey first.
@export var overworld_mode := false

signal return_to_hub_requested
signal exit_requested

var _continue: Button
var _return: Button
var _prompt: AbandonPrompt
var _settings: SettingsPanel
var _settings_button: Button


func _ready() -> void:
	visible = false
	add_child(UiKit.dim(0.6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiKit.label("PAUSED", 16))
	_continue = UiKit.button("Continue")
	_continue.pressed.connect(_resume)
	box.add_child(_continue)
	_settings_button = UiKit.button("Settings")
	_settings_button.pressed.connect(func() -> void: _settings.open())
	box.add_child(_settings_button)
	if overworld_mode:
		_return = UiKit.button("Return to Hub")
		_return.pressed.connect(func() -> void: return_to_hub_requested.emit())
		box.add_child(_return)
	elif not hub_mode:
		_return = UiKit.button("Return to Hub" if GameSession.dungeon == null else "Leave the dungeon")
		_return.pressed.connect(func() -> void: _prompt.open())
		box.add_child(_return)
	var exit := UiKit.button("Exit")
	exit.pressed.connect(func() -> void: exit_requested.emit() if overworld_mode else get_tree().quit())
	box.add_child(exit)
	add_child(UiKit.centered(box))
	_settings = SettingsPanel.new()
	_settings.name = "SettingsPanel"
	_settings.dismissed.connect(func() -> void: _settings_button.grab_focus.call_deferred())
	add_child(_settings)
	if not hub_mode and not overworld_mode:
		_prompt = AbandonPrompt.new()
		_prompt.name = "AbandonPrompt"
		_prompt.dismissed.connect(func() -> void: _return.grab_focus.call_deferred())
		add_child(_prompt)


func _unhandled_input(event: InputEvent) -> void:
	if SceneFader.busy or not event.is_action_pressed(&"pause"):
		return
	if visible:
		_resume()
	elif _can_open():
		visible = true
		get_tree().paused = true
		_continue.grab_focus.call_deferred()
	get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if get_tree().paused:
		return false
	if level_up_menu and level_up_menu.active:
		return false
	return end_screen == null or not end_screen.visible


func _resume() -> void:
	visible = false
	get_tree().paused = false

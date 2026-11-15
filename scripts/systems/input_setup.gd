extends Node
## Registers the keyboard Input Map actions at startup.
## Gamepads are polled per device by PlayerInput so each player can own a pad.

const KEY_ACTIONS := {
	&"move_left": KEY_A,
	&"move_right": KEY_D,
	&"move_up": KEY_W,
	&"move_down": KEY_S,
	&"ability_q": KEY_Q,
	&"ability_e": KEY_E,
	&"ability_r": KEY_R,
	&"pause": KEY_ESCAPE,
	&"debug_toggle": KEY_F3,
	&"hub_confirm": KEY_ENTER,
	&"interact": KEY_F,
	&"hub_info": KEY_I,
}

## Extra keys for actions that have more than one (the primary key is in KEY_ACTIONS).
const EXTRA_KEYS := {
	&"hub_confirm": [KEY_KP_ENTER, KEY_F],
}

const HUB_LEFT := &"hub_left"
const HUB_RIGHT := &"hub_right"


func _ready() -> void:
	for action: StringName in KEY_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ACTIONS[action]
		InputMap.action_add_event(action, event)
	for action: StringName in EXTRA_KEYS:
		for key: Key in EXTRA_KEYS[action]:
			var extra := InputEventKey.new()
			extra.physical_keycode = key
			InputMap.action_add_event(action, extra)
	# Browsing: A / D and the arrows, plus the D-pad. Separate actions so they stay free of walking later.
	_add_action(HUB_LEFT, [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT])
	_add_action(HUB_RIGHT, [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT])
	_add_stick(HUB_LEFT, -1.0)
	_add_stick(HUB_RIGHT, 1.0)
	_add_buttons(&"pause", [JOY_BUTTON_START])
	_add_buttons(&"hub_confirm", [JOY_BUTTON_A])
	_add_buttons(&"interact", [JOY_BUTTON_A])
	_add_buttons(&"hub_info", [JOY_BUTTON_BACK])


func _add_action(action: StringName, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	_add_buttons(action, buttons)


## A stick flick counts once per push: the action fires when the axis crosses its deadzone.
func _add_stick(action: StringName, direction: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = direction
	InputMap.action_add_event(action, event)


func _add_buttons(action: StringName, buttons: Array) -> void:
	for button: JoyButton in buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)

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
}


func _ready() -> void:
	for action: StringName in KEY_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ACTIONS[action]
		InputMap.action_add_event(action, event)

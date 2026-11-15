class_name PlayerInput
extends Node
## Turns device input into move_vector and aim_vector. Combat code reads only these.
## device_id: -1 = keyboard and mouse, 0+ = that gamepad.

signal ability_pressed(slot: StringName)

const TRIGGER_THRESHOLD := 0.5
const MOVE_DEADZONE := 0.2
const STICK_DEADZONE := 0.25

@export var device_id: int = -1
## Solo convenience: the keyboard player can also be driven by the first gamepad.
@export var gamepad_fallback: bool = true

var move_vector := Vector2.ZERO
var aim_vector := Vector2.RIGHT

var _has_aim_input := false
var _mouse_active := false
var _last_mouse_screen := Vector2.INF
var _pad_prev: Dictionary = {}  # slot -> bool, for gamepad edge detection


func _physics_process(_delta: float) -> void:
	var pad := _active_pad()
	move_vector = _read_move(pad)
	_update_aim(pad)
	_poll_abilities(pad)


func _poll_abilities(pad: int) -> void:
	for slot: StringName in [&"q", &"e", &"r"]:
		var pressed := false
		if device_id == -1 and Input.is_action_just_pressed(StringName("ability_%s" % slot)):
			pressed = true
		if pad >= 0:
			var down := _pad_down(pad, slot)
			if down and not _pad_prev.get(slot, false):
				pressed = true
			_pad_prev[slot] = down
		if pressed:
			ability_pressed.emit(slot)


func _pad_down(pad: int, slot: StringName) -> bool:
	match slot:
		&"q":
			return Input.is_joy_button_pressed(pad, JOY_BUTTON_X)
		&"e":
			return Input.is_joy_button_pressed(pad, JOY_BUTTON_Y)
		_:
			return Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD


func _active_pad() -> int:
	if device_id >= 0:
		return device_id
	if gamepad_fallback:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			return pads[0]
	return -1


func _read_move(pad: int) -> Vector2:
	var v := Vector2.ZERO
	if device_id == -1:
		v = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if v == Vector2.ZERO and pad >= 0:
		v = _stick(pad, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, MOVE_DEADZONE)
	return v


func _update_aim(pad: int) -> void:
	var body := get_parent() as Node2D
	if device_id == -1:
		var mouse_screen := body.get_viewport().get_mouse_position()
		if _last_mouse_screen != Vector2.INF and mouse_screen != _last_mouse_screen:
			_mouse_active = true
		_last_mouse_screen = mouse_screen

	if pad >= 0:
		var s := _stick(pad, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, STICK_DEADZONE)
		if s != Vector2.ZERO:
			aim_vector = s.normalized()
			_has_aim_input = true
			_mouse_active = false
			return

	if _mouse_active:
		var d := body.get_global_mouse_position() - body.global_position
		if d.length_squared() > 1.0:
			aim_vector = d.normalized()
			_has_aim_input = true
			return

	# No aim input yet: fall back to the last movement direction.
	# Once aim input exists, the last aim direction is kept on release.
	if not _has_aim_input and move_vector != Vector2.ZERO:
		aim_vector = move_vector.normalized()


func _stick(pad: int, axis_x: JoyAxis, axis_y: JoyAxis, deadzone: float) -> Vector2:
	var v := Vector2(Input.get_joy_axis(pad, axis_x), Input.get_joy_axis(pad, axis_y))
	if v.length() < deadzone:
		return Vector2.ZERO
	return v.limit_length(1.0)

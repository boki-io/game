class_name CameraFollow
extends Camera2D
## Follows the nearest player (to its own position), stays inside the arena, and can shake.

var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_total := 0.01


static func shake(node: Node, strength: float, duration: float) -> void:
	var cam := node.get_tree().get_first_node_in_group(&"camera") as CameraFollow
	if cam:
		cam._start_shake(strength, duration)


func _ready() -> void:
	add_to_group(&"camera")
	limit_left = 0
	limit_top = 0
	limit_right = Arena.SIZE.x
	limit_bottom = Arena.SIZE.y
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _physics_process(delta: float) -> void:
	var target: Player = PlayerRegistry.nearest(global_position)
	if target:
		# Snap to whole pixels so the sprite doesn't shimmer at low resolution.
		global_position = (target.global_position - Vector2(0, 12)).round()
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := maxf(_shake_time, 0.0) / _shake_total
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)).round() * _shake_strength * k
	else:
		offset = Vector2.ZERO


func _start_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(strength, _shake_strength * maxf(_shake_time, 0.0) / _shake_total)
	_shake_total = maxf(duration, 0.01)
	_shake_time = duration

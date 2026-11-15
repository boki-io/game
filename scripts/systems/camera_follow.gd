class_name CameraFollow
extends Camera2D
## Follows the nearest player (to its own position), stays inside the arena, and can shake.
## With no player it glides to `browse_target` (the hub's browse mode) and, when a player appears,
## blends from where it is to following them.

const BROWSE_TIME := 0.25
const BLEND_TIME := 0.3

## Added to `offset` every frame (shake comes on top). The hub uses it to put the focused pedestal left of center.
var base_offset := Vector2.ZERO

var _browse_tween: Tween
var _offset_tween: Tween
var _blend := 1.0  # 0..1 while blending from a browse position to following the player
var _blend_from := Vector2.ZERO
var _had_target := false

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
	limit_right = Arena.world_size.x
	limit_bottom = Arena.world_size.y
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


## Eases `base_offset` to `value` (the hub shifts the view between browse and walk mode).
func set_base_offset(value: Vector2, time: float = 0.0) -> void:
	if _offset_tween:
		_offset_tween.kill()
	if time <= 0.0:
		base_offset = value
		return
	_offset_tween = create_tween()
	_offset_tween.tween_property(self, "base_offset", value, time)


## Moves the camera to a world position over BROWSE_TIME. Only used while no player exists.
func browse_to(pos: Vector2, instant: bool = false) -> void:
	if _browse_tween:
		_browse_tween.kill()
	if instant:
		global_position = pos.round()
		return
	_browse_tween = create_tween()
	_browse_tween.tween_property(self, "global_position", pos.round(), BROWSE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	var target: Player = PlayerRegistry.nearest(global_position)
	if target:
		if _browse_tween:
			_browse_tween.kill()
		var follow := (target.global_position - Vector2(0, 12)).round()
		if not _had_target and _blend_from != Vector2.ZERO:
			_blend = 0.0
		if _blend < 1.0:
			_blend = minf(_blend + delta / BLEND_TIME, 1.0)
			follow = _blend_from.lerp(follow, _blend).round()
		# Snap to whole pixels so the sprite doesn't shimmer at low resolution.
		global_position = follow
	_had_target = target != null
	if not _had_target:
		_blend_from = global_position
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := maxf(_shake_time, 0.0) / _shake_total
		offset = base_offset + Vector2(randf_range(-1, 1), randf_range(-1, 1)).round() * _shake_strength * k
	else:
		offset = base_offset


func _start_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(strength, _shake_strength * maxf(_shake_time, 0.0) / _shake_total)
	_shake_total = maxf(duration, 0.01)
	_shake_time = duration

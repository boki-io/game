class_name CameraFollow
extends Camera2D
## Follows the nearest player (to its own position), stays inside the arena, and can shake.
## The player can move inside a small dead zone around the screen centre without the camera moving; past it the
## camera follows with a little smoothing.
## With no player it glides to `browse_target` (the hub's browse mode) and, when a player appears,
## blends from where it is to following them.

const BROWSE_TIME := 0.25
const BLEND_TIME := 0.3

## Half-size of the dead zone as a fraction of half the screen (0 = hard lock, 1 = the screen edge).
@export_range(0.0, 0.5) var dead_zone_x := 0.08
@export_range(0.0, 0.5) var dead_zone_y := 0.06
## How fast the camera catches up once the player leaves the dead zone (higher = tighter, 0 = no smoothing).
@export_range(0.0, 30.0) var smoothing_speed := 6.0

## Added to `offset` every frame (shake comes on top). The hub uses it to put the focused pedestal left of center.
var base_offset := Vector2.ZERO

var _browse_tween: Tween
var _offset_tween: Tween
var _blend := 1.0  # 0..1 while blending from a browse position to following the player
var _blend_from := Vector2.ZERO
var _cam_pos := Vector2.ZERO  # the camera's unrounded follow position (dead zone and smoothing applied)
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


## Jumps to the player on the next frame instead of easing (a respawn far from where the player died).
func snap() -> void:
	_had_target = false
	_blend_from = Vector2.ZERO


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
		var goal := target.global_position - Vector2(0, 12)
		if not _had_target:
			_cam_pos = _clamp_to_limits(goal)
		else:
			_cam_pos = _follow_step(_cam_pos, goal, delta)
		var follow := _cam_pos.round()
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


## One frame of following `goal`: no movement while it is inside the dead zone, otherwise ease toward the point
## that puts it back on the dead zone's edge. Kept inside the arena limits so the dead zone does not go stale at a wall.
func _follow_step(from: Vector2, goal: Vector2, delta: float) -> Vector2:
	var zone := get_viewport_rect().size * 0.5 * Vector2(dead_zone_x, dead_zone_y)
	var d := goal - from
	var excess := d - d.clamp(-zone, zone)
	var step := excess
	if smoothing_speed > 0.0:
		step *= 1.0 - exp(-smoothing_speed * delta)
	return _clamp_to_limits(from + step)


func _clamp_to_limits(pos: Vector2) -> Vector2:
	var half := get_viewport_rect().size * 0.5 / zoom
	var lo := Vector2(limit_left, limit_top) + half
	var hi := Vector2(limit_right, limit_bottom) - half
	return Vector2(clampf(pos.x, lo.x, maxf(lo.x, hi.x)), clampf(pos.y, lo.y, maxf(lo.y, hi.y)))


func _start_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(strength, _shake_strength * maxf(_shake_time, 0.0) / _shake_total)
	_shake_total = maxf(duration, 0.01)
	_shake_time = duration

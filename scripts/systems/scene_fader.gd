extends Node
## Autoload. Wipes the screen shut with a circle (an iris) on the player, changes scene, and opens it again. While `busy`, gameplay and
## menu input is ignored. `busy` is a plain variable: tests set and read it.

const IRIS_TIME := 0.35  # seconds to close, and again to open
const IRIS_SHADER := preload("res://shaders/iris.gdshader")

## True from fade_to_scene until the opening ends (and during the first boot's opening).
var busy := false

var _wipe: Iris
var _tween: Tween


## A full-screen rect that covers everything farther than `radius` from `center` (pixels). Hidden while open (radius at least `r_max()`), so an
## idle iris costs no full-screen draw. Its own `color` is ignored: the shader writes the output.
class Iris extends ColorRect:
	var center := Vector2.ZERO
	var radius := 0.0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = IRIS_SHADER
		material = mat
		visible = false

	func view_size() -> Vector2:
		return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(640, 360)

	## The distance from `center` to the farthest corner: a hole this big covers the whole screen.
	func r_max() -> float:
		var v := view_size()
		return maxf(maxf(center.distance_to(Vector2.ZERO), center.distance_to(Vector2(v.x, 0))),
			maxf(center.distance_to(Vector2(0, v.y)), center.distance_to(v)))

	func is_open() -> bool:
		return radius >= r_max()

	func set_radius(r: float) -> void:
		radius = r
		_apply()

	func place(c: Vector2, r: float) -> void:
		center = c
		radius = r
		_apply()

	func open_at(c: Vector2) -> void:
		center = c
		radius = r_max()
		_apply()

	func _apply() -> void:
		var mat := material as ShaderMaterial
		mat.set_shader_parameter("view_size", view_size())
		mat.set_shader_parameter("center", center)
		mat.set_shader_parameter("radius", radius)
		visible = not is_open()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_wipe = Iris.new()
	layer.add_child(_wipe)
	# The first boot starts fully closed and opens from the screen centre.
	busy = true
	_wipe.place(_wipe.view_size() / 2.0, 0.0)
	_open.call_deferred()


func fade_to_scene(path: String) -> void:
	if busy:
		return
	busy = true
	_wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_tween()
	var start := _focus()
	_wipe.open_at(start)
	_tween = create_tween()
	_tween.tween_method(_wipe.set_radius, _wipe.radius, 0.0, IRIS_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_change_scene.bind(path))


func _change_scene(path: String) -> void:
	get_tree().paused = false
	get_tree().scene_changed.connect(_open, CONNECT_ONE_SHOT)
	get_tree().change_scene_to_file(path)


## The screen position the iris closes and opens on: the first player, dead or alive (`nearest` skips the dead, so it would give nothing at the
## moment of death), a little above its feet; the screen centre when there is no player (the select screen, menus). The canvas transform
## carries the camera, its offset and its shake.
func _focus() -> Vector2:
	var view := _wipe.view_size()
	var players: Array = PlayerRegistry.players
	if players.is_empty() or not is_instance_valid(players[0]):
		return view / 2.0
	var player: Node2D = players[0]
	return get_viewport().get_canvas_transform() * (player.global_position + Vector2(0, -8))


## `_focus()` after the new scene's camera has had a physics frame: CameraFollow places itself in `_physics_process`, so earlier its canvas
## transform is still the default and the player would be off screen.
func _settle_focus() -> Vector2:
	await get_tree().physics_frame
	await get_tree().process_frame
	return _focus()


func _open() -> void:
	var center := await _settle_focus()
	_kill_tween()
	_wipe.place(center, 0.0)
	_tween = create_tween()
	_tween.tween_method(_wipe.set_radius, 0.0, _wipe.r_max(), IRIS_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finished)


func _finished() -> void:
	busy = false
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.open_at(_wipe.center)


func _kill_tween() -> void:
	if _tween:
		_tween.kill()

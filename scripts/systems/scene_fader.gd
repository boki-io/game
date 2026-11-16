extends Node
## Autoload. Wipes the screen shut with a circle (an iris) on the player, changes scene, and opens it again. While `busy`, gameplay and
## menu input is ignored. `busy` is a plain variable: tests set and read it.
## Beats (they never set `busy`): `iris_hold` leaves a hole around the player (the death screen), `flash` washes a colour over the screen
## (stage clear). They live on a layer under the scenes' UI, so the HUD and the menus stay on top of them.

const IRIS_TIME := 0.35  # seconds to close, and again to open
const IRIS_SHADER := preload("res://shaders/iris.gdshader")

## True from fade_to_scene until the opening ends (and during the first boot's opening).
var busy := false

var _wipe: Iris
var _tween: Tween
var _beat: Iris
var _beat_tween: Tween
var _flash_rect: ColorRect
var _flash_tween: Tween


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
	# The beat layer has the value of the scenes' UI layers (1) and is a lower sibling than any scene's UI, and layers with the same value sort by
	# their index among their siblings, so it draws under the HUD and menus and over the world.
	var beat_layer := CanvasLayer.new()
	beat_layer.layer = 1
	add_child(beat_layer)
	_beat = Iris.new()
	beat_layer.add_child(_beat)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.visible = false
	beat_layer.add_child(_flash_rect)
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
	# After a death beat the wipe takes over from the hole's size, so there is no frame of open world between them.
	if _beat.is_open():
		_wipe.open_at(_focus())
	else:
		_wipe.place(_beat.center, _beat.radius)
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
	iris_release()  # the new scene is up and the wipe covers it: the beat can go
	_kill_tween()
	_wipe.place(center, 0.0)
	_tween = create_tween()
	_tween.tween_method(_wipe.set_radius, 0.0, _wipe.r_max(), IRIS_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finished)


## Closes the beat iris from full size to `radius` around the first player (dead or alive) over `time` and leaves it there. The scene's UI
## draws over it, so the death screen stays readable. Does not set `busy`.
func iris_hold(radius: float, time: float) -> void:
	if _beat_tween:
		_beat_tween.kill()
	_beat.open_at(_focus())
	_beat_tween = create_tween()
	_beat_tween.tween_method(_beat.set_radius, _beat.radius, radius, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Snaps the beat iris open again (and clears a flash).
func iris_release() -> void:
	if _beat_tween:
		_beat_tween.kill()
	_beat.open_at(_beat.center)
	if _flash_tween:
		_flash_tween.kill()
	_flash_rect.visible = false


## A full-screen `color` over the world (and under the UI) that fades to nothing over `time`. Does not set `busy`.
func flash(color: Color, time: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_rect.color = color
	_flash_rect.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, time)
	_flash_tween.tween_callback(func() -> void: _flash_rect.visible = false)


func _finished() -> void:
	busy = false
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.open_at(_wipe.center)


func _kill_tween() -> void:
	if _tween:
		_tween.kill()

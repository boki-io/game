extends Node
## Autoload. Fades to black, changes scene, fades back in. While `busy`, gameplay and menu input is ignored.

const FADE_TIME := 0.3

var busy := false

var _layer: CanvasLayer
var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_rect)
	# The first boot fades in from black.
	busy = true
	_rect.modulate.a = 1.0
	_fade_in.call_deferred()


func fade_to_scene(path: String) -> void:
	if busy:
		return
	busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_TIME)
	_tween.tween_callback(_change_scene.bind(path))


func _change_scene(path: String) -> void:
	get_tree().paused = false
	get_tree().scene_changed.connect(_fade_in, CONNECT_ONE_SHOT)
	get_tree().change_scene_to_file(path)


func _fade_in() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(_finished)


func _finished() -> void:
	busy = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _kill_tween() -> void:
	if _tween:
		_tween.kill()

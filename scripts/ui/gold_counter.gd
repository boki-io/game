class_name GoldCounter
extends Control
## A small coin and a gold number, drawn like `Hud._draw_gold` (spec 0.7, 7.4). Right-aligned in its rect. `count_to`
## animates the number up; it keeps running while the tree is paused, so it works in the camp screen's header.

const COIN_RIM := Color("c89a1c")
const COIN_FACE := Color("ffd23f")
const FONT_SIZE := 8

## The number on show (it lags behind the target during a count-up).
var shown := 0

var _tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(64, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows `value` at once.
func set_amount(value: int) -> void:
	_stop()
	shown = value
	queue_redraw()


## Counts from the number on show up (or down) to `value` over `duration` seconds.
func count_to(value: int, duration: float = 0.6) -> void:
	_stop()
	if duration <= 0.0 or value == shown or not is_inside_tree():
		set_amount(value)
		return
	_tween = create_tween()
	_tween.tween_method(_set_shown, shown, value, duration)


func _stop() -> void:
	if _tween:
		_tween.kill()
		_tween = null


func _set_shown(value: int) -> void:
	shown = value
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var text := str(shown)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var baseline := size.y / 2.0 + 3.0
	draw_string(font, Vector2(size.x - width, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
	var centre := Vector2(size.x - width - 7.0, size.y / 2.0)
	draw_circle(centre, 3.5, COIN_RIM)
	draw_circle(centre, 2.5, COIN_FACE)

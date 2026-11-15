extends Node2D
## Stand-in for AnimatedSprite2D + Shadow until real art exists. Origin is the feet.

@export var body_color := Color("4a7bd0")
@export var body_size := Vector2(14, 22)
## Turn off to draw only the shadow (an AnimatedSprite2D child supplies the body).
@export var body_visible := true
## Debug marker showing the aim vector.
@export var show_aim := true
@export var facing := Vector2.RIGHT:
	set(v):
		facing = v
		queue_redraw()
@export var aim := Vector2.RIGHT:
	set(v):
		aim = v
		if show_aim:
			queue_redraw()

## White body flash on hit.
var flash := false:
	set(v):
		flash = v
		queue_redraw()
## Attack warning: blinking body and a "!" marker above the head.
var warn := false:
	set(v):
		warn = v
		_update_processing()
var warn_color := Color("ffd23f")
## Horizontal jitter in px (used while an enemy charges up).
var shake := 0.0:
	set(v):
		shake = v
		_update_processing()
## Darkened body (recovering after an attack).
var dim := false:
	set(v):
		dim = v
		queue_redraw()


func _ready() -> void:
	_update_processing()


func _process(_delta: float) -> void:
	queue_redraw()


func _update_processing() -> void:
	set_process(warn or shake > 0.0)
	queue_redraw()


func _draw() -> void:
	_draw_shadow()
	if not body_visible:
		return
	var color := body_color
	if dim:
		color = color.darkened(0.5)
	if warn and int(Time.get_ticks_msec() / 80) % 2 == 0:
		color = color.lightened(0.6)
	if flash:
		color = Color.WHITE
	var jitter := randf_range(-shake, shake) if shake > 0.0 else 0.0
	var rect := Rect2(-body_size.x / 2.0 + jitter, -body_size.y - 2.0, body_size.x, body_size.y)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.5), false)
	var eye_y := rect.position.y + body_size.y * 0.3
	draw_rect(Rect2(-2 + facing.x * 4 + jitter, eye_y + facing.y * 2, 4, 4), Color.WHITE)
	if show_aim:
		draw_circle(Vector2(0, -body_size.y * 0.5 - 2.0) + aim * 22.0, 1.5, Color(1, 1, 1, 0.7))
	if warn:
		var font := ThemeDB.fallback_font
		var pos := Vector2(-3, -body_size.y - 6.0)
		draw_string(font, pos + Vector2(1, 1), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		draw_string(font, pos, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, warn_color)


func _draw_shadow() -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * body_size.x * 0.65, sin(a) * 4.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))

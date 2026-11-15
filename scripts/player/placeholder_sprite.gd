extends Node2D
## Stand-in for AnimatedSprite2D + Shadow until real art exists. Origin is the feet.

@export var body_color := Color("4a7bd0")
@export var body_size := Vector2(14, 22)
## Debug marker showing the aim vector.
@export var show_aim := true
## White body flash on hit.
var flash := false:
	set(v):
		flash = v
		queue_redraw()
@export var facing := Vector2.RIGHT:
	set(v):
		facing = v
		queue_redraw()
@export var aim := Vector2.RIGHT:
	set(v):
		aim = v
		if show_aim:
			queue_redraw()


func _draw() -> void:
	_draw_shadow()
	var rect := Rect2(-body_size.x / 2.0, -body_size.y - 2.0, body_size.x, body_size.y)
	draw_rect(rect, Color.WHITE if flash else body_color)
	draw_rect(rect, body_color.darkened(0.5), false)
	var eye_y := rect.position.y + body_size.y * 0.3
	draw_rect(Rect2(-2 + facing.x * 4, eye_y + facing.y * 2, 4, 4), Color.WHITE)
	if show_aim:
		draw_circle(Vector2(0, -body_size.y * 0.5 - 2.0) + aim * 22.0, 1.5, Color(1, 1, 1, 0.7))


func _draw_shadow() -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * body_size.x * 0.65, sin(a) * 4.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))

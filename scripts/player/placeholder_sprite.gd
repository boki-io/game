extends Node2D
## Stand-in for AnimatedSprite2D + Shadow until real art exists. Origin is the feet.

@export var body_color := Color("4a7bd0")
@export var facing := Vector2.RIGHT:
	set(v):
		facing = v
		queue_redraw()
## Debug marker showing the aim vector.
@export var aim := Vector2.RIGHT:
	set(v):
		aim = v
		queue_redraw()


func _draw() -> void:
	_draw_shadow()
	draw_rect(Rect2(-7, -24, 14, 22), body_color)
	draw_rect(Rect2(-7, -24, 14, 22), body_color.darkened(0.5), false)
	draw_rect(Rect2(-2 + facing.x * 4, -17 + facing.y * 2, 4, 4), Color.WHITE)
	draw_circle(Vector2(0, -12) + aim * 22.0, 1.5, Color(1, 1, 1, 0.7))


func _draw_shadow() -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 9.0, sin(a) * 4.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))

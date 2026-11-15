class_name Arena
extends Node2D
## Fixed-size bounded map: wall colliders on the World layer plus a visible border.

const SIZE := Vector2i(1600, 896)
const WALL_THICKNESS := 32.0


func _ready() -> void:
	z_index = -9
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	var w := float(SIZE.x)
	var h := float(SIZE.y)
	var t := WALL_THICKNESS
	_add_wall(walls, Rect2(-t, -t, w + 2 * t, t))
	_add_wall(walls, Rect2(-t, h, w + 2 * t, t))
	_add_wall(walls, Rect2(-t, 0, t, h))
	_add_wall(walls, Rect2(w, 0, t, h))


func _add_wall(body: StaticBody2D, rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = rect.get_center()
	body.add_child(cs)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color("e0c060"), false, 2.0)

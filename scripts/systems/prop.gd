class_name Prop
extends StaticBody2D
## A rock pillar. Origin is the base.

const STONE := Color("5c5248")

## Optional (spec 0.6 section 8): the map's pillar colour; null keeps today's stone. Set before the node is added.
var theme: MapTheme


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -6)
	add_child(cs)


func _draw() -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 11.0, sin(a) * 5.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-8, -36, 16, 34), STONE if theme == null else theme.pillar)
	draw_rect(Rect2(-8, -36, 16, 34), Color("231e19"), false)

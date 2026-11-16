class_name PlayerGlow
extends Node2D
## A soft additive glow around a player, drawn like the torch halos (three nested circles, additive blend). It sits behind the
## player's own sprite, breathes a little, and follows the sprite's alpha so the post-dash blink and the Phase ghost dim it too.

const BREATH := 0.04  # radius wobble
const BREATH_HZ := 0.6

var color := Color.WHITE
var radius := 56.0
var alpha := 0.16
## Its modulate alpha scales the light (null: full strength).
var sprite: CanvasItem

var _scale := 1.0


func _ready() -> void:
	position = Vector2(0, -10)  # the body's middle
	show_behind_parent = true
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


## The three (radius, alpha) pairs of the circles at rest, outermost first.
func circles() -> Array[Vector2]:
	var a := alpha * 0.5
	return [Vector2(radius, a), Vector2(radius * 0.65, a), Vector2(radius * 0.4, a)]


func _process(_delta: float) -> void:
	_scale = sprite.modulate.a if is_instance_valid(sprite) else 1.0
	queue_redraw()


func _draw() -> void:
	var breath := 1.0 + BREATH * sin(Time.get_ticks_msec() / 1000.0 * TAU * BREATH_HZ)
	for c in circles():
		draw_circle(Vector2.ZERO, c.x * breath, Color(color, c.y * _scale))

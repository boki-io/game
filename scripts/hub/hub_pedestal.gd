class_name HubPedestal
extends Node2D
## A platform in the hub with a character standing idle on it, a name, a spotlight ring and a click area.
## Decoration only: it does not block movement.

signal clicked(pedestal: HubPedestal)

const PLACEHOLDER_SPRITE := preload("res://scripts/player/placeholder_sprite.gd")
const CLICK_RADIUS := 26.0
const PLATFORM_RADIUS := Vector2(26, 9)

var character: CharacterData
var focused := false:
	set(v):
		focused = v
		queue_redraw()

var _figure: Node2D
var _anim: AnimatedSprite2D
var _bob_time := 0.0


func setup(c: CharacterData) -> void:
	character = c
	_build_figure()
	_build_click_area()
	queue_redraw()


## Hides the figure while its character is being played, and shows it again afterwards.
func set_figure_visible(shown: bool) -> void:
	_figure.visible = shown


func _build_figure() -> void:
	_figure = Node2D.new()
	_figure.set_script(PLACEHOLDER_SPRITE)
	_figure.body_color = character.body_color
	_figure.show_aim = false
	add_child(_figure)
	if character.sprite_frames and character.sprite_frames.has_animation(&"idle"):
		_figure.body_visible = false  # keep the shadow, hide the rectangle
		var frames := character.sprite_frames
		for anim in frames.get_animation_names():
			frames.set_animation_loop(anim, not Player.ONE_SHOT_ANIMS.has(anim))
		_anim = AnimatedSprite2D.new()
		_anim.sprite_frames = frames
		_anim.scale = Vector2(character.sprite_scale, character.sprite_scale)
		_anim.position = character.sprite_offset
		_anim.flip_h = character.sprite_faces_left  # figures face right
		if _anim.flip_h:
			_anim.position.x = -character.sprite_offset.x
		_figure.add_child(_anim)
		_anim.play(&"idle")
		set_process(false)


func _build_click_area() -> void:
	var area := Area2D.new()
	area.input_pickable = true
	area.collision_layer = 1 << 7  # an unused layer; layer 0 would make the area unpickable
	area.collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = CLICK_RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -14)
	area.add_child(cs)
	area.input_event.connect(_on_area_input)
	add_child(area)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func _process(delta: float) -> void:
	# Characters without animation frames get a gentle one-pixel bob.
	_bob_time += delta
	_figure.position.y = -1.0 if fmod(_bob_time, 1.6) < 0.8 else 0.0


func _draw() -> void:
	var glow := 0.55 if focused else 0.12
	var ring := Color("ffd866") if focused else Color(1, 1, 1)
	draw_circle(Vector2.ZERO, PLATFORM_RADIUS.x + 6.0, Color(ring, glow * 0.25))
	_draw_ellipse(PLATFORM_RADIUS, Color("4a4658"))
	_draw_ellipse(PLATFORM_RADIUS * 0.8, Color("5e5a70"))
	_draw_ellipse_outline(PLATFORM_RADIUS + Vector2(5, 2), Color(ring, glow + 0.2), 1.0 if not focused else 2.0)
	var font := ThemeDB.fallback_font
	var label := character.display_name
	var pos := Vector2(-40.0, PLATFORM_RADIUS.y + 14.0)
	draw_string(font, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 8, Color(0, 0, 0, 0.9))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 8,
		Color("ffd866") if focused else Color(1, 1, 1, 0.7))


func _ellipse_points(radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


func _draw_ellipse(radii: Vector2, color: Color) -> void:
	draw_colored_polygon(_ellipse_points(radii), color)


func _draw_ellipse_outline(radii: Vector2, color: Color, width: float) -> void:
	var pts := _ellipse_points(radii)
	pts.append(pts[0])
	draw_polyline(pts, color, width)

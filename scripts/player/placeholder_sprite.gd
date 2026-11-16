extends Node2D
## Stand-in for AnimatedSprite2D + Shadow until real art exists. Origin is the feet.

## One small detail drawn on the body (same order as MonsterVariant.Mark).
enum Mark { NONE, STRIPE, SPOTS, CREST }

@export var body_color := Color("4a7bd0")
@export var body_size := Vector2(14, 22)
## Outline colour; fully transparent means today's look (the body darkened by half).
@export var outline_color := Color(0, 0, 0, 0):
	set(v):
		outline_color = v
		queue_redraw()
@export var eye_color := Color.WHITE:
	set(v):
		eye_color = v
		queue_redraw()
@export var mark := Mark.NONE:
	set(v):
		mark = v
		queue_redraw()
@export var mark_color := Color.WHITE:
	set(v):
		mark_color = v
		queue_redraw()
## Turn off to draw only the shadow (an AnimatedSprite2D child supplies the body).
@export var body_visible := true:
	set(v):
		body_visible = v
		queue_redraw()
## Debug marker showing the aim vector.
@export var show_aim := true
@export var facing := Vector2.RIGHT:
	set(v):
		if v == facing:
			return  # enemies set this every frame; redrawing for no change is costly with hundreds on screen
		facing = v
		queue_redraw()
@export var aim := Vector2.RIGHT:
	set(v):
		if v == aim:
			return
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
	var blink := warn and int(Time.get_ticks_msec() / 80) % 2 == 0
	if blink:
		color = color.lightened(0.6)
	if flash:
		color = Color.WHITE
	var jitter := randf_range(-shake, shake) if shake > 0.0 else 0.0
	var rect := Rect2(-body_size.x / 2.0 + jitter, -body_size.y - 2.0, body_size.x, body_size.y)
	draw_rect(rect, color)
	# The themed outline only shows in the normal look; blink, flash and dim keep the derived one.
	var plain := not (dim or flash or blink)
	var outline := outline_color if (plain and outline_color.a > 0.0) else color.darkened(0.5)
	draw_rect(rect, outline, false)
	if mark != Mark.NONE and not flash:
		_draw_mark(rect, dim, blink)
	var eye_y := rect.position.y + body_size.y * 0.3
	draw_rect(Rect2(-2 + facing.x * 4 + jitter, eye_y + facing.y * 2, 4, 4), eye_color)
	if show_aim:
		draw_circle(Vector2(0, -body_size.y * 0.5 - 2.0) + aim * 22.0, 1.5, Color(1, 1, 1, 0.7))
	if warn:
		var font := ThemeDB.fallback_font
		var pos := Vector2(-3, -body_size.y - 6.0)
		draw_string(font, pos + Vector2(1, 1), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		draw_string(font, pos, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, warn_color)


## The mark inside `rect`, kept clear of the eye (the eye sits at 30% of the height). It follows the body's dim and
## warn blink so those signals look the same on every map.
func _draw_mark(rect: Rect2, dimmed: bool, blinking: bool) -> void:
	var c := mark_color
	if dimmed:
		c = c.darkened(0.5)
	if blinking:
		c = c.lightened(0.6)
	var w := rect.size.x
	var h := rect.size.y
	var o := rect.position
	match mark:
		Mark.STRIPE:
			draw_rect(Rect2(o.x + 1.0, o.y + h * 0.62, w - 2.0, maxf(3.0, round(h * 0.16))), c)
		Mark.SPOTS:
			var s := maxf(3.0, round(w * 0.22))
			draw_rect(Rect2(o.x + 1.0, o.y + h * 0.62, s, s), c)
			draw_rect(Rect2(o.x + w - 1.0 - s, o.y + h * 0.78 - s * 0.5, s, s), c)
			draw_rect(Rect2(o.x + w * 0.5 - s * 0.5, o.y + h - 1.0 - s, s, s), c)
		Mark.CREST:
			var t := maxf(3.0, round(h * 0.16))
			var teeth := 3 if w >= 14.0 else 2
			var step := (w - 2.0) / teeth
			for i in teeth:
				var x0 := o.x + 1.0 + step * i
				draw_colored_polygon(PackedVector2Array([
					Vector2(x0, o.y + t + 1.0), Vector2(x0 + step * 0.5, o.y + 1.0), Vector2(x0 + step, o.y + t + 1.0)]), c)


func _draw_shadow() -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * body_size.x * 0.65, sin(a) * 4.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))

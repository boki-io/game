class_name CaveWall
extends StaticBody2D
## A freestanding rock wall inside the arena: solid for the Player (like the props), a flat slab seen from above
## with a darker face along its south edge. The node's origin is the bottom centre of its footprint, so it
## Y-sorts with the characters. `layout()` decides where walls go, seeded so every run has the same ones.
## Enemies and projectiles are not blocked, as with the props.

const THICKNESS := 16.0
const LENGTHS := [48.0, 64.0, 96.0, 128.0, 160.0, 208.0, 256.0, 320.0]
const COUNT := 6
const MARGIN := 56.0  # clear space between a wall and the rock band, and between two walls
const FACE := 6.0
const WALL_SEED := 31

const TOP := Color("4d443a")
const TOP_LIGHT := Color("5e5448")
const SIDE := Color("2e2822")
const OUTLINE := Color("1e1a17")

var footprint := Rect2()  # world rectangle covered, set by setup()

var _flecks: Array[Rect2] = []
var _top := TOP
var _top_light := TOP_LIGHT
var _side := SIDE
var _outline := OUTLINE


## Footprints (world rectangles) of the walls. `reserved` rectangles (the spawn area ...) are kept clear.
static func layout(size: Vector2, band: float, reserved: Array[Rect2]) -> Array[Rect2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = WALL_SEED
	var out: Array[Rect2] = []
	var edge := band + MARGIN
	var tries := 0
	while out.size() < COUNT and tries < 1500:
		tries += 1
		var length: float = LENGTHS[rng.randi_range(0, LENGTHS.size() - 1)]
		var horizontal := rng.randf() < 0.5
		var dims := Vector2(length, THICKNESS) if horizontal else Vector2(THICKNESS, length)
		var pos := Vector2(rng.randf_range(edge, size.x - edge - dims.x), rng.randf_range(edge, size.y - edge - dims.y)).round()
		var rect := Rect2(pos, dims)
		var blocked := false
		for r in reserved:
			if rect.intersects(r.grow(24.0)):
				blocked = true
				break
		for other in out:
			if rect.intersects(other.grow(MARGIN)):
				blocked = true
				break
		if not blocked:
			out.append(rect)
	return out


## `theme` is optional (spec 0.6 section 8): null keeps today's colours.
func setup(rect: Rect2, theme: MapTheme = null) -> void:
	footprint = rect
	if theme != null:
		_top = theme.wall_top
		_top_light = theme.wall_top_light
		_side = theme.wall_side
		_outline = theme.wall_outline
	position = Vector2(rect.get_center().x, rect.end.y)
	collision_layer = 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -rect.size.y / 2.0)
	add_child(cs)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rect)
	for i in int(rect.size.x * rect.size.y / 160.0):
		_flecks.append(Rect2(Vector2(rng.randf_range(-rect.size.x / 2.0 + 2.0, rect.size.x / 2.0 - 4.0),
			rng.randf_range(-rect.size.y + 2.0, -FACE - 2.0)), Vector2(3, 1)))


func _draw() -> void:
	var w := footprint.size.x
	var h := footprint.size.y
	var body := Rect2(-w / 2.0, -h, w, h)
	draw_colored_polygon(_shadow(w), Color(0, 0, 0, 0.3))
	draw_rect(body, _side)
	draw_rect(Rect2(body.position, Vector2(w, h - FACE)), _top)
	draw_rect(Rect2(body.position, Vector2(w, 2)), _top_light)
	for f in _flecks:
		draw_rect(f, _top_light)
	draw_rect(body, _outline, false, 1.0)


func _shadow(w: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * (w / 2.0 + 4.0), sin(a) * 4.0 + 2.0))
	return pts

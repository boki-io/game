class_name CaveDecor
extends Node2D
## One piece of non-blocking cave decor: a stalagmite, rock, pebbles, bones or a glowing mushroom, and (v0.6) moss,
## crystals, icicles, frost, big fungi, puddles, vents and floor cracks. Drawing only.
## The hub and the run both use it. `layout()` decides where they go: seeded (the same every launch), mostly along the walls, and never on
## the reserved areas (pedestals, training area, door lane, sign).

## New kinds are appended: the numbers of the first five are saved in theme files and must not change.
enum Kind { STALAGMITE, ROCK, PEBBLES, BONES, MUSHROOM, MOSS, CRYSTAL, ICICLE, FROST, BIG_FUNGUS, PUDDLE, VENT, CRACK }

const COUNT := 48  # at most 60
const CLEARANCE := 24.0
const WALL_MARGIN := 10.0  # how far in from the rock band decor may start
const DECOR_SEED := 7
## Glow of the kinds that glow when there is no theme (the mushroom's cyan).
const GLOW := Color(0.3, 0.9, 0.85)

var kind := Kind.ROCK
var variant := 0
## Optional (spec 0.6 section 8): the glowing kinds use its `glow_color`; null keeps today's cyan. Set before the node is added.
var theme: MapTheme


## A list of {kind, pos, variant}. `size` is the room, `band` the rock band, `reserved` rectangles to keep clear.
static func layout(size: Vector2, band: float, reserved: Array[Rect2], count: int = COUNT) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	var out: Array[Dictionary] = []
	var keep_out: Array[Rect2] = []
	for r in reserved:
		keep_out.append(r.grow(CLEARANCE))
	var tries := 0
	while out.size() < count and tries < 4000:
		tries += 1
		var kind_roll := rng.randf()
		var k: Kind
		var pos: Vector2
		if kind_roll < 0.35:  # stalagmites and rocks hug the walls
			k = Kind.STALAGMITE if rng.randf() < 0.6 else Kind.ROCK
			pos = _near_wall(rng, size, band)
		else:
			k = [Kind.PEBBLES, Kind.PEBBLES, Kind.BONES, Kind.MUSHROOM, Kind.ROCK][rng.randi_range(0, 4)]
			pos = Vector2(rng.randf_range(band + WALL_MARGIN, size.x - band - WALL_MARGIN),
				rng.randf_range(band + WALL_MARGIN + 12.0, size.y - band - WALL_MARGIN))
		var blocked := false
		for r in keep_out:
			if r.has_point(pos):
				blocked = true
				break
		if not blocked:
			out.append({kind = k, pos = pos.round(), variant = rng.randi_range(0, 2)})
	return out


static func _near_wall(rng: RandomNumberGenerator, size: Vector2, band: float) -> Vector2:
	var inset := band + WALL_MARGIN + rng.randf_range(0.0, 14.0)
	match rng.randi_range(0, 3):
		0:
			return Vector2(rng.randf_range(inset, size.x - inset), inset + 10.0)
		1:
			return Vector2(rng.randf_range(inset, size.x - inset), size.y - inset)
		2:
			return Vector2(inset, rng.randf_range(inset + 10.0, size.y - inset))
		_:
			return Vector2(size.x - inset, rng.randf_range(inset + 10.0, size.y - inset))


func _draw() -> void:
	draw_set_transform(Vector2.ZERO)
	if kind not in [Kind.MOSS, Kind.FROST, Kind.PUDDLE, Kind.CRACK]:
		_shadow(7.0 if kind in [Kind.STALAGMITE, Kind.ICICLE, Kind.BIG_FUNGUS] else 5.0)
	match kind:
		Kind.STALAGMITE:
			var h := 14.0 + variant * 5.0
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(-1, -h), Vector2(6, 0)]), Color("6b6256"))
			draw_colored_polygon(PackedVector2Array([Vector2(-1, -h), Vector2(6, 0), Vector2(1, 0)]), Color("4c453c"))
		Kind.ROCK:
			var w := 6.0 + variant * 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(-w, 0), Vector2(-w + 2, -w), Vector2(w - 2, -w + 1), Vector2(w, 0)]), Color("6a625a"))
			draw_line(Vector2(-w + 2, -w), Vector2(w - 2, -w + 1), Color("857c72"), 1.0)
		Kind.PEBBLES:
			for i in 3:
				draw_rect(Rect2(Vector2(-6 + i * 5 + variant, -1 - (i % 2)), Vector2(2 + (i % 2), 2)), Color("7a7268"))
		Kind.BONES:
			draw_line(Vector2(-5, -1), Vector2(5, -3 + variant), Color("cfc8b4"), 2.0)
			draw_circle(Vector2(5, -3 + variant), 1.6, Color("cfc8b4"))
			draw_circle(Vector2(-5, -1), 1.6, Color("cfc8b4"))
			if variant == 2:
				draw_circle(Vector2(-1, -5), 3.0, Color("d8d2c0"))
				draw_rect(Rect2(-2, -6, 1, 1), Color("2a2622"))
				draw_rect(Rect2(0, -6, 1, 1), Color("2a2622"))
		Kind.MUSHROOM:
			draw_circle(Vector2(0, -4), 9.0, Color(0.3, 0.9, 0.85, 0.10))
			draw_rect(Rect2(-1, -4, 2, 4), Color("b9c9c4"))
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -4), Vector2(-2, -8), Vector2(2, -8), Vector2(4, -4)]), Color("3fd6c4"))


	_draw_new()


## The v0.6 kinds. Flat ones (moss, frost, puddle, crack) have no shadow; the others reuse the small one drawn above.
func _draw_new() -> void:
	var glow := glow_color()
	match kind:
		Kind.MOSS:
			var moss := Color("4f6b3a")
			draw_colored_polygon(_blob(13.0 + variant * 2.0, 5.5), Color(0.1, 0.2, 0.07, 0.8))
			draw_colored_polygon(_blob(10.0 + variant * 2.0, 4.0), Color(0.36, 0.55, 0.22, 0.95))
			draw_colored_polygon(_blob(6.0 + variant, 2.5), Color(0.5, 0.72, 0.3, 1.0))
			for i in 4:
				var x := -6.0 + i * 4.0 + variant
				draw_line(Vector2(x, 0), Vector2(x + 1, -3 - (i % 2)), moss.lightened(0.2), 1.0)
		Kind.CRYSTAL:
			draw_circle(Vector2(0, -6), 12.0, Color(glow, 0.10))
			var body := glow.lerp(Color.WHITE, 0.25)
			var spikes := 2 + variant % 2
			for i in spikes:
				var x := (i - (spikes - 1) / 2.0) * 5.0
				var h := 10.0 + ((i + variant) % 3) * 4.0
				draw_colored_polygon(PackedVector2Array([Vector2(x - 3, 0), Vector2(x, -h), Vector2(x + 3, 0)]), body)
				draw_colored_polygon(PackedVector2Array([Vector2(x, -h), Vector2(x + 3, 0), Vector2(x + 0.5, 0)]), body.darkened(0.35))
		Kind.ICICLE:
			var h := 18.0 + variant * 5.0
			draw_colored_polygon(PackedVector2Array([Vector2(-5, 0), Vector2(0, -h), Vector2(5, 0)]), Color("b9dff0"))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -h), Vector2(5, 0), Vector2(1, 0)]), Color("7fb3d0"))
			draw_line(Vector2(-1, -h + 4), Vector2(-2, -4), Color(1, 1, 1, 0.7), 1.0)
		Kind.FROST:
			draw_colored_polygon(_blob(14.0 + variant * 2.0, 6.0), Color(0.35, 0.55, 0.75, 0.55))
			draw_colored_polygon(_blob(11.0 + variant * 2.0, 4.5), Color(0.92, 0.97, 1.0, 0.9))
			draw_colored_polygon(_blob(6.0 + variant, 2.5), Color(1.0, 1.0, 1.0, 1.0))
			draw_line(Vector2(-4, 0), Vector2(3, -1), Color(1, 1, 1, 0.8), 1.0)
		Kind.BIG_FUNGUS:
			draw_circle(Vector2(0, -12), 16.0, Color(glow, 0.10))
			var h := 12.0 + variant * 3.0
			var cap := glow.lerp(Color(0.55, 0.3, 0.85), 0.35)
			draw_rect(Rect2(-2, -h, 4, h), Color("c9bfd6"))
			draw_colored_polygon(PackedVector2Array([Vector2(-11, -h + 1), Vector2(-8, -h - 6), Vector2(-3, -h - 9),
				Vector2(3, -h - 9), Vector2(8, -h - 6), Vector2(11, -h + 1)]), cap)
			draw_rect(Rect2(-11, -h + 1, 22, 2), cap.darkened(0.35))
			draw_circle(Vector2(-4, -h - 4), 1.5, cap.lightened(0.5))
			draw_circle(Vector2(4, -h - 5), 1.2, cap.lightened(0.5))
		Kind.PUDDLE:
			var r := 9.0 + variant * 2.0
			draw_colored_polygon(_blob(r + 2.0, r * 0.4 + 1.5), Color(0.6, 0.85, 1.0, 0.75))
			draw_colored_polygon(_blob(r, r * 0.4), Color(0.1, 0.28, 0.5, 0.95))
			draw_polyline(_ring(r * 0.6, r * 0.24), Color(0.75, 0.92, 1.0, 0.9), 1.0)
		Kind.VENT:
			draw_colored_polygon(_blob(8.0, 3.5), Color("4a4136"))
			draw_colored_polygon(_blob(4.5, 2.0), Color("14100c"))
			draw_polyline(PackedVector2Array([Vector2(0, -2), Vector2(2, -7), Vector2(-1, -12), Vector2(2, -17 - variant * 2)]),
				Color(0.9, 0.9, 0.85, 0.45), 2.0)
		Kind.CRACK:
			var pts := PackedVector2Array()
			var n := 5 + variant
			for i in n:
				pts.append(Vector2(-12.0 + i * 24.0 / (n - 1), (-2.0 if i % 2 == 0 else 2.0) + (i % 3) - 1.0))
			draw_polyline(pts, Color(glow, 0.25), 5.0)
			draw_polyline(pts, glow.lerp(Color.WHITE, 0.3), 1.5)


## The colour of the glowing kinds: the theme's `glow_color`, or today's cyan.
func glow_color() -> Color:
	return GLOW if theme == null else theme.glow_color


## A flat ellipse with a slightly uneven edge, for patches on the floor.
func _blob(rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		var wob := 1.0 + 0.12 * sin(a * 3.0 + variant * 2.0)
		pts.append(Vector2(cos(a) * rx * wob, sin(a) * ry * wob))
	return pts


func _ring(rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _shadow(radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * 0.4))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.3))

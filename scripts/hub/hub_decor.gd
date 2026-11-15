class_name HubDecor
extends Node2D
## One piece of non-blocking cave decor: a stalagmite, rock, pebbles, bones or a glowing mushroom.
## `layout()` decides where they go: seeded (the same every launch), mostly along the walls, and never on
## the reserved areas (pedestals, training area, door lane, sign).

enum Kind { STALAGMITE, ROCK, PEBBLES, BONES, MUSHROOM }

const COUNT := 48  # at most 60
const CLEARANCE := 24.0
const WALL_MARGIN := 10.0  # how far in from the rock band decor may start
const DECOR_SEED := 7

var kind := Kind.ROCK
var variant := 0


## A list of {kind, pos, variant}. `size` is the room, `band` the rock band, `reserved` rectangles to keep clear.
static func layout(size: Vector2, band: float, reserved: Array[Rect2]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	var out: Array[Dictionary] = []
	var keep_out: Array[Rect2] = []
	for r in reserved:
		keep_out.append(r.grow(CLEARANCE))
	var tries := 0
	while out.size() < COUNT and tries < 2000:
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
	_shadow(7.0 if kind == Kind.STALAGMITE else 5.0)
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


func _shadow(radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * 0.4))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.3))

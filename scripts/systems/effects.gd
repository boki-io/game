class_name Effects
extends Node2D
## Transient visuals drawn from one canvas item: slash arcs, death puffs, damage numbers.
## Numbers are capped and merged when close together.

const MAX_NUMBERS := 40
const NUMBER_LIFE := 0.6
const MERGE_DIST := 10.0
const MERGE_WINDOW := 0.15

var _numbers: Array[Dictionary] = []
var _fx: Array[Dictionary] = []


static func get_for(node: Node) -> Effects:
	return node.get_tree().get_first_node_in_group(&"effects") as Effects


func _ready() -> void:
	add_to_group(&"effects")
	z_index = 10  # above the y-sorted world


func damage_number(pos: Vector2, amount: float) -> void:
	for n in _numbers:
		if n.age < MERGE_WINDOW and n.pos.distance_to(pos) < MERGE_DIST:
			n.value += amount
			return
	if _numbers.size() >= MAX_NUMBERS:
		_numbers.remove_at(0)
	_numbers.append({pos = pos, value = amount, age = 0.0})


func slash_arc(pos: Vector2, dir: Vector2, radius: float, arc_rad: float) -> void:
	_fx.append({kind = &"arc", pos = pos, angle = dir.angle(), radius = radius, arc = arc_rad, age = 0.0, life = 0.12})


func puff(pos: Vector2, color: Color) -> void:
	_fx.append({kind = &"puff", pos = pos, radius = 9.0, color = color, age = 0.0, life = 0.2})


func _process(delta: float) -> void:
	if _numbers.is_empty() and _fx.is_empty():
		return
	for n in _numbers:
		n.age += delta
	for f in _fx:
		f.age += delta
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return n.age < NUMBER_LIFE)
	_fx = _fx.filter(func(f: Dictionary) -> bool: return f.age < f.life)
	queue_redraw()


func _draw() -> void:
	for f in _fx:
		var t: float = f.age / f.life
		if f.kind == &"arc":
			_draw_arc_fx(f, t)
		else:
			draw_circle(f.pos, f.radius * (0.4 + t), Color(f.color, 0.6 * (1.0 - t)))
	var font := ThemeDB.fallback_font
	for n in _numbers:
		var t: float = n.age / NUMBER_LIFE
		var p: Vector2 = n.pos + Vector2(-8, -t * 14.0)
		var text := str(roundi(n.value))
		draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, 16, 8, Color(0, 0, 0, 1.0 - t))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, 16, 8, Color(1, 1, 0.8, 1.0 - t))


func _draw_arc_fx(f: Dictionary, t: float) -> void:
	var pts := PackedVector2Array([f.pos])
	var steps := 10
	for i in steps + 1:
		var a: float = f.angle - f.arc / 2.0 + f.arc * i / steps
		pts.append(f.pos + Vector2.from_angle(a) * f.radius)
	draw_colored_polygon(pts, Color(1, 1, 1, 0.5 * (1.0 - t)))
	draw_arc(f.pos, f.radius, f.angle - f.arc / 2.0, f.angle + f.arc / 2.0, 12, Color(1, 1, 1, 1.0 - t), 1.5)

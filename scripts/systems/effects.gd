class_name Effects
extends Node2D
## Transient visuals drawn from one canvas item: slash arcs, rings, telegraphs, puffs and
## floating numbers (damage in yellow, mana spend in blue). Numbers are capped and merged.

const MAX_NUMBERS := 40
const NUMBER_LIFE := 0.6
const MERGE_DIST := 10.0
const MERGE_WINDOW := 0.15
const DAMAGE_COLOR := Color(1, 1, 0.8)
const MANA_COLOR := Color(0.4, 0.65, 1.0)

var _numbers: Array[Dictionary] = []
var _fx: Array[Dictionary] = []


static func get_for(node: Node) -> Effects:
	return node.get_tree().get_first_node_in_group(&"effects") as Effects


func _ready() -> void:
	add_to_group(&"effects")
	z_index = 10  # above the y-sorted world


func damage_number(pos: Vector2, amount: float) -> void:
	_add_number(pos, amount, DAMAGE_COLOR, "")


## Blue "-N" shown beside the player when mana is spent.
func mana_number(pos: Vector2, cost: float) -> void:
	_add_number(pos, cost, MANA_COLOR, "-")


func _add_number(pos: Vector2, amount: float, color: Color, prefix: String) -> void:
	for n in _numbers:
		if n.color == color and n.age < MERGE_WINDOW and n.pos.distance_to(pos) < MERGE_DIST:
			n.value += amount
			return
	if _numbers.size() >= MAX_NUMBERS:
		_numbers.remove_at(0)
	_numbers.append({pos = pos, value = amount, age = 0.0, color = color, prefix = prefix})


func slash_arc(pos: Vector2, dir: Vector2, radius: float, arc_rad: float) -> void:
	_fx.append({kind = &"arc", pos = pos, angle = dir.angle(), radius = radius, arc = arc_rad, age = 0.0, life = 0.12})


## Ground warning for a delayed hit; lasts `duration` seconds.
func telegraph(pos: Vector2, radius: float, duration: float) -> void:
	_fx.append({kind = &"telegraph", pos = pos, radius = radius, age = 0.0, life = maxf(duration, 0.01)})


## Expanding shockwave ring.
func ring(pos: Vector2, radius: float) -> void:
	_fx.append({kind = &"ring", pos = pos, radius = radius, age = 0.0, life = 0.25})


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
		match f.kind:
			&"arc":
				_draw_arc_fx(f, t)
			&"telegraph":
				draw_circle(f.pos, f.radius, Color(1, 0.2, 0.2, 0.12 + 0.2 * t))
				draw_arc(f.pos, f.radius, 0.0, TAU, 40, Color(1, 0.3, 0.3, 0.9), 1.0)
			&"ring":
				draw_circle(f.pos, f.radius, Color(1, 1, 1, 0.3 * (1.0 - t)))
				draw_arc(f.pos, f.radius * (0.6 + 0.4 * t), 0.0, TAU, 40, Color(1, 1, 1, 1.0 - t), 2.0)
			_:
				draw_circle(f.pos, f.radius * (0.4 + t), Color(f.color, 0.6 * (1.0 - t)))
	var font := ThemeDB.fallback_font
	for n in _numbers:
		var t: float = n.age / NUMBER_LIFE
		var p: Vector2 = n.pos + Vector2(-12, -t * 14.0)
		var text: String = n.prefix + str(roundi(n.value))
		draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, 24, 8, Color(0, 0, 0, 1.0 - t))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, 24, 8, Color(n.color, 1.0 - t))


func _draw_arc_fx(f: Dictionary, t: float) -> void:
	var pts := PackedVector2Array([f.pos])
	var steps := 10
	for i in steps + 1:
		var a: float = f.angle - f.arc / 2.0 + f.arc * i / steps
		pts.append(f.pos + Vector2.from_angle(a) * f.radius)
	draw_colored_polygon(pts, Color(1, 1, 1, 0.5 * (1.0 - t)))
	draw_arc(f.pos, f.radius, f.angle - f.arc / 2.0, f.angle + f.arc / 2.0, 12, Color(1, 1, 1, 1.0 - t), 1.5)

class_name OverworldMarker
extends Node2D
## One marker of the world (spec 1.6): a place from markers.json drawn as a code-drawn placeholder by kind, centred on its
## coordinate (real art comes later). Checkpoints and the start camp can be lit, caves and dungeons cleared, gates locked
## (an open gate draws its pillars and banner, a locked one joins them with a barrier and blocks the gap with a collider).
## The overworld owns interaction; this node only knows how to look and what its prompt says.

var data: Dictionary = {}
var index := 0
var kind: StringName = &""
var lit := false  # a checkpoint or the start camp the player has activated
var cleared := false  # a cave, dungeon or the final vault the player has cleared
var locked := false  # a gate that is locked
var show_name := false  # the player is close: the name is drawn
var gap_tiles := 12  # a gate's open width along its (nx, ny) vector
var _barrier: StaticBody2D


func setup(marker: Dictionary, marker_index: int, world: WorldData) -> void:
	data = marker
	index = marker_index
	kind = StringName(marker.kind)
	position = WorldData.marker_world(marker)
	name = "%s_%d" % [marker.kind, marker_index]
	z_index = 0
	if kind == &"gate":
		gap_tiles = _measure_gap(world)


func is_interactive() -> bool:
	return kind in [&"start_camp", &"checkpoint", &"cave", &"dungeon", &"final_dungeon", &"special"]


## What pressing F here does, as the prompt text ("" when nothing).
func prompt_text() -> String:
	match kind:
		&"start_camp", &"checkpoint":
			return "F: Rest here" if not lit else "F: Rest here (lit)"
		&"cave", &"dungeon", &"final_dungeon":
			return "F: Enter %s%s" % [data.name, " (cleared)" if cleared else ""]
		&"special":
			return "F: Examine"
	return ""


func set_lit(value: bool) -> void:
	if lit != value:
		lit = value
		queue_redraw()


func set_cleared(value: bool) -> void:
	if cleared != value:
		cleared = value
		queue_redraw()


func set_show_name(value: bool) -> void:
	if show_name != value:
		show_name = value
		queue_redraw()


## A locked gate draws a barrier and blocks the gap; an open one does neither.
func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	if _barrier != null:
		_barrier.queue_free()
		_barrier = null
	if locked and kind == &"gate":
		_barrier = StaticBody2D.new()
		_barrier.collision_layer = 1
		_barrier.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = Vector2(gap_tiles * WorldData.TILE_PX + 16.0, 24.0)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		_barrier.add_child(cs)
		_barrier.rotation = _axis().angle()
		add_child(_barrier)
	queue_redraw()


## The direction across a gate's gap (the marker's nx, ny).
func _axis() -> Vector2:
	return Vector2(float(data.get("nx", 1.0)), float(data.get("ny", 0.0))).normalized()


func _measure_gap(world: WorldData) -> int:
	var origin := Vector2(float(data.x), float(data.y))
	var along := _axis()
	var count := 1
	for sign_dir in [1.0, -1.0]:
		var k := 1
		while k < 40 and world.is_walkable(Vector2i((origin + along * sign_dir * k).round())):
			count += 1
			k += 1
	return count


func _draw() -> void:
	match kind:
		&"start_camp":
			_draw_camp(true)
		&"camp":
			_draw_camp(false)
		&"checkpoint":
			_draw_lamp()
		&"gate":
			_draw_gate()
		&"cave":
			_draw_arch(14.0, false)
		&"dungeon", &"final_dungeon":
			_draw_arch(20.0, true)
		&"special":
			_draw_special(String(data.get("subtype", "")))
		&"cache":
			draw_circle(Vector2(0, 2), 7.0, Color("5a4630"))
			draw_circle(Vector2(0, 0), 6.0, Color("7a6040"))
			draw_rect(Rect2(-2, -2, 4, 4), Color("ffd866"))
	if show_name and kind != &"arena":
		var font := ThemeDB.fallback_font
		var text: String = data.name
		draw_string(font, Vector2(-80, -34 if kind in [&"dungeon", &"final_dungeon"] else -26), text, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 8, Color(1, 1, 1, 0.9))


func _draw_camp(is_start: bool) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-14, 8), Vector2(14, 8), Vector2(0, -14)]), Color("b8654a") if not is_start else Color("d08a5a"))
	draw_colored_polygon(PackedVector2Array([Vector2(-4, 8), Vector2(4, 8), Vector2(0, -3)]), Color("2e1a14"))
	draw_colored_polygon(PackedVector2Array([Vector2(12, 8), Vector2(18, 8), Vector2(15, -1)]), Color("ff8a2b"))
	if is_start:
		var font := ThemeDB.fallback_font
		draw_circle(Vector2(0, -22), 3.0, Color("ffd866") if lit else Color("6b5a40"))


func _draw_lamp() -> void:
	draw_rect(Rect2(-1.5, -14, 3, 20), Color("4a3320"))
	draw_circle(Vector2(0, -16), 5.0, Color("ffd866") if lit else Color("6b5a40"))
	if lit:
		draw_circle(Vector2(0, -16), 10.0, Color(1.0, 0.85, 0.4, 0.2))


func _draw_gate() -> void:
	var axis := _axis()
	var half := gap_tiles * WorldData.TILE_PX / 2.0
	for sign_dir in [1.0, -1.0]:
		var p: Vector2 = axis * half * sign_dir
		draw_rect(Rect2(p + Vector2(-5, -18), Vector2(10, 22)), Color("5a5a64"))
		draw_rect(Rect2(p + Vector2(-5, -18), Vector2(10, 22)), Color("2a2a32"), false, 1.0)
	var banner := Color("b03030") if not locked else Color("606068")
	draw_line(axis * -half + Vector2(0, -14), axis * half + Vector2(0, -14), banner, 2.0)
	if locked:
		draw_line(axis * -half, axis * half, Color("a0a0a8"), 4.0)


func _draw_arch(size: float, boss: bool) -> void:
	var tint := Color("606068") if not cleared else Color("5a7a5a")
	draw_rect(Rect2(-size, -size * 0.6, size * 2.0, size * 1.2), tint)
	draw_rect(Rect2(-size * 0.5, -size * 0.1, size, size * 0.7), Color("0c0b10"))
	if boss:
		draw_circle(Vector2(0, -size * 0.85), 4.0, Color("d8d0c0"))
		draw_rect(Rect2(-2, -size * 0.85 + 3, 4, 3), Color("d8d0c0"))
	if cleared:
		draw_circle(Vector2(size * 0.8, -size * 0.55), 3.0, Color("7be08a"))


func _draw_special(subtype: String) -> void:
	match subtype:
		"shrine":
			draw_rect(Rect2(-6, -2, 12, 8), Color("8a8a96"))
			draw_rect(Rect2(-3, -12, 6, 10), Color("a0a0ac"))
			draw_circle(Vector2(0, -14), 3.0, Color("9fd3ff"))
		"ruins":
			draw_rect(Rect2(-9, -4, 4, 10), Color("7a7066"))
			draw_rect(Rect2(-2, -9, 4, 15), Color("8a8076"))
			draw_rect(Rect2(5, -2, 4, 8), Color("6a6056"))
		"altar":
			draw_rect(Rect2(-9, -3, 18, 9), Color("5a4a6a"))
			draw_circle(Vector2(0, -8), 3.0, Color("c070ff"))
		_:
			draw_colored_polygon(PackedVector2Array([Vector2(-8, 6), Vector2(8, 6), Vector2(0, -8)]), Color("7a5a3a"))
			draw_rect(Rect2(-2, 0, 4, 6), Color("2e1a14"))

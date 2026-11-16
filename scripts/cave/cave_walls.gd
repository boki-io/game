class_name CaveWalls
extends Node2D
## The cave walls (hub and run): a band of rock along every edge with a ragged inner edge, and the wall torches
## (flickering flames with a warm additive glow). Drawing only; the solid collision is the Arena's.

const ROCK := Color("3a322b")
const ROCK_DARK := Color("1e1a17")
const ROCK_LIGHT := Color("4d443a")
const STEP := 8.0
const ROCK_SEED := 99

@export var wall_band := 16.0
## Optional (spec 0.6 section 8): the map's rock and torch colours; null keeps today's. Set before the node is ready.
@export var theme: MapTheme
## Torches along the walls, in world coordinates.
var torches: Array[Vector2] = []

var _rock_edges: Array[PackedVector2Array] = []  # one polygon per side
var _flecks: Array[Rect2] = []
var _time := 0.0
var _glow: TorchGlow
var _rock := ROCK
var _rock_dark := ROCK_DARK
var _rock_light := ROCK_LIGHT


func _ready() -> void:
	z_index = -9
	_apply_theme()
	_build_rock()
	_glow = TorchGlow.new()
	_glow.cave = self
	_glow.z_index = 20
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)


## Changes the theme of a node that is already ready (MapBuilder, since main.tscn's Cave has built the default rock).
func set_theme(map_theme: MapTheme) -> void:
	theme = map_theme
	_apply_theme()
	if is_node_ready():
		_rock_edges.clear()
		_flecks.clear()
		_build_rock()
		queue_redraw()


func _apply_theme() -> void:
	_rock = ROCK if theme == null else theme.rock
	_rock_dark = ROCK_DARK if theme == null else theme.rock_dark
	_rock_light = ROCK_LIGHT if theme == null else theme.rock_light


func _process(delta: float) -> void:
	_time += delta
	_glow.queue_redraw()  # only the flames move; the rock is drawn once


## The torch halo (additive) and flame colours: the theme's `glow_color` and `torch_color`, or today's oranges.
func halo_color() -> Color:
	return Color(1.0, 0.55, 0.2) if theme == null else theme.glow_color


func flame_color() -> Color:
	return Color(1.0, 0.65, 0.2) if theme == null else theme.torch_color


## Flicker for torch `i`: about 0.85 .. 1.15.
func flicker(i: int) -> float:
	return 1.0 + 0.1 * sin(_time * 9.0 + i * 2.3) + 0.05 * sin(_time * 23.0 + i * 5.1)


func _build_rock() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ROCK_SEED
	var w := float(Arena.world_size.x)
	var h := float(Arena.world_size.y)
	var b := wall_band
	# Each side: a polygon from the room's edge to a jagged line that never goes past the collider (b).
	var sides := [
		[Vector2(0, 0), Vector2(1, 0), w, Vector2(0, 1)],
		[Vector2(0, h), Vector2(1, 0), w, Vector2(0, -1)],
		[Vector2(0, 0), Vector2(0, 1), h, Vector2(1, 0)],
		[Vector2(w, 0), Vector2(0, 1), h, Vector2(-1, 0)],
	]
	for side in sides:
		var origin: Vector2 = side[0]
		var along: Vector2 = side[1]
		var length: float = side[2]
		var inward: Vector2 = side[3]
		var pts := PackedVector2Array([origin, origin + along * length])
		var d := length
		while d >= 0.0:
			var depth := b - rng.randf_range(0.0, 4.0)
			pts.append(origin + along * d + inward * depth)
			if rng.randf() < 0.5:
				_flecks.append(Rect2(origin + along * d + inward * rng.randf_range(2.0, b - 5.0), Vector2(3, 2)))
			d -= STEP
		_rock_edges.append(pts)


func _draw() -> void:
	for poly in _rock_edges:
		draw_colored_polygon(poly, _rock)
		var outline := poly.slice(2)
		draw_polyline(outline, _rock_dark, 1.0)
	for f in _flecks:
		draw_rect(f, _rock_light)
	for t in torches:  # the bracket and the flame's stem
		draw_rect(Rect2(t + Vector2(-2, 0), Vector2(4, 6)), Color("2b2018"))


## The soft glow and flame of every torch, drawn additively on its own node.
class TorchGlow extends Node2D:
	var cave: CaveWalls

	func _draw() -> void:
		var halo := cave.halo_color()
		var flame := cave.flame_color()
		for i in cave.torches.size():
			var p := cave.torches[i] + Vector2(0, -2)
			var f := cave.flicker(i)
			for r in [46.0, 30.0, 18.0]:
				draw_circle(p, r * f, Color(halo, 0.08))
			draw_circle(p, 4.5 * f, Color(flame, 0.9))
			draw_circle(p + Vector2(0, -2), 2.0 * f, Color(1.0, 0.95, 0.6, 0.9))

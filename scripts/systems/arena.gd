class_name Arena
extends Node2D
## Fixed-size bounded map: wall colliders on the World layer plus a visible border.

const WALL_THICKNESS := 32.0
## The size of a run's arena (the stage maps): twice the old 1600x896 each way. main.tscn and map_preview.tscn use
## the `size` default; the hub and the select screen set their own.
const RUN_SIZE := Vector2i(3200, 1792)

## The size of the arena currently loaded. Assigned in _enter_tree (before any _ready in the scene),
## always from the `size` export, so it is never stale after a scene change. Must be the first child
## of its scene root so siblings after it read the right value.
static var world_size := RUN_SIZE
## The rock band of the arena loaded (0 for none). Things that keep to the floor stay this far inside the edge.
static var wall_margin := 0.0

@export var size := RUN_SIZE
## A solid, visible band of rock along every edge (the hub's cave walls). The colliders sit at the band's inner
## edge. 0 keeps the plain walls outside the arena and the yellow border (the run).
@export var wall_band := 0


func _enter_tree() -> void:
	world_size = size
	wall_margin = float(wall_band)


func _ready() -> void:
	z_index = -9
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	var w := float(size.x)
	var h := float(size.y)
	var t := WALL_THICKNESS
	var b := float(wall_band)
	_add_wall(walls, Rect2(-t, -t, w + 2 * t, t + b))
	_add_wall(walls, Rect2(-t, h - b, w + 2 * t, t + b))
	_add_wall(walls, Rect2(-t, 0, t + b, h))
	_add_wall(walls, Rect2(w - b, 0, t + b, h))


func _add_wall(body: StaticBody2D, rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = rect.get_center()
	body.add_child(cs)


func _draw() -> void:
	if wall_band > 0:
		return  # the cave draws its own rock
	draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Color("e0c060"), false, 2.0)

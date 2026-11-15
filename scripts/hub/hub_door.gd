class_name HubDoor
extends Node2D
## The doorway in the hub's north wall: a dark archway that lights up once a character is chosen, with
## a trigger just inside it. The trigger only detects the Player body, and only while open.

signal player_entered

const SIZE := Vector2(48, 24)
## The rock band the doorway is carved into: the trigger sits just inside it, on the walkable floor.
@export var wall_band := 0.0
## Ignores the Player for this long after the scene loads, so a return from a run cannot re-trigger it.
const GRACE_TIME := 1.0

var is_open := false

var _trigger: Area2D
var _grace := GRACE_TIME


func _ready() -> void:
	z_index = -8
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = 2  # the Player layer
	_trigger.monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, wall_band + SIZE.y / 2.0)
	_trigger.add_child(cs)
	_trigger.body_entered.connect(_on_body_entered)
	add_child(_trigger)
	_trigger.monitoring = false


func _physics_process(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)


## Lights the door and makes it usable, or darkens and disables it.
func set_open(open: bool) -> void:
	is_open = open
	_trigger.set_deferred("monitoring", open)
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if is_open and _grace <= 0.0 and body is Player:
		player_entered.emit()


func _draw() -> void:
	var w := SIZE.x
	var frame := Rect2(-w / 2.0 - 3.0, 0, w + 6.0, SIZE.y + 3.0)  # carved into the band, so no taller with it
	draw_rect(frame, Color("2a2833"))
	var inner := Rect2(-w / 2.0, 0, w, SIZE.y)
	draw_rect(inner, Color("ffd866", 0.9) if is_open else Color("0c0b10"))
	if is_open:
		draw_rect(Rect2(inner.position + Vector2(6, 0), inner.size - Vector2(12, 6)), Color("fff2b8", 0.7))
	draw_rect(frame, Color("e0c060") if is_open else Color("4a4658"), false, 1.0)

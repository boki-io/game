class_name ItemDrop
extends Node2D
## An item lying on the ground (spec 1.5): a glowing gem tinted by the item's rating. It hops out of the dead enemy like
## the vacuum magnet and cannot be taken during the hop; then the nearest living player who comes within
## `pick_distance` of the body point takes it. It has no attract(), so the pickup radius never pulls it, and it never
## expires. Pooled by Pickups, which emits `item_collected`.

const BODY_POINT := Vector2(0, -6)  # where gems and coins fly to on a player
const CHECK_EVERY := 6  # physics frames between looks for a taker
const REDRAW_HZ := 15.0
const GLOW_RADIUS := {&"standard": 8.0, &"epic": 11.0, &"legendary": 14.0}
const BEAM_HEIGHT := 24.0

var pool: Pickups
var active := false
var item_id: StringName = &""
var rating: StringName = &"standard"
var color := Color.WHITE
var _pop_vel := Vector2.ZERO  # the hop out of the dead enemy; it cannot be taken until it is over
var _frame := 0
var _redraw_in := 0.0
var _age := 0.0


func activate(pos: Vector2, id: StringName) -> void:
	var item := ItemRegistry.find(id)
	item_id = id
	rating = item.rating if item != null else &"standard"
	color = ItemData.rating_color(rating)
	global_position = pos
	_pop_vel = Pickups.random_pop()
	_frame = 0
	_redraw_in = 0.0
	_age = 0.0
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	queue_redraw()


func deactivate() -> void:
	active = false
	item_id = &""
	_pop_vel = Vector2.ZERO
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## True while it is still hopping out of the enemy.
func hopping() -> bool:
	return _pop_vel != Vector2.ZERO


func _physics_process(delta: float) -> void:
	_age += delta
	_redraw_in -= delta
	if _redraw_in <= 0.0:
		_redraw_in = 1.0 / REDRAW_HZ
		queue_redraw()
	if _pop_vel != Vector2.ZERO:
		_pop_vel = Pickups.pop_step(self, _pop_vel, delta)
		return
	_frame += 1
	if _frame % CHECK_EVERY != 0:
		return
	var player := PlayerRegistry.nearest(global_position)
	if player != null and global_position.distance_to(player.global_position + BODY_POINT) <= pool.loot.pick_distance:
		pool.take_item_drop(self)


func _draw() -> void:
	var glow: float = GLOW_RADIUS.get(rating, 8.0) * (1.0 + 0.1 * sin(_age * TAU / 1.2))
	draw_circle(Vector2.ZERO, glow, Color(color, 0.16))
	draw_circle(Vector2.ZERO, glow * 0.6, Color(color, 0.22))
	if rating != &"standard":
		draw_rect(Rect2(-0.5, -BEAM_HEIGHT, 1.0, BEAM_HEIGHT), Color(color, 0.5))
	draw_rect(Rect2(-3, -3, 6, 6), color)
	draw_rect(Rect2(-3, -3, 6, 6), color.lightened(0.5), false, 1.0)

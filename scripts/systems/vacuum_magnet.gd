class_name VacuumMagnet
extends Node2D
## The vacuum magnet (spec 1.3): a drop that lies on the ground for `lifetime` seconds (blinking for the last `flash_time`)
## and starts the vacuum for the player who walks onto it. Pooled by Pickups as a single instance. It has no attract(), so
## the pickup radius never pulls it in: the player has to walk to it.

const BODY_POINT := Vector2(0, -6)  # where gems and coins fly to on a player
const BURST_COLOR := Color("5fe0c8")

var pool: Pickups
var active := false
var _age := 0.0
var _pop_vel := Vector2.ZERO  # the hop out of the dead enemy; it cannot be taken until it is over
var _data: VacuumData


func activate(pos: Vector2) -> void:
	_data = pool.vacuum_data
	global_position = pos
	_age = 0.0
	_pop_vel = Pickups.random_pop()
	active = true
	modulate.a = 1.0
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func deactivate() -> void:
	active = false
	_pop_vel = Vector2.ZERO
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## True in the last `flash_time` seconds of the lifetime.
func is_flashing() -> bool:
	return active and _age >= _data.lifetime - _data.flash_time


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _data.lifetime:
		pool.release_magnet()
		return
	modulate.a = 1.0
	if is_flashing():
		var phase := int((_age - (_data.lifetime - _data.flash_time)) * _data.flash_hz * 2.0)
		modulate.a = 1.0 if phase % 2 == 0 else 0.25
	queue_redraw()
	if _pop_vel != Vector2.ZERO:
		_pop_vel = Pickups.pop_step(self, _pop_vel, delta)
		return
	var player := PlayerRegistry.nearest(global_position)
	if player != null and global_position.distance_to(player.global_position + BODY_POINT) <= _data.pick_distance:
		_take(player)


func _take(player: Player) -> void:
	pool.start_vacuum(player)
	Audio.play(&"vacuum_pickup")
	var fx := Effects.get_for(self)
	if fx:
		fx.burst(player.global_position + BODY_POINT, BURST_COLOR, 24, Vector2(60, 160), 0.5, 2.0)
	pool.release_magnet()


func _draw() -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var glow := 10.5 + 1.5 * sin(t * TAU / 1.2)
	draw_circle(Vector2.ZERO, glow, Color(0.37, 0.88, 0.78, 0.16))
	draw_circle(Vector2.ZERO, glow * 0.6, Color(0.37, 0.88, 0.78, 0.22))
	draw_colored_polygon(_ellipse(Vector2(0, 7), Vector2(5, 1.6)), Color(0, 0, 0, 0.3))  # the shadow
	var red := Color("d8342c")
	draw_arc(Vector2(0, 0.5), 4.5, 0.0, PI, 14, red, 3.5)
	draw_line(Vector2(-4.5, 0.5), Vector2(-4.5, -3.5), red, 3.5)
	draw_line(Vector2(4.5, 0.5), Vector2(4.5, -3.5), red, 3.5)
	draw_rect(Rect2(-6.25, -6.0, 3.5, 2.5), Color("dfe6ee"))  # the silver tips
	draw_rect(Rect2(2.75, -6.0, 3.5, 2.5), Color("dfe6ee"))


func _ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 12:
		pts.append(c + Vector2(cos(TAU * i / 12.0) * r.x, sin(TAU * i / 12.0) * r.y))
	return pts

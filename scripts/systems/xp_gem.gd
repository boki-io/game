class_name XPGem
extends Area2D
## Pooled XP pickup. Sits still until a player's XPCollector reaches it, then accelerates in.

const START_SPEED := 70.0
const ACCEL := 500.0
const MAX_SPEED := 320.0
const COLLECT_DISTANCE := 5.0

var value := 1
var target: Player
var pool: Pickups
var _speed := START_SPEED
var _pop_vel := Vector2.ZERO  # the hop out of the dead enemy; the pull-in waits until it is over


func activate(pos: Vector2, amount: int) -> void:
	global_position = pos
	value = amount
	target = null
	_speed = START_SPEED
	_pop_vel = Pickups.random_pop()
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	set_deferred("monitorable", true)


func deactivate() -> void:
	_pop_vel = Vector2.ZERO
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	set_deferred("monitorable", false)
	target = null


func attract(player: Player) -> void:
	if target == null:
		target = player


func _physics_process(delta: float) -> void:
	if _pop_vel != Vector2.ZERO:
		_pop_vel = Pickups.pop_step(self, _pop_vel, delta)
		return
	var vacuum := pool != null and pool.vacuuming()  # a bare scene (no pool) has no vacuum
	if vacuum:
		target = pool.vacuum_target  # the vacuum's player, whoever pulled this one before
	if target == null:
		return
	if not is_instance_valid(target) or target.dead:
		target = null
		return
	var to := target.global_position + Vector2(0, -6) - global_position
	var dist := to.length()
	if dist < COLLECT_DISTANCE:
		target.xp.add(value)
		Audio.play(&"xp_pickup")
		pool.release(self)
		return
	if vacuum:
		_speed = minf(_speed + pool.vacuum_data.pull_accel * delta, pool.vacuum_data.pull_speed)
	else:
		_speed = minf(_speed + ACCEL * delta, MAX_SPEED)
	global_position += to / dist * minf(_speed * delta, dist)


func _draw() -> void:
	var pts := PackedVector2Array([Vector2(0, -4), Vector2(3, 0), Vector2(0, 4), Vector2(-3, 0)])
	draw_colored_polygon(pts, Color("5fe0c8"))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color("1f7a6a"), 1.0)

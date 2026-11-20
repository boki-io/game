class_name Coin
extends Area2D
## Pooled gold pickup. Moves like an XPGem (XPCollector pulls in anything with attract()), but on arrival adds
## to GameSession.run_gold. Not an XPGem: that class is tied to XP.

const START_SPEED := 70.0
const ACCEL := 500.0
const MAX_SPEED := 320.0
const COLLECT_DISTANCE := 5.0

var value := 1
var target: Player
var pool: Pickups
var _speed := START_SPEED
var _pop_vel := Vector2.ZERO  # the hop out of the dead enemy; the pull-in waits until it is over


func activate(pos: Vector2, amount: int = 1) -> void:
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
	if pool.vacuuming():
		target = pool.vacuum_target  # the vacuum's player, whoever pulled this one before
	if target == null:
		return
	if not is_instance_valid(target) or target.dead:
		target = null
		return
	var to := target.global_position + Vector2(0, -6) - global_position
	var dist := to.length()
	if dist < COLLECT_DISTANCE:
		GameSession.run_gold += value
		Audio.play(&"coin")
		pool.release_coin(self)
		return
	_speed = minf(_speed + pool.pull_accel(ACCEL) * delta, pool.pull_speed(MAX_SPEED))
	global_position += to / dist * minf(_speed * delta, dist)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 3.5, Color("c89a1c"))
	draw_circle(Vector2.ZERO, 2.5, Color("ffd23f"))
	draw_circle(Vector2(-0.8, -0.8), 0.9, Color("fff2b8"))

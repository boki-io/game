class_name RangedBrain
extends EnemyBrain
## Walks toward the player until in range, then stands and shoots on a timer.
## Each shot has a warning flash; the aim is taken when the flash ends.

enum State { APPROACH, HOLD }

const SHOT_HEIGHT := Vector2(0, -8)  # fired from and aimed at body height

var _state := State.APPROACH
var _shot_cd := 0.0
var _windup_left := -1.0  # < 0 when not winding up
var _d: RangedData


func setup(e: Enemy) -> void:
	super(e)
	_d = e.data as RangedData


func reset() -> void:
	_state = State.APPROACH
	_shot_cd = _d.fire_interval * 0.5  # the first shot comes a little early
	_windup_left = -1.0


func think(delta: float, target: Player) -> Vector2:
	var dist := enemy.global_position.distance_to(target.global_position)
	match _state:
		State.APPROACH:
			if dist <= _d.hold_distance:
				_state = State.HOLD
			return enemy.chase(target, _d.speed)
		_:
			if dist > _d.resume_distance:
				_cancel_windup()
				_state = State.APPROACH
				return enemy.chase(target, _d.speed)
			_tick_shooting(delta, target)
			return enemy.settle(target, _d.speed)


func cancel() -> void:
	_cancel_windup()


func can_contact() -> bool:
	return false  # it shoots, it doesn't melee


func _tick_shooting(delta: float, target: Player) -> void:
	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left < 0.0:
			_fire(target)
		return
	_shot_cd -= delta
	if _shot_cd <= 0.0:
		_windup_left = _d.windup_time
		enemy.sprite.warn = true
		enemy.sprite.warn_color = Color("ff8a3a")
		Audio.play(&"ranged_windup", -4.0)


func _fire(target: Player) -> void:
	_cancel_windup()
	_shot_cd = _d.fire_interval
	var from := enemy.global_position + SHOT_HEIGHT
	var dir := (target.global_position + SHOT_HEIGHT - from).normalized()
	var pool := Projectiles.get_for(enemy)
	if pool:
		pool.fire(from, dir, _d.projectile_speed, _d.projectile_damage, _d.projectile_lifetime)
		Audio.play(&"ranged_shot", -3.0)


func _cancel_windup() -> void:
	_windup_left = -1.0
	enemy.sprite.warn = false

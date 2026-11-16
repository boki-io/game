class_name RangedBrain
extends EnemyBrain
## Walks toward the player until in range, then stands and shoots on a timer.
## Each shot has a warning flash; the aim is taken when the flash ends.

enum State { APPROACH, HOLD }

const SHOT_HEIGHT := Vector2(0, -8)  # fired from and aimed at body height
const SHOT_RADIUS := 2.0  # the clearance a shot needs on its way to the target
const LOS_LOST_TIME := 0.3  # holding shooters walk again after this long without a clear shot

var _state := State.APPROACH
var _shot_cd := 0.0
var _windup_left := -1.0  # < 0 when not winding up
var _los_lost := 0.0  # seconds the shot has been blocked while holding
var _d: RangedData


func setup(e: Enemy) -> void:
	super(e)
	_d = e.data as RangedData


func reset() -> void:
	_state = State.APPROACH
	_shot_cd = _d.fire_interval * 0.5  # the first shot comes a little early
	_windup_left = -1.0
	_los_lost = 0.0


func think(delta: float, target: Player) -> Vector2:
	var dist := enemy.global_position.distance_to(target.global_position)
	match _state:
		State.APPROACH:
			if dist <= _d.hold_distance and _clear_shot(target):
				_state = State.HOLD
				_los_lost = 0.0
			return enemy.chase(target, _d.speed)  # walks the flow field when a wall is in the way
		_:
			_los_lost = 0.0 if _clear_shot(target) else _los_lost + delta
			if dist > _d.resume_distance or _los_lost >= LOS_LOST_TIME:
				_cancel_windup()
				_state = State.APPROACH
				return enemy.chase(target, _d.speed)
			_tick_shooting(delta, target)
			return enemy.settle(target, _d.speed)


func cancel() -> void:
	_cancel_windup()


func can_contact() -> bool:
	return false  # it shoots, it doesn't melee


func asks_to_move() -> bool:
	return _state == State.APPROACH


## Whether a shot from here would reach the target (the shot flies at body height, so the line is tested there).
func _clear_shot(target: Player) -> bool:
	return enemy.has_line_of_sight(target, SHOT_RADIUS, SHOT_HEIGHT)


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
	if not _clear_shot(target):
		_shot_cd = 0.2  # a wall moved in: no shot, look again shortly
		return
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

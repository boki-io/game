class_name DasherBrain
extends EnemyBrain
## Slow bruiser. Walks at the player; within trigger range it stops, projects a lane on the
## ground (following the player, then locking), dashes along it, and rests.
## A stun cancels the telegraph or dash and sends it straight to recovery.

enum State { APPROACH, AIM, LOCK, DASH, RECOVER }

var _state := State.APPROACH
var _t := 0.0
var _dir := Vector2.RIGHT
var _dash_left := 0.0
var _dash_hit := false
var _d: DasherData
var _lane: DashTelegraph


func setup(e: Enemy) -> void:
	super(e)
	_d = e.data as DasherData
	_lane = DashTelegraph.new()
	_lane.length = _d.dash_distance
	_lane.width = _d.lane_width
	e.add_child(_lane)


func reset() -> void:
	_enter(State.APPROACH)


func think(delta: float, target: Player) -> Vector2:
	_t += delta
	match _state:
		State.APPROACH:
			# It needs a clear line to the target to wind up, so it never aims into a wall.
			if (enemy.global_position.distance_to(target.global_position) <= _d.trigger_range
					and enemy.has_line_of_sight(target, _d.hitbox_radius)):
				_enter(State.AIM)
			return enemy.chase(target, _d.speed)
		State.AIM:
			_dir = _direction_to(target)
			_lane.length = _lane_length()  # shortened at the first obstacle on the aim
			_update_lane()
			if _t >= _d.aim_time:
				_enter(State.LOCK)
			return enemy.settle(target, 0.0)
		State.LOCK:
			_lane.from = enemy.global_position
			_lane.lock_progress = clampf(_t / _d.lock_time, 0.0, 1.0)
			if _t >= _d.lock_time:
				_enter(State.DASH)
			return Vector2.ZERO
		State.DASH:
			var step := minf(_d.dash_speed * delta, _dash_left)
			_dash_left -= step
			if _dash_left <= 0.0:
				_enter(State.RECOVER)
			return _dir * (step / delta) if delta > 0.0 else Vector2.ZERO
		_:
			if _t >= _d.recovery_time:
				_enter(State.APPROACH)
			return Vector2.ZERO


func asks_to_move() -> bool:
	return _state == State.APPROACH


func cancel() -> void:
	if _state == State.AIM or _state == State.LOCK or _state == State.DASH:
		_enter(State.RECOVER)


func contact_damage() -> float:
	return _d.dash_damage if _state == State.DASH else _d.contact_damage


func can_contact() -> bool:
	return not (_state == State.DASH and _dash_hit)  # one hit per dash


func on_contact_hit() -> void:
	if _state == State.DASH:
		_dash_hit = true


func _enter(state: State) -> void:
	_state = state
	_t = 0.0
	var sprite := enemy.sprite
	sprite.warn = state == State.AIM or state == State.LOCK
	sprite.dim = state == State.RECOVER
	match state:
		State.APPROACH:
			sprite.shake = 0.0
			_lane.hide_lane()
		State.AIM:
			sprite.warn_color = _lane.AIM_COLOR
			sprite.shake = 0.6
			_lane.locked = false
			_lane.lock_progress = 0.0
			_lane.show_lane()
			Audio.play(&"dasher_charge", -3.0)
		State.LOCK:
			sprite.warn_color = _lane.LOCK_COLOR
			sprite.shake = 1.6
			_lane.locked = true
			_lane.dir = _dir
		State.DASH:
			sprite.shake = 0.0
			_lane.hide_lane()
			_dash_left = _lane_length()
			_dash_hit = false
			Audio.play(&"dasher_dash", -2.0)
		State.RECOVER:
			sprite.shake = 0.0
			_lane.hide_lane()


func _direction_to(target: Player) -> Vector2:
	var to := target.global_position - enemy.global_position
	var dir := to.normalized() if to.length_squared() > 0.01 else _dir
	enemy.facing = dir
	return dir


## The dash distance, cut short where an obstacle stands on the aim.
func _lane_length() -> float:
	var obstacles := enemy.obstacles
	if obstacles == null:
		return _d.dash_distance
	return obstacles.ray_distance(enemy.global_position, _dir, _d.dash_distance, _d.hitbox_radius)


func _update_lane() -> void:
	_lane.from = enemy.global_position
	_lane.dir = _dir

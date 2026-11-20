class_name Enemy
extends Node2D
## One pooled enemy of any type. Common behavior lives here (health, knockback, stun, contact
## hits, separation, teleport-back); what the enemy actually does comes from data.brain.
## The SpawnDirector calls activate()/deactivate() instead of instancing and freeing.

signal died(enemy: Enemy)

const SEPARATION_RADIUS := 12.0
const SEPARATION_WEIGHT := 0.8
const SEPARATION_MAX_NEIGHBORS := 6  # bounds the cost of a dense crowd
const ARENA_PADDING := 6.0
const FLASH_TIME := 0.09
const HEAVY_HIT := 30.0  # damage that counts as a full-strength hit for the layered hit sound
const BIG_BODY := 720.0  # body area (px^2) that counts as a full-strength kill for the layered kill sound
const RECOIL_TIME := 0.1  # a visual shove of the body away from the player after a hit; the enemy itself does not move
const RECOIL_DISTANCE := 2.0
const SPARK_COUNT := 3
const SPARK_SPEED := Vector2(60.0, 110.0)
const SPARK_LIFE := 0.18
const SPARK_SPREAD := deg_to_rad(100.0)
const DEATH_BURST_SPEED := Vector2(50.0, 100.0)
const DEATH_BURST_LIFE := 0.35
const KILL_SHAKE_TIME := 0.1
const KNOCKBACK_DECAY := 640.0  # px/s^2
const LOS_MARGIN := 6.0  # extra clearance around the body when deciding to walk straight (obstacles)
const FLOW_HOLD := 0.5  # seconds an enemy that switched to the flow field stays on it
const LOS_REFRESH := 4  # physics frames between line-of-sight refreshes
const MAX_STEP := 5.0  # px an enemy moves between two push-outs
const STUCK_TIME := 3.0  # asked to move but moved under STUCK_MOVE for this long: recycled
const STUCK_MOVE := 2.0
const STUCK_MIN_TARGET := 60.0
## Drawn art (MonsterVariant.sprite_frames): 32x32 frames with the feet on row 29, so the bottom centre sits at the
## origin. The slimes look a little to their left, so a target on the right flips them.
const ART_OFFSET := Vector2(-16.0, -30.0)
const ART_FACES_LEFT := true

## Set by the SpawnDirector before the enemy is added to the tree.
var data: EnemyData
var director: SpawnDirector
## Walls and pillars that block it; null in scenes without any (the hub). Set by the director or found in the tree.
var obstacles: ObstacleMap
var active := false
var facing := Vector2.RIGHT
var brain: EnemyBrain

var _contact_cd := 0.0
var _flash_left := 0.0
var _recoil_left := 0.0
var _recoil_dir := Vector2.ZERO
var _knockback := Vector2.ZERO
var _stun_left := 0.0
var _separation_cache := Vector2.ZERO
var _los_clear := true
var _on_flow := false
var _flow_until := 0
var _flow_dir := Vector2.ZERO
var _stuck_anchor := Vector2.ZERO
var _stuck_t := 0.0
var status := EnemyStatus.new()  # slow, freeze, vulnerable, burn (spec 1.0 section 2)
var _anim: AnimatedSprite2D  # only when the type or the applied variant has sprite_frames
var _art_offset := ART_OFFSET
var _art_scale := 1.0
var _art_faces_left := ART_FACES_LEFT
var _one_shot := false  # an attack or hurt animation is playing (it hands back to the base loop when it ends)
var _attack_anim := &""  # the brain's attack animation in progress ("" when none, or when a hurt took over)
var _held := false  # the attack animation stays on its last frame when it ends, until the brain ends it
var _moving := false  # the brain asked to move last frame (walk instead of idle)

@onready var health: Health = $Health
@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Node2D = $Sprite


func _ready() -> void:
	health.died.connect(_on_died)
	sprite.body_color = data.body_color
	sprite.body_size = data.body_size
	sprite.show_aim = false
	var shape := CircleShape2D.new()  # unique per enemy: types differ in size
	shape.radius = data.hitbox_radius
	$Hitbox/CollisionShape2D.shape = shape
	brain = data.brain.new()
	brain.setup(self)
	if data.sprite_frames != null:
		_set_art(data.sprite_frames, data.art_offset, data.art_scale, data.art_faces_left)
	if obstacles == null:
		obstacles = ObstacleMap.get_for(self)


## Dresses the enemy in a map's look (spec 0.6 section 7): colours and a mark on the sprite only, and drawn art
## when the variant has sprite_frames. `data`, the hitbox, the brain and the health are not touched. Null keeps the
## type's own look. Call after the enemy is in the tree.
func apply_variant(variant: MonsterVariant) -> void:
	if variant == null:
		return
	sprite.body_color = variant.body_color
	sprite.outline_color = variant.outline_color
	sprite.eye_color = variant.eye_color
	sprite.mark = int(variant.mark)
	sprite.mark_color = variant.mark_color
	if variant.sprite_frames != null:
		_set_art(variant.sprite_frames, ART_OFFSET, 1.0, ART_FACES_LEFT)
	elif data.sprite_frames == null:
		_set_art(null)  # the type has no art of its own either: back to the drawn body


## Swaps the drawn body for an AnimatedSprite2D showing `frames` (a child of the placeholder, so the stun tint
## applies to it and its shadow stays), or back to the placeholder body when null. The defaults are the slimes'
## (32 px frames, feet on row 29, looking left); a type's own art passes its EnemyData values.
func _set_art(frames: SpriteFrames, offset := ART_OFFSET, art_scale := 1.0, faces_left := ART_FACES_LEFT) -> void:
	if frames == null or not (frames.has_animation(&"bounce") or frames.has_animation(&"idle")):
		if _anim:
			_anim.queue_free()
			_anim = null
		sprite.body_visible = true
		return
	if _anim == null:
		_anim = AnimatedSprite2D.new()
		_anim.centered = false
		_anim.animation_finished.connect(_on_anim_finished)
		sprite.add_child(_anim)
	_art_offset = offset
	_art_scale = art_scale
	_art_faces_left = faces_left
	_anim.offset = offset
	_anim.scale = Vector2(art_scale, art_scale)
	_anim.sprite_frames = frames
	sprite.body_visible = false
	_play_base()


## The loop the enemy is in when nothing else is playing: `walk` while it moves and `idle` when it stands (art with
## those two), else `bounce` (the slimes). Starts on a frame that depends on the enemy so a crowd does not move in step.
func _play_base() -> void:
	_one_shot = false
	_attack_anim = &""
	_held = false
	_anim.speed_scale = 1.0
	var frames := _anim.sprite_frames
	var base := &"bounce"
	if frames.has_animation(&"walk") and _moving:
		base = &"walk"
	elif frames.has_animation(&"idle"):
		base = &"idle"
	_anim.play(base)
	_anim.set_frame_and_progress((get_instance_id() + Engine.get_physics_frames()) % frames.get_frame_count(base), 0.0)


## Plays a one-shot animation of the art (hurt, attack); false when the art has none of that name. `fit_time` > 0
## stretches or squeezes it to take that many seconds (the art's own length is not the brain's timing).
func _play_one_shot(anim: StringName, fit_time := 0.0) -> bool:
	if _anim == null or not _anim.sprite_frames.has_animation(anim):
		return false
	_one_shot = true
	_attack_anim = &""
	_held = false
	var frames := _anim.sprite_frames
	var length := 0.0
	for i in frames.get_frame_count(anim):
		length += frames.get_frame_duration(anim, i)
	length /= frames.get_animation_speed(anim)
	_anim.speed_scale = length / fit_time if fit_time > 0.0 and length > 0.0 else 1.0
	_anim.play(anim)
	return true


func _on_anim_finished() -> void:
	if active and _one_shot and not _held:
		_play_base()


## The brain starts an attack: the art's `attack` animation plays (the ranged enemy's peak is the shot). Art with
## its own phases passes the animation (`windup`, `dash`), the seconds it should take, and `hold` to stay on the last
## frame until the next call or cancel_attack().
func play_attack(anim := &"attack", fit_time := 0.0, hold := false) -> void:
	if _play_one_shot(anim, fit_time):
		_attack_anim = anim
		_held = hold


## The attack was interrupted or is over (stun, freeze, walking on, recovery): an attack animation in progress ends.
func cancel_attack() -> void:
	if _anim and _one_shot and _attack_anim != &"":
		_play_base()


func activate(pos: Vector2, hp_multiplier: float) -> void:
	global_position = pos
	health.setup(data.max_health * hp_multiplier)
	_contact_cd = 0.0
	_flash_left = 0.0
	_recoil_left = 0.0
	sprite.position = Vector2.ZERO
	_knockback = Vector2.ZERO
	_stun_left = 0.0
	status.reset()
	_refresh_tint()
	sprite.flash = false
	sprite.warn = false
	sprite.shake = 0.0
	sprite.dim = false
	if _anim:
		_anim.flip_h = _flips(facing)
		_moving = false
		_play_base()
	brain.reset()
	_los_clear = true
	_on_flow = false
	_stuck_t = 0.0
	_stuck_anchor = pos
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	hitbox.set_deferred("monitoring", true)
	EnemyGrid.register(self)


func deactivate() -> void:
	active = false
	status.reset()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	hitbox.set_deferred("monitoring", false)
	EnemyGrid.unregister(self)


func _exit_tree() -> void:
	EnemyGrid.unregister(self)


## `quiet` (burn ticks): the damage number and the health change only, no hit sound, spark, recoil or flash.
## Vulnerable multiplies the amount first, so the number shown is the HP lost.
func take_damage(amount: float, quiet := false) -> void:
	if not active or health.current <= 0.0:
		return
	if status.any_active:
		amount *= status.damage_multiplier()
	health.take_damage(amount)
	var fx := Effects.get_for(self)
	if fx:
		fx.damage_number(global_position + Vector2(0, -data.body_size.y - 6.0), amount)
	if quiet:
		return
	if health.current > 0.0:
		Audio.impact(&"hit", amount / HEAVY_HIT)  # a killing blow plays the death sound instead (_on_died)
		var near := PlayerRegistry.nearest(global_position)
		var away := (global_position - near.global_position).normalized() if near else Vector2.ZERO
		if fx:
			fx.burst(global_position + Vector2(0, -data.body_size.y / 2.0), sprite.body_color.lightened(0.5), SPARK_COUNT,
				SPARK_SPEED, SPARK_LIFE, 2.0, away, SPARK_SPREAD, Vector2.ZERO, true)
		if not data.immovable and away != Vector2.ZERO:
			_recoil_dir = away
			_recoil_left = RECOIL_TIME
			sprite.position = away * RECOIL_DISTANCE
		if _play_one_shot(&"hurt") or _play_one_shot(&"hit"):
			pass  # the art flashes itself
		else:
			_flash_left = FLASH_TIME
			sprite.flash = true


func stun(seconds: float) -> void:
	if not active or data.immovable:
		return
	_stun_left = maxf(_stun_left, seconds)
	_refresh_tint()
	brain.cancel()


## Stunned or frozen: the brain does not run and contact hits are blocked.
func is_stunned() -> bool:
	return _stun_left > 0.0 or status.freeze_left > 0.0


## Speed x `factor` for `seconds` (0.6 = 40% slower). The lowest factor wins, the time is the longest.
## Dummies (immovable) ignore every status.
func apply_slow(factor: float, seconds: float) -> void:
	if not active or data.immovable:
		return
	status.apply_slow(factor, seconds)
	_refresh_tint()


## Like a stun (the brain is cancelled, no contact hits) with an ice tint; also makes the enemy vulnerable by
## `vulnerable` for the same time.
func freeze(seconds: float, vulnerable := 1.0) -> void:
	if not active or data.immovable:
		return
	status.apply_freeze(seconds, vulnerable)
	_refresh_tint()
	brain.cancel()


## `take_damage` multiplies the amount by `mult` for `seconds`.
func apply_vulnerable(mult: float, seconds: float) -> void:
	if not active or data.immovable:
		return
	status.apply_vulnerable(mult, seconds)


## `dps` damage a second for `seconds`, in ticks of 0.5 s. The dps is final: read it already scaled.
func ignite(dps: float, seconds: float) -> void:
	if not active or data.immovable:
		return
	status.ignite(dps, seconds)
	_refresh_tint()


## The one place the body tint is set: stun, then freeze, then burn, then slow, else white.
func _refresh_tint() -> void:
	if _stun_left > 0.0:
		sprite.modulate = Color(1.0, 1.0, 0.45)
	elif status.freeze_left > 0.0:
		sprite.modulate = Color(0.55, 0.8, 1.0)
	elif status.burn_left > 0.0:
		sprite.modulate = Color(1.0, 0.6, 0.35)
	elif status.slow_left > 0.0:
		sprite.modulate = Color(0.75, 0.95, 0.75)
	else:
		sprite.modulate = Color.WHITE


func apply_knockback(impulse: Vector2) -> void:
	if active and not data.immovable:
		_knockback = impulse


## Velocity toward `target` at `speed`, nudged apart from neighbors. Also turns the sprite.
func chase(target: Player, speed: float) -> Vector2:
	var to := target.global_position - global_position
	var dir := to.normalized() if to.length_squared() > 0.01 else Vector2.ZERO
	if obstacles != null and obstacles.has_obstacles():
		dir = _steer(target, dir)
	if dir != Vector2.ZERO:
		facing = dir
	return (dir + _separation() * SEPARATION_WEIGHT) * speed * status.slow_factor


## Whether the way to `target` is open for a circle of `radius` (always true without obstacles).
func has_line_of_sight(target: Player, radius: float, lift := Vector2.ZERO) -> bool:
	return obstacles == null or obstacles.segment_clear(global_position + lift, target.global_position + lift, radius)


## Straight at the target when the way is clear, otherwise along the flow field. Switching to the flow field
## sticks for FLOW_HOLD seconds so an enemy at a wall corner does not flip-flop. The line-of-sight result is
## cached and refreshed every LOS_REFRESH-th physics frame.
func _steer(target: Player, straight: Vector2) -> Vector2:
	var frame := Engine.get_physics_frames()
	if (frame + get_instance_id()) % LOS_REFRESH == 0:
		_los_clear = has_line_of_sight(target, data.hitbox_radius + LOS_MARGIN)
		if not _los_clear or _on_flow:
			_flow_dir = obstacles.flow_direction(global_position)
	if _on_flow and frame >= _flow_until:
		_on_flow = false
	if _los_clear and not _on_flow:
		return straight
	if not _on_flow:
		_on_flow = true
		_flow_until = frame + int(FLOW_HOLD * Engine.physics_ticks_per_second)
		_flow_dir = obstacles.flow_direction(global_position)
	return _flow_dir if _flow_dir != Vector2.ZERO else straight


## Standing still, turned toward `target`, but still easing away from neighbors.
func settle(target: Player, speed: float) -> Vector2:
	var to := target.global_position - global_position
	if to.length_squared() > 0.01:
		facing = to.normalized()
	return _separation() * SEPARATION_WEIGHT * speed * status.slow_factor * 0.5


func _physics_process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.flash = false
	if _recoil_left > 0.0:
		_recoil_left = maxf(_recoil_left - delta, 0.0)
		sprite.position = _recoil_dir * RECOIL_DISTANCE * (_recoil_left / RECOIL_TIME)
	var target := PlayerRegistry.nearest(global_position)
	if target == null:
		return

	if status.any_active:
		var burn := status.advance(delta)
		if burn > 0.0:
			take_damage(burn, true)
			if not active:
				return  # the burn killed it
		_refresh_tint()
	var velocity := Vector2.ZERO
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			_refresh_tint()
	elif status.freeze_left <= 0.0:
		velocity = brain.think(delta, target)
	var asked := velocity + _knockback
	if obstacles == null:
		global_position += asked * delta
	else:
		# Short steps, each pushed out of obstacles, so a fast knockback or dash cannot jump over a wall.
		var steps := clampi(ceili(asked.length() * delta / MAX_STEP), 1, 8)
		for i in steps:
			global_position = obstacles.push_out(global_position + asked * delta / steps, data.hitbox_radius)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	global_position = global_position.clamp(
		Vector2(ARENA_PADDING, ARENA_PADDING) + Vector2(Arena.wall_margin, Arena.wall_margin),
		Vector2(Arena.world_size) - Vector2(ARENA_PADDING, ARENA_PADDING) - Vector2(Arena.wall_margin, Arena.wall_margin))
	if obstacles != null and not data.immovable:
		# The last position change of the frame: shortest way out of any wall or pillar, so it slides along them.
		global_position = obstacles.push_out(global_position, data.hitbox_radius)
		_check_stuck(delta, asked, target)
	sprite.facing = facing
	if _anim:
		var flip := _flips(facing)
		if _anim.flip_h != flip:
			_anim.flip_h = flip
		var moving := velocity.length_squared() > 1.0
		if moving != _moving:
			_moving = moving
			if not _one_shot:
				_play_base()

	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _contact_cd <= 0.0 and not is_stunned() and brain.can_contact():
		_try_contact_hit()

	var to_target := target.global_position - global_position
	if director and to_target.length() > director.teleport_distance:
		var ring_pos: Variant = director.ring_position(target.global_position)
		if ring_pos != null:
			global_position = ring_pos


## An enemy that asked to move (at least half its speed) but covered under 2 px in a 3 s window, far from its
## target, is recycled through the teleport-back. Covers whatever the flow field misses.
func _check_stuck(delta: float, asked: Vector2, target: Player) -> void:
	if (is_stunned() or director == null or not brain.asks_to_move()
			or asked.length() < data.speed * status.slow_factor * 0.5
			or global_position.distance_to(target.global_position) <= STUCK_MIN_TARGET):
		_stuck_anchor = global_position
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t < STUCK_TIME:
		return
	var moved := global_position.distance_to(_stuck_anchor)
	_stuck_anchor = global_position
	_stuck_t = 0.0
	if moved < STUCK_MOVE:
		var ring_pos: Variant = director.ring_position(target.global_position)
		if ring_pos != null:
			global_position = ring_pos
			_stuck_anchor = global_position


func _try_contact_hit() -> void:
	for area in hitbox.get_overlapping_areas():
		if area is Hurtbox:
			var applied: bool = area.receive_hit(brain.contact_damage())
			_contact_cd = data.contact_interval
			if applied:
				brain.on_contact_hit()


func _separation() -> Vector2:
	# Recomputed every other physics frame (alternating by instance), reusing the last result in between.
	var id := get_instance_id()
	if (Engine.get_physics_frames() + id) % 2 == 0:
		_separation_cache = EnemyGrid.separation(global_position, SEPARATION_RADIUS, self,
			SEPARATION_MAX_NEIGHBORS, id)
	return _separation_cache


func _flips(dir: Vector2) -> bool:
	return dir.x > 0.0 if _art_faces_left else dir.x < 0.0


func _on_died() -> void:
	Audio.impact(&"kill", data.body_size.x * data.body_size.y / BIG_BODY)
	var fx := Effects.get_for(self)
	if fx:
		if _anim and _anim.sprite_frames.has_animation(&"death"):
			# This node is pooled and hidden at once, so the puddle is an effect of its own, not a state of this sprite.
			fx.play_once(_anim.sprite_frames, &"death", global_position, _art_offset, _anim.flip_h, _anim.scale)
		else:
			fx.puff(global_position + Vector2(0, -8), sprite.body_color)
		# A burst in the enemy's own colour, more bits for a bigger body (Grunt 6, Ranged 7, Dasher 14).
		var count := clampi(roundi(data.body_size.x * data.body_size.y / 30.0), 5, 14)
		fx.burst(global_position + Vector2(0, -data.body_size.y / 2.0), sprite.body_color, count,
			DEATH_BURST_SPEED, DEATH_BURST_LIFE, 2.0)
	if data.kill_shake > 0.0:
		CameraFollow.shake(self, data.kill_shake, KILL_SHAKE_TIME)
	died.emit(self)

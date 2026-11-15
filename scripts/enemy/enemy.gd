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
const FLASH_TIME := 0.06
const KNOCKBACK_DECAY := 640.0  # px/s^2

## Set by the SpawnDirector before the enemy is added to the tree.
var data: EnemyData
var director: SpawnDirector
var active := false
var facing := Vector2.RIGHT
var brain: EnemyBrain

var _contact_cd := 0.0
var _flash_left := 0.0
var _knockback := Vector2.ZERO
var _stun_left := 0.0
var _separation_cache := Vector2.ZERO

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


func activate(pos: Vector2, hp_multiplier: float) -> void:
	global_position = pos
	health.setup(data.max_health * hp_multiplier)
	_contact_cd = 0.0
	_flash_left = 0.0
	_knockback = Vector2.ZERO
	_stun_left = 0.0
	sprite.modulate = Color.WHITE
	sprite.flash = false
	sprite.warn = false
	sprite.shake = 0.0
	sprite.dim = false
	brain.reset()
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	hitbox.set_deferred("monitoring", true)
	EnemyGrid.register(self)


func deactivate() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	hitbox.set_deferred("monitoring", false)
	EnemyGrid.unregister(self)


func _exit_tree() -> void:
	EnemyGrid.unregister(self)


func take_damage(amount: float) -> void:
	if not active or health.current <= 0.0:
		return
	health.take_damage(amount)
	Audio.play(&"enemy_hit", -6.0)
	var fx := Effects.get_for(self)
	if fx:
		fx.damage_number(global_position + Vector2(0, -data.body_size.y - 6.0), amount)
	if health.current > 0.0:
		_flash_left = FLASH_TIME
		sprite.flash = true


func stun(seconds: float) -> void:
	if not active or data.immovable:
		return
	_stun_left = maxf(_stun_left, seconds)
	sprite.modulate = Color(1.0, 1.0, 0.45)
	brain.cancel()


func apply_knockback(impulse: Vector2) -> void:
	if active and not data.immovable:
		_knockback = impulse


## Velocity toward `target` at `speed`, nudged apart from neighbors. Also turns the sprite.
func chase(target: Player, speed: float) -> Vector2:
	var to := target.global_position - global_position
	var dir := to.normalized() if to.length_squared() > 0.01 else Vector2.ZERO
	if dir != Vector2.ZERO:
		facing = dir
	return (dir + _separation() * SEPARATION_WEIGHT) * speed


## Standing still, turned toward `target`, but still easing away from neighbors.
func settle(target: Player, speed: float) -> Vector2:
	var to := target.global_position - global_position
	if to.length_squared() > 0.01:
		facing = to.normalized()
	return _separation() * SEPARATION_WEIGHT * speed * 0.5


func _physics_process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.flash = false
	var target := PlayerRegistry.nearest(global_position)
	if target == null:
		return

	var velocity := Vector2.ZERO
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			sprite.modulate = Color.WHITE
	else:
		velocity = brain.think(delta, target)
	global_position += (velocity + _knockback) * delta
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	global_position = global_position.clamp(
		Vector2(ARENA_PADDING, ARENA_PADDING),
		Vector2(Arena.world_size) - Vector2(ARENA_PADDING, ARENA_PADDING))
	sprite.facing = facing

	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _contact_cd <= 0.0 and _stun_left <= 0.0 and brain.can_contact():
		_try_contact_hit()

	var to_target := target.global_position - global_position
	if director and to_target.length() > director.teleport_distance:
		var ring_pos: Variant = director.ring_position(target.global_position)
		if ring_pos != null:
			global_position = ring_pos


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


func _on_died() -> void:
	Audio.play(&"enemy_death", -4.0)
	var fx := Effects.get_for(self)
	if fx:
		fx.puff(global_position + Vector2(0, -8), data.body_color)
	died.emit(self)

class_name Enemy
extends Node2D
## Chases the nearest player, separates lightly from neighbors, hurts on contact.
## Pooled: the SpawnDirector calls activate()/deactivate() instead of instancing and freeing.

const SEPARATION_RADIUS := 12.0
const SEPARATION_WEIGHT := 0.8
const ARENA_PADDING := 6.0

signal died(enemy: Enemy)

const FLASH_TIME := 0.06

@export var data: EnemyData

var director: SpawnDirector
var active := false
var _contact_cd := 0.0
var _flash_left := 0.0

@onready var health: Health = $Health
@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Node2D = $Sprite


func _ready() -> void:
	health.died.connect(_on_died)


func activate(pos: Vector2, hp_multiplier: float) -> void:
	global_position = pos
	health.setup(data.max_health * hp_multiplier)
	_contact_cd = 0.0
	_flash_left = 0.0
	sprite.flash = false
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
	var fx := Effects.get_for(self)
	if fx:
		fx.damage_number(global_position + Vector2(0, -22), amount)
	if health.current > 0.0:
		_flash_left = FLASH_TIME
		sprite.flash = true


func _physics_process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.flash = false
	var target := PlayerRegistry.nearest(global_position)
	if target == null:
		return

	var to_target := target.global_position - global_position
	var dir := to_target.normalized() if to_target.length_squared() > 0.01 else Vector2.ZERO
	var velocity := (dir + _separation() * SEPARATION_WEIGHT) * data.speed
	global_position += velocity * delta
	global_position = global_position.clamp(
		Vector2(ARENA_PADDING, ARENA_PADDING),
		Vector2(Arena.SIZE) - Vector2(ARENA_PADDING, ARENA_PADDING))
	sprite.facing = dir

	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _contact_cd <= 0.0:
		_try_contact_hit()

	if director and to_target.length() > director.teleport_distance:
		var ring_pos: Variant = director.ring_position(target.global_position)
		if ring_pos != null:
			global_position = ring_pos


func _try_contact_hit() -> void:
	for area in hitbox.get_overlapping_areas():
		if area is Hurtbox:
			area.receive_hit(data.contact_damage)
			_contact_cd = data.contact_interval


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in EnemyGrid.query(global_position, SEPARATION_RADIUS):
		if other == self:
			continue
		var away := global_position - other.global_position
		var dist := away.length()
		if dist < 0.01:
			away = Vector2.from_angle(randf() * TAU)
			dist = 0.01
		push += away / dist * (1.0 - dist / SEPARATION_RADIUS)
	return push.limit_length(1.0)


func _on_died() -> void:
	var fx := Effects.get_for(self)
	if fx:
		fx.puff(global_position + Vector2(0, -8), Color(0.8, 0.25, 0.25))
	died.emit(self)

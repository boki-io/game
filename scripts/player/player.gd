class_name Player
extends CharacterBody2D

signal died

@export var move_speed: float = 90.0
@export var max_hp: float = 100.0

var facing := Vector2.RIGHT
var dead := false

var _face_dir := Vector2.RIGHT
var _face_time := 0.0

@onready var player_input: PlayerInput = $PlayerInput
@onready var sprite: Node2D = $Sprite
@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	PlayerRegistry.register(self)
	health.setup(max_hp)
	health.died.connect(_on_died)
	hurtbox.hit_taken.connect(_on_hit_taken)


func _exit_tree() -> void:
	PlayerRegistry.unregister(self)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var move := player_input.move_vector
	velocity = move * move_speed
	move_and_slide()
	if move != Vector2.ZERO:
		facing = move.normalized()
	_face_time -= delta
	sprite.facing = _face_dir if _face_time > 0.0 else facing
	sprite.aim = player_input.aim_vector


## Briefly turn the sprite toward a cast direction (it otherwise faces movement).
func face_towards(dir: Vector2, duration: float) -> void:
	_face_dir = dir
	_face_time = duration


func _on_hit_taken(_amount: float) -> void:
	sprite.modulate = Color(1, 0.35, 0.35)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _on_died() -> void:
	dead = true
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.4, 0.4, 0.4)
	hurtbox.set_deferred("monitorable", false)
	died.emit()

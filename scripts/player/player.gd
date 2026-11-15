class_name Player
extends CharacterBody2D

@export var move_speed: float = 90.0

var facing := Vector2.RIGHT

@onready var player_input: PlayerInput = $PlayerInput
@onready var sprite: Node2D = $Sprite


func _ready() -> void:
	PlayerRegistry.register(self)


func _exit_tree() -> void:
	PlayerRegistry.unregister(self)


func _physics_process(_delta: float) -> void:
	var move := player_input.move_vector
	velocity = move * move_speed
	move_and_slide()
	if move != Vector2.ZERO:
		facing = move.normalized()
	sprite.facing = facing
	sprite.aim = player_input.aim_vector

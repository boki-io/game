class_name EnemyData
extends Resource

@export var id: StringName
@export var max_health: float = 20.0
@export var speed: float = 45.0  # px/s
@export var contact_damage: float = 5.0
@export var contact_interval: float = 0.5  # seconds between hits while touching
@export var xp_drop: int = 1

class_name RangedData
extends EnemyData

@export_group("Ranged")
@export var hold_distance: float = 130.0  # stops walking at this range
@export var resume_distance: float = 160.0  # walks again if the player gets this far
@export var fire_interval: float = 2.0  # seconds between shots
@export var windup_time: float = 0.4  # warning flash before each shot
@export var projectile_damage: float = 8.0
@export var projectile_speed: float = 110.0  # px/s
@export var projectile_lifetime: float = 3.0

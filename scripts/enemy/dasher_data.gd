class_name DasherData
extends EnemyData

@export_group("Dasher")
@export var trigger_range: float = 110.0  # starts charging when the player is this close
@export var aim_time: float = 0.6  # lane follows the player
@export var lock_time: float = 0.4  # lane is fixed: the dodge window
@export var dash_distance: float = 140.0
@export var dash_speed: float = 300.0  # px/s
@export var recovery_time: float = 0.8  # stands still afterwards
@export var dash_damage: float = 15.0
## Lane drawn on the ground. Keep close to 2 * (hitbox_radius + player hurtbox radius 6)
## so what the player sees is what can hit them.
@export var lane_width: float = 26.0

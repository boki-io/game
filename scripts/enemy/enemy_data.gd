class_name EnemyData
extends Resource
## Numbers and look for one enemy type. The brain script decides how it behaves.

@export var id: StringName
@export var max_health: float = 20.0
@export var speed: float = 45.0  # px/s
@export var contact_damage: float = 5.0
@export var contact_interval: float = 0.5  # seconds between hits while touching
@export var xp_drop: int = 1
@export var body_color: Color = Color(0.8, 0.25, 0.25, 1)
@export var body_size: Vector2 = Vector2(12, 16)
@export var hitbox_radius: float = 7.0
@export var brain: Script  # an EnemyBrain subclass
## Training dummies: knockback and stun do nothing (so slams, meteors and Static Shock neither move nor tint them).
@export var immovable := false
## Camera shake strength when this enemy dies (0 = none). Tough enemies kick the camera; a crowd of grunts must not.
@export var kill_shake: float = 0.0

@export_group("Spawning")
@export var spawn_weight: float = 70.0  # relative weight once fully phased in
@export var unlock_time: float = 0.0  # seconds into the run before it can spawn
@export var full_weight_time: float = 0.0  # seconds at which it reaches full weight


## Spawn weight at run time t: 0 before unlock, ramping linearly up to full weight.
func weight_at(t: float) -> float:
	if t < unlock_time:
		return 0.0
	if full_weight_time <= unlock_time:
		return spawn_weight
	return spawn_weight * clampf((t - unlock_time) / (full_weight_time - unlock_time), 0.0, 1.0)

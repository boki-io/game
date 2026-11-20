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

@export_group("Art")
## Optional drawn art for this type on every map (a map's MonsterVariant can still bring its own, as the grunt's
## slimes do). Animations: `idle` and `walk` (loop), `attack` (once, played when a shot winds up), `hurt` and `death`
## (once). A set with only `bounce` / `hit` / `death` (the slimes) is also understood. Null keeps the drawn body.
@export var sprite_frames: SpriteFrames
## Scale of the frames (a 64 px frame at 0.5 is as big as a 32 px slime frame).
@export var art_scale := 1.0
## Top-left corner of a frame relative to the enemy's feet, before scaling (the node's `offset`).
@export var art_offset := Vector2.ZERO
## True when the art looks left in the frames (the slimes do); false when it looks right.
@export var art_faces_left := false

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

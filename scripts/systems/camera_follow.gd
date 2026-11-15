extends Camera2D
## Follows the nearest player (to its own position) and stays inside the arena.


func _ready() -> void:
	limit_left = 0
	limit_top = 0
	limit_right = Arena.SIZE.x
	limit_bottom = Arena.SIZE.y
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _physics_process(_delta: float) -> void:
	var target: Player = PlayerRegistry.nearest(global_position)
	if target:
		# Snap to whole pixels so the sprite doesn't shimmer at low resolution.
		global_position = (target.global_position - Vector2(0, 12)).round()

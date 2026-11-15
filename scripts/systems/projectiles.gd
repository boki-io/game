class_name Projectiles
extends Node2D
## Pool for enemy projectiles, capped so a crowd of shooters can't flood the screen.

const MAX_LIVE := 60

@export var projectile_scene: PackedScene

var _pool: Array[EnemyProjectile] = []
var _live := 0


static func get_for(node: Node) -> Projectiles:
	return node.get_tree().get_first_node_in_group(&"projectiles") as Projectiles


func _ready() -> void:
	add_to_group(&"projectiles")
	z_index = 6  # above the y-sorted world, below effects


func fire(pos: Vector2, dir: Vector2, speed: float, damage: float, lifetime: float) -> void:
	if _live >= MAX_LIVE:
		return
	var p: EnemyProjectile
	if _pool.is_empty():
		p = projectile_scene.instantiate()
		p.pool = self
		add_child(p)
	else:
		p = _pool.pop_back()
	_live += 1
	p.launch(pos, dir, speed, damage, lifetime)


func release(p: EnemyProjectile) -> void:
	_live -= 1
	_pool.append(p)

class_name PlayerProjectiles
extends Node2D
## Pool for the player's spell bolts, capped so rapid fire can't flood the screen.

const MAX_LIVE := 40

@export var projectile_scene: PackedScene

var _pool: Array[PlayerProjectile] = []
var _live := 0


static func get_for(node: Node) -> PlayerProjectiles:
	return node.get_tree().get_first_node_in_group(&"player_projectiles") as PlayerProjectiles


func _ready() -> void:
	add_to_group(&"player_projectiles")
	z_index = 6  # above the y-sorted world, below effects


## Returns false (and fires nothing) when the live cap is reached. `opts` (all optional, see
## PlayerProjectile.launch): hits, bounces, bounce_reach, arrow, steady, steady_full.
func fire(pos: Vector2, dir: Vector2, speed: float, damage: float, range_px: float, pierce: int,
		opts: Dictionary = {}) -> bool:
	if _live >= MAX_LIVE:
		return false
	var p: PlayerProjectile
	if _pool.is_empty():
		p = projectile_scene.instantiate()
		p.pool = self
		add_child(p)
	else:
		p = _pool.pop_back()
	_live += 1
	p.launch(pos, dir, speed, damage, range_px, pierce, opts)
	return true


## Retires every bolt in flight (used when the hub changes character).
func clear() -> void:
	for child in get_children():
		var p := child as PlayerProjectile
		if p and p.active:
			p.retire()


func release(p: PlayerProjectile) -> void:
	_live -= 1
	_pool.append(p)

class_name Pickups
extends Node2D
## Owns the XP gem pool.

@export var gem_scene: PackedScene

var _pool: Array[XPGem] = []


func spawn_gem(pos: Vector2, value: int) -> void:
	var gem: XPGem
	if _pool.is_empty():
		gem = gem_scene.instantiate()
		gem.pool = self
		add_child(gem)
	else:
		gem = _pool.pop_back()
	gem.activate(pos, value)


func release(gem: XPGem) -> void:
	gem.deactivate()
	_pool.append(gem)

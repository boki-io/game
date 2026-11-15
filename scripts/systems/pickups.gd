class_name Pickups
extends Node2D
## Owns the XP gem pool and the coin pool.

@export var gem_scene: PackedScene
@export var coin_scene: PackedScene

var _pool: Array[XPGem] = []
var _coin_pool: Array[Coin] = []


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


func spawn_coin(pos: Vector2) -> void:
	var coin: Coin
	if _coin_pool.is_empty():
		coin = coin_scene.instantiate()
		coin.pool = self
		add_child(coin)
	else:
		coin = _coin_pool.pop_back()
	coin.activate(pos)


func release_coin(coin: Coin) -> void:
	coin.deactivate()
	_coin_pool.append(coin)

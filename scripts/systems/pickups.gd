class_name Pickups
extends Node2D
## Owns the XP gem pool and the coin pool.

@export var gem_scene: PackedScene
@export var coin_scene: PackedScene

## A pickup hops out of the dead enemy before it can be pulled in: 150 to 170 px/s, slowing at 1000 px/s^2 (11 to 15 px).
const POP_SPEED := Vector2(150.0, 170.0)
const POP_DECEL := 1000.0

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


## A random starting velocity for a pickup's pop.
static func random_pop() -> Vector2:
	return Vector2.from_angle(randf() * TAU) * randf_range(POP_SPEED.x, POP_SPEED.y)


## One frame of a pop: moves `item` by `vel`, keeps it inside the arena as enemies are kept, and returns the slowed velocity.
static func pop_step(item: Node2D, vel: Vector2, delta: float) -> Vector2:
	item.global_position += vel * delta
	var pad := Vector2(Enemy.ARENA_PADDING + Arena.wall_margin, Enemy.ARENA_PADDING + Arena.wall_margin)
	item.global_position = item.global_position.clamp(pad, Vector2(Arena.world_size) - pad)
	return vel.move_toward(Vector2.ZERO, POP_DECEL * delta)

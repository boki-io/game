class_name Pickups
extends Node2D
## Owns the XP gem pool and the coin pool, and the vacuum (spec 1.3): while it runs, every gem and coin flies to
## `vacuum_target` fast. Gems and coins read it each frame (`vacuuming()`), so nothing is looped over when it starts.

@export var gem_scene: PackedScene
@export var coin_scene: PackedScene
@export var vacuum_data: VacuumData
@export var magnet_scene: PackedScene

## A pickup hops out of the dead enemy before it can be pulled in: 150 to 170 px/s, slowing at 1000 px/s^2 (11 to 15 px).
const POP_SPEED := Vector2(150.0, 170.0)
const POP_DECEL := 1000.0

var _pool: Array[XPGem] = []
var _coin_pool: Array[Coin] = []
## The player the vacuum pulls everything to (null when it is not running) and the seconds it has left.
var vacuum_target: Player
var vacuum_left := 0.0
var _magnet: VacuumMagnet  # the one magnet, made on the first drop


func _ready() -> void:
	if vacuum_data == null:
		vacuum_data = VacuumData.new()


func _physics_process(delta: float) -> void:
	if vacuum_target == null:
		return
	# A freed player is not null, so the validity check comes first.
	vacuum_left -= delta
	if vacuum_left <= 0.0 or not is_instance_valid(vacuum_target) or vacuum_target.dead:
		vacuum_target = null
		vacuum_left = 0.0


## Starts the vacuum for `player` (or restarts it: a second one refreshes the time and takes over the target).
## A null or dead player does nothing.
func start_vacuum(player: Player) -> void:
	if not is_instance_valid(player) or player.dead:
		return
	vacuum_target = player
	vacuum_left = vacuum_data.effect_time


## The magnet is lying on the ground.
func magnet_on_map() -> bool:
	return _magnet != null and _magnet.active


## A killed mob's chance to drop the magnet. Nothing is rolled while one lies on the ground or the vacuum runs, so
## there is never more than one. Returns whether one was placed.
func roll_magnet(pos: Vector2) -> bool:
	if magnet_on_map() or vacuuming() or randf() >= vacuum_data.drop_chance:
		return false
	place_magnet(pos)
	return true


## Puts the magnet on the ground at `pos` (it hops out like a coin).
func place_magnet(pos: Vector2) -> void:
	if _magnet == null:
		_magnet = magnet_scene.instantiate()
		_magnet.pool = self
		add_child(_magnet)
	_magnet.activate(pos)


func release_magnet() -> void:
	_magnet.deactivate()


func vacuuming() -> bool:
	return vacuum_target != null


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

class_name SpawnDirector
extends Node
## Spawns enemies on a ring just outside the screen, with a rising rate and HP scaling.
## The type of each spawn is picked by weight; types phase in over time (see EnemyData).
## Owns one enemy pool per type.

@export var enemy_scene: PackedScene
@export var enemy_types: Array[EnemyData] = []
@export var start_rate: float = 0.8  # spawns/s at 0:00 (v0.6: 20% below the original 1.0)
@export var end_rate: float = 6.4  # spawns/s at the end of the run (v0.6: 20% below the original 8.0)
@export var alive_cap: int = 300
@export var hp_scale_per_minute: float = 0.15
@export var ring_margin: float = 24.0  # px beyond the screen corner
const SPAWN_RADIUS := 7.0  # a mob's footprint when checking a spawn against obstacles

@export var teleport_margin: float = 120.0  # px beyond the ring before an enemy is recycled

var run_manager: RunManager
## The stage being played. Its modifiers last for this stage only (a new arena is built for the next one).
var stage := StageData.new()
## Added to the stage's coin chance (camp Greed); the run sets it before the first spawn.
var coin_bonus := 0.0
var pickups: Pickups
var enemies_root: Node2D
## Walls and pillars; spawns avoid them and enemies are given it. Null in scenes without any.
var obstacles: ObstacleMap
var alive := 0
var alive_by_type: Dictionary = {}  # id -> count

var ring_radius := 0.0
var teleport_distance := 0.0

var _accum := 0.0
var _pools: Dictionary = {}  # EnemyData -> Array[Enemy]


func _ready() -> void:
	var view := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	ring_radius = view.length() / 2.0 + ring_margin
	teleport_distance = ring_radius + teleport_margin
	for type in enemy_types:
		_pools[type] = []
		alive_by_type[type.id] = 0


## Applies a stage's population modifier to the spawn rate and alive cap. Call once, before the stage starts.
func apply_stage(data: StageData) -> void:
	stage = data
	start_rate = data.scaled_rate(start_rate)
	end_rate = data.scaled_rate(end_rate)
	alive_cap = data.scaled_cap(alive_cap)


func _physics_process(delta: float) -> void:
	if not run_manager.running:
		return
	var t := clampf(run_manager.elapsed / RunManager.RUN_DURATION, 0.0, 1.0)
	_accum += lerpf(start_rate, end_rate, t) * delta
	while _accum >= 1.0:
		_accum -= 1.0
		if alive >= alive_cap:
			_accum = 0.0
			break
		_spawn()


func _spawn() -> void:
	var player := PlayerRegistry.random_alive()
	if player == null:
		return
	var type := _pick_type(run_manager.elapsed)
	if type == null:
		return
	var pos: Variant = ring_position(player.global_position)
	if pos == null:
		return
	var hp_mult := 1.0 + hp_scale_per_minute * run_manager.elapsed / 60.0
	var enemy := _acquire(type)
	enemy.activate(pos, hp_mult)
	alive += 1
	alive_by_type[type.id] += 1


## Weighted random type for run time t, or null if nothing is unlocked.
func _pick_type(t: float) -> EnemyData:
	var total := 0.0
	for type in enemy_types:
		total += type.weight_at(t)
	if total <= 0.0:
		return null
	var roll := randf() * total
	for type in enemy_types:
		roll -= type.weight_at(t)
		if roll <= 0.0:
			return type
	return enemy_types[0]


## A random point on the spawn ring around `around` that lies inside the arena, or null.
func ring_position(around: Vector2) -> Variant:
	var bounds := Rect2(Vector2.ZERO, Vector2(Arena.world_size)).grow(-8.0 - Arena.wall_margin)
	var best: Variant = null
	for i in 8:
		var p := around + Vector2.from_angle(randf() * TAU) * ring_radius
		if bounds.has_point(p):
			if obstacles == null or not obstacles.blocked(p, SPAWN_RADIUS):
				return p
			if best == null:
				best = p
	if best != null:  # every inside candidate was in an obstacle: take the nearest free spot instead
		var out := obstacles.push_out(best, SPAWN_RADIUS)
		return out if bounds.has_point(out) else best
	return null


func release(enemy: Enemy) -> void:
	enemy.deactivate()
	_pools[enemy.data].append(enemy)
	alive -= 1
	alive_by_type[enemy.data.id] -= 1


func _acquire(type: EnemyData) -> Enemy:
	var pool: Array = _pools[type]
	if not pool.is_empty():
		return pool.pop_back()
	var enemy: Enemy = enemy_scene.instantiate()
	enemy.data = type
	enemy.director = self
	enemy.obstacles = obstacles
	enemy.died.connect(_on_enemy_died)
	enemies_root.add_child(enemy)
	# With no map set (editor runs, most tests) the default cave dresses the enemy: only its grunt slime, same colours.
	var theme: MapTheme = stage.theme if stage.theme != null else MapRegistry.default()
	enemy.apply_variant(theme.variant_for(type.id))
	return enemy


func _on_enemy_died(enemy: Enemy) -> void:
	run_manager.kills += 1
	if pickups:
		pickups.spawn_gem(enemy.global_position, stage.scaled_xp(enemy.data.xp_drop))
		# Mobs that drop no XP (the hub dummies) drop no coins either.
		if enemy.data.xp_drop > 0 and randf() < clampf(stage.coin_chance() + coin_bonus, 0.0, 1.0):
			pickups.spawn_coin(enemy.global_position)
	release(enemy)

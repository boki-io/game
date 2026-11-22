extends RefCounted
## Shared setup for the horde tests (spec 1.8 sections 5 and 7): a real Player (from `tests/fixture.gd`, the arena run with
## its spawner off), the real world data, a `WorldObstacles`, a stub that counts the reward calls, the real plan, and a
## `HordeDirector` on its own `Enemies` root. Load it with `load()`; it names no class that uses an autoload.

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const SitesS := preload("res://scripts/overworld/horde_sites.gd")
const PlanS := preload("res://scripts/overworld/horde_plan.gd")
const JourneyS := preload("res://scripts/overworld/journey.gd")
const ObstaclesS := preload("res://scripts/overworld/world_obstacles.gd")

## Where a far-away hero stands: the north-east corner of the world, no horde within 1,200 px of it.
const FAR := Vector2(31900.0, 100.0)

static var _plan: Array = []


## Counts what the director asks of the pickups (the real `Pickups` needs a scene).
class Rewards extends Node:
	var gems: Array = []  # [pos, value]
	var coins := 0
	var magnets := 0
	var items := 0

	func spawn_gem(pos: Vector2, value: int) -> void:
		gems.append([pos, value])

	func spawn_coin(_pos: Vector2) -> void:
		coins += 1

	func roll_magnet(_pos: Vector2) -> bool:
		magnets += 1
		return false

	func roll_item_drop(_pos: Vector2, _chance: float, _rng = null) -> bool:
		items += 1
		return false


## The plan of the real sites and rules (built once per process).
static func plan(world, rules) -> Array:
	if _plan.is_empty():
		_plan = PlanS.build(world, SitesS.shared(), rules)
	return _plan


## Returns {main, world, rules, plan, director, obstacles, rewards, journey, player, enemies, fx}. `overrides` sets fields
## on a copy of hordes.tres (e.g. {"alert_radius": 0.0}). The hero stands at FAR with enormous health.
static func build(tree: SceneTree, overrides := {}) -> Dictionary:
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(tree, &"knight")
	await F.frames(tree, 2)
	var world = WorldDataS.shared()
	var base = load("res://content/overworld/hordes.tres")
	var rules = base.duplicate()
	for k in overrides:
		rules.set(k, overrides[k])
	var p = F.player()
	p.health.setup(1.0e9)
	p.caster.set_physics_process(false)
	p.global_position = FAR
	Arena.world_size = Vector2i(WorldDataS.SIZE * WorldDataS.TILE_PX, WorldDataS.SIZE * WorldDataS.TILE_PX)
	var fx := Node2D.new()
	tree.root.add_child(fx)
	var enemies := Node2D.new()
	fx.add_child(enemies)
	var obstacles = ObstaclesS.new()
	obstacles.setup_world(world)
	fx.add_child(obstacles)
	var rewards := Rewards.new()
	fx.add_child(rewards)
	var journey = JourneyS.new_for(&"knight", world)
	var director = load("res://scripts/overworld/horde_director.gd").new()
	fx.add_child(director)
	var the_plan := plan(world, base)
	director.setup(world, the_plan, rules, obstacles, enemies, rewards, journey)
	return {main = main, fx = fx, world = world, rules = rules, plan = the_plan, director = director,
		obstacles = obstacles, rewards = rewards, journey = journey, player = p, enemies = enemies}


## Frees what `build` made.
static func finish(tree: SceneTree, ctx: Dictionary) -> void:
	ctx.fx.queue_free()
	ctx.main.queue_free()
	await tree.process_frame
	tree.paused = false

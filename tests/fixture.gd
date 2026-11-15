extends RefCounted
## Shared setup for the gameplay tests. In a --script SceneTree the autoloads only exist from the first frame,
## so a test must not name classes that use them (Player, Enemy, AbilityCaster ...) in its own code. It loads
## this file at runtime instead:  var F: GDScript = load("res://tests/fixture.gd")

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")


## Loads a run (main.tscn) with `character_id`, the spawner switched off and the run clock stopped.
## The Player stands in the middle of the arena. Returns the run's root node.
static func start_run(tree: SceneTree, character_id: StringName) -> Node:
	for c in CharacterRegistry.all():
		if c.id == character_id:
			GameSession.character = c
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	tree.current_scene = main
	main.spawn_director.set_physics_process(false)
	main.run_manager.running = false
	return main


static func player() -> Player:
	return PlayerRegistry.players[0]


## An active enemy of `id` (data/enemies/<id>.tres) at `pos`. A frozen one stays where it is (it is still hit
## by abilities, but never moves, attacks or hits the Player).
static func spawn_enemy(main: Node, id: String, pos: Vector2, hp_multiplier: float = 1.0,
		frozen: bool = false) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.data = load("res://data/enemies/%s.tres" % id)
	main.get_node("World/Enemies").add_child(e)
	e.activate(pos, hp_multiplier)
	if frozen:
		e.set_physics_process(false)
	return e


static func upgrade(p: Player, id: String) -> void:
	p.upgrades.apply(load("res://data/upgrades/%s.tres" % id))


static func frames(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.physics_frame


static func seconds(tree: SceneTree, time: float) -> void:
	await frames(tree, int(ceil(time * Engine.physics_ticks_per_second)))


static func cast(p: Player, slot: StringName, aim: Vector2 = Vector2.RIGHT) -> void:
	p.player_input.aim_vector = aim
	p.player_input.ability_pressed.emit(slot)

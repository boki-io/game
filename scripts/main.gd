extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROP_SCRIPT := preload("res://scripts/systems/prop.gd")
const PROP_COUNT := 14
const PROP_MARGIN := 48.0

@onready var players_root: Node2D = $World/Players
@onready var props_root: Node2D = $World/Props
@onready var run_manager: RunManager = $RunManager
@onready var spawn_director: SpawnDirector = $SpawnDirector


func _ready() -> void:
	spawn_director.run_manager = run_manager
	spawn_director.enemies_root = $World/Enemies
	spawn_director.pickups = $Pickups
	var debug: Label = $UI/DebugOverlay
	debug.run_manager = run_manager
	debug.spawn_director = spawn_director
	var end_screen: Control = $UI/EndScreen
	end_screen.run_manager = run_manager
	run_manager.run_ended.connect(end_screen.show_result)
	var pause_menu := $UI/PauseMenu
	pause_menu.level_up_menu = $UI/LevelUpMenu
	pause_menu.end_screen = end_screen

	_spawn_props()
	var player: Player = PLAYER_SCENE.instantiate()
	player.character = GameSession.character
	player.position = Vector2(Arena.SIZE) / 2.0
	players_root.add_child(player)
	player.died.connect(run_manager.on_player_died)
	player.xp.leveled_up.connect(func(_level: int) -> void: $UI/LevelUpMenu.queue_level_up(player))
	$UI/Hud.bind(player, run_manager)


func _spawn_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var center := Vector2(Arena.SIZE) / 2.0
	for i in PROP_COUNT:
		var pos := Vector2(
			rng.randf_range(PROP_MARGIN, Arena.SIZE.x - PROP_MARGIN),
			rng.randf_range(PROP_MARGIN, Arena.SIZE.y - PROP_MARGIN))
		if pos.distance_to(center) < 60.0:
			continue
		var prop := StaticBody2D.new()
		prop.set_script(PROP_SCRIPT)
		prop.position = pos
		props_root.add_child(prop)

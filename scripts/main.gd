extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROP_SCRIPT := preload("res://scripts/systems/prop.gd")
const PROP_COUNT := 8  # with the 6 rock walls, the same 14 obstacles the arena always had
const PROP_MARGIN := 48.0
const WALL_BAND := 16.0  # matches the Arena's wall_band in main.tscn
const START_CLEARING := 110.0  # radius around the start that stays free of walls, props and decor
const DECOR_COUNT := 110

## Footprints of the freestanding rock walls (see CaveWall.layout).
var rock_walls: Array[Rect2] = []

@onready var players_root: Node2D = $World/Players
@onready var props_root: Node2D = $World/Props
@onready var run_manager: RunManager = $RunManager
@onready var spawn_director: SpawnDirector = $SpawnDirector


func _ready() -> void:
	spawn_director.run_manager = run_manager
	spawn_director.enemies_root = $World/Enemies
	spawn_director.pickups = $Pickups
	# Without a stage (main.tscn run from the editor) every modifier is 0%.
	spawn_director.apply_stage(GameSession.current_stage if GameSession.current_stage else StageData.new())
	var debug: Label = $UI/DebugOverlay
	debug.run_manager = run_manager
	debug.spawn_director = spawn_director
	var end_screen: Control = $UI/EndScreen
	end_screen.run_manager = run_manager
	run_manager.run_ended.connect(end_screen.show_result)
	var pause_menu := $UI/PauseMenu
	pause_menu.level_up_menu = $UI/LevelUpMenu
	pause_menu.end_screen = end_screen

	_build_cave()
	_spawn_props()
	var player: Player = PLAYER_SCENE.instantiate()
	player.character = GameSession.character
	player.position = Vector2(Arena.world_size) / 2.0
	players_root.add_child(player)
	player.died.connect(run_manager.on_player_died)
	player.xp.leveled_up.connect(func(_level: int) -> void: $UI/LevelUpMenu.queue_level_up(player))
	$UI/Hud.bind(player, run_manager)


## Rock walls of varied length, torches along the outer walls, and decor, all seeded.
func _build_cave() -> void:
	var size := Vector2(Arena.world_size)
	var centre := size / 2.0
	var start := Rect2(centre - Vector2(START_CLEARING, START_CLEARING), Vector2(START_CLEARING, START_CLEARING) * 2.0)
	rock_walls = CaveWall.layout(size, WALL_BAND, [start])
	for rect in rock_walls:
		var wall := CaveWall.new()
		props_root.add_child(wall)
		wall.setup(rect)
	var cave: CaveWalls = $Cave
	cave.wall_band = WALL_BAND
	var torches: Array[Vector2] = []
	for x in [200.0, 600.0, 1000.0, 1400.0]:
		torches.append(Vector2(x, 9.0))
		torches.append(Vector2(x + 100.0, size.y - WALL_BAND + 1.0))
	for y in [220.0, 670.0]:
		torches.append(Vector2(WALL_BAND - 3.0, y))
		torches.append(Vector2(size.x - WALL_BAND + 3.0, y))
	cave.torches = torches
	var reserved: Array[Rect2] = [start]
	reserved.append_array(rock_walls)
	for item in CaveDecor.layout(size, WALL_BAND, reserved, DECOR_COUNT):
		var decor := CaveDecor.new()
		decor.kind = item.kind
		decor.variant = item.variant
		decor.position = item.pos
		$World/Decor.add_child(decor)


func _spawn_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var center := Vector2(Arena.world_size) / 2.0
	for i in PROP_COUNT:
		var pos := Vector2(
			rng.randf_range(PROP_MARGIN, Arena.world_size.x - PROP_MARGIN),
			rng.randf_range(PROP_MARGIN, Arena.world_size.y - PROP_MARGIN))
		if pos.distance_to(center) < 60.0:
			continue
		var blocked := false
		for rect in rock_walls:
			if rect.grow(16.0).has_point(pos):
				blocked = true
		if blocked:
			continue
		var prop := StaticBody2D.new()
		prop.set_script(PROP_SCRIPT)
		prop.position = pos
		props_root.add_child(prop)

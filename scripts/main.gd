extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROP_SCRIPT := preload("res://scripts/systems/prop.gd")
const PROP_COUNT := 8  # with the 6 rock walls, the same 14 obstacles the arena always had
const PROP_MARGIN := 48.0
const WALL_BAND := 16.0  # matches the Arena's wall_band in main.tscn
const START_CLEARING := 110.0  # radius around the start that stays free of walls, props and decor
const DECOR_COUNT := 110
const STAGE_CLEARED_TIME := 2.0  # seconds the "Stage cleared" banner stays

## Footprints of the freestanding rock walls (see CaveWall.layout).
var rock_walls: Array[Rect2] = []
## Base positions of the pillars (see _spawn_props).
var prop_positions: Array[Vector2] = []

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
	var end_screen: EndScreen = $UI/EndScreen
	end_screen.run_manager = run_manager
	run_manager.run_ended.connect(_on_run_ended)
	var pause_menu := $UI/PauseMenu
	pause_menu.level_up_menu = $UI/LevelUpMenu
	pause_menu.end_screen = end_screen

	_build_cave()
	_spawn_props()
	_build_obstacles()
	var player: Player = PLAYER_SCENE.instantiate()
	player.character = GameSession.character
	player.position = Vector2(Arena.world_size) / 2.0
	players_root.add_child(player)
	# Level, XP and upgrades carried from the previous stage. Restored before leveled_up is connected.
	if GameSession.run_progress != null:
		RunProgress.restore(player, GameSession.run_progress)
	player.died.connect(run_manager.on_player_died)
	player.xp.leveled_up.connect(func(_level: int) -> void: $UI/LevelUpMenu.queue_level_up(player))
	$UI/Hud.bind(player, run_manager)


## Death shows the end screen. A win waits for the level-up menu to close (so no level is lost and the banner never
## covers it); then the last stage shows victory and any other stage shows "Stage cleared" and loads the next select.
func _on_run_ended(won: bool) -> void:
	if not won:
		$UI/EndScreen.show_result(EndScreen.Mode.DEATH)
		return
	while $UI/LevelUpMenu.active:
		await get_tree().process_frame
	if GameSession.is_last_stage():
		GameSession.finish_run()
		$UI/EndScreen.show_result(EndScreen.Mode.VICTORY)
		return
	get_tree().paused = true
	$UI/StageBanner.show_banner()
	# The tree is paused, so the timer must ignore pause or it would never fire.
	await get_tree().create_timer(STAGE_CLEARED_TIME, true).timeout
	GameSession.complete_stage()


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


## Hands the walls and pillars to the enemies, which cannot walk through them (spec 0.6, 6.6).
## HOOK: built here from the legacy walls and pillars of the default theme. When MapBuilder (build step 6) builds
## the arena it returns the MapLayoutData and calls the same `ObstacleMap.setup()` with its walls and pillars,
## and this function goes away.
func _build_obstacles() -> void:
	var obstacles := ObstacleMap.new()
	var pad := Vector2(Arena.wall_margin, Arena.wall_margin) + Vector2(Enemy.ARENA_PADDING, Enemy.ARENA_PADDING)
	var size := Vector2(Arena.world_size)
	obstacles.setup(rock_walls, prop_positions, size, Rect2(pad, size - pad * 2.0))
	add_child(obstacles)
	spawn_director.obstacles = obstacles


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
		prop_positions.append(pos)

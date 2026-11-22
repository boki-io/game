extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const STAGE_CLEARED_TIME := 2.0  # seconds the "Stage cleared" banner stays
const ITEM_BANNER_TIME := 3.0  # seconds the "Found: ..." banner stays, then it fades for ITEM_BANNER_FADE
const ITEM_BANNER_FADE := 0.5

## Footprints of the freestanding rock walls (the layout's).
var rock_walls: Array[Rect2] = []
## Base positions of the pillars (the layout's).
var prop_positions: Array[Vector2] = []

var _item_banner_id := 0  # which showing of the item banner is current; an older timer does nothing

@onready var players_root: Node2D = $World/Players
@onready var props_root: Node2D = $World/Props
@onready var run_manager: RunManager = $RunManager
@onready var spawn_director: SpawnDirector = $SpawnDirector


func _ready() -> void:
	Audio.stop_music()  # the arena has no music
	spawn_director.run_manager = run_manager
	spawn_director.enemies_root = $World/Enemies
	spawn_director.pickups = $Pickups
	$Pickups.inventory = GameSession.inventory
	$Pickups.item_collected.connect(_on_item_collected)
	# Without a stage (main.tscn run from the editor) every modifier is 0%.
	spawn_director.apply_stage(GameSession.current_stage if GameSession.current_stage else StageData.new())
	spawn_director.coin_bonus = CampAttributes.coin_bonus(GameSession.attribute_levels)
	var debug: Label = $UI/DebugOverlay
	debug.run_manager = run_manager
	debug.spawn_director = spawn_director
	var end_screen: EndScreen = $UI/EndScreen
	end_screen.run_manager = run_manager
	run_manager.run_ended.connect(_on_run_ended)
	var pause_menu := $UI/PauseMenu
	pause_menu.level_up_menu = $UI/LevelUpMenu
	pause_menu.end_screen = end_screen

	_build_map()
	var player: Player = PLAYER_SCENE.instantiate()
	player.character = GameSession.character
	player.attribute_levels = GameSession.attribute_levels
	player.equipment = GameSession.inventory.worn_items(GameSession.character.id)
	player.position = Vector2(Arena.world_size) / 2.0
	players_root.add_child(player)
	# Level, XP and upgrades carried from the previous stage. Restored before leveled_up is connected.
	if GameSession.run_progress != null:
		RunProgress.restore(player, GameSession.run_progress)
	player.died.connect(run_manager.on_player_died)
	player.xp.leveled_up.connect(func(_level: int) -> void: $UI/LevelUpMenu.queue_level_up(player))
	$UI/Hud.bind(player, run_manager)


## An item was taken from the ground: unlock it (saved at once) and announce it. Nothing happens for an item already owned.
func _on_item_collected(item_id: StringName) -> void:
	if not GameSession.inventory.unlock(item_id):
		return
	Audio.play(&"level_up")
	var item := ItemRegistry.find(item_id)
	var banner: Label = $UI/ItemBanner
	banner.text = "Found: %s (%s)" % [item.display_name, ItemData.rating_name(item.rating)]
	banner.add_theme_color_override("font_color", ItemData.rating_color(item.rating))
	banner.modulate.a = 1.0
	banner.visible = true
	_item_banner_id += 1
	var mine := _item_banner_id
	# The tree may be paused (a level-up menu): the timer and the tween must keep running.
	await get_tree().create_timer(ITEM_BANNER_TIME, true).timeout
	if mine != _item_banner_id or not is_instance_valid(banner):
		return
	var tween := banner.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(banner, "modulate:a", 0.0, ITEM_BANNER_FADE)
	await tween.finished
	if mine == _item_banner_id and is_instance_valid(banner):
		banner.visible = false


## Death shows the end screen. A win waits for the level-up menu to close (so no level is lost and the banner never
## covers it); then the last stage shows victory and any other stage shows "Stage cleared" and loads the next select (in a
## cave or dungeon run, the next stage of it).
func _on_run_ended(won: bool) -> void:
	if not won:
		SceneFader.iris_hold(70.0, 0.7)  # the screen closes to a small hole around the body, behind the death screen
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
	SceneFader.flash(Color(1.0, 0.92, 0.6, 0.4), 0.4)
	# The tree is paused, so the timer must ignore pause or it would never fire.
	await get_tree().create_timer(STAGE_CLEARED_TIME, true).timeout
	GameSession.complete_stage()


## Builds the arena of the stage's map (or today's cave with no stage) through MapBuilder, and hands the
## ObstacleMap to the director (spec 0.6, 6.6 and 9).
func _build_map() -> void:
	var theme: MapTheme = GameSession.current_stage.theme if GameSession.current_stage else null
	if theme == null:
		theme = MapRegistry.default()
	var targets := MapBuilder.Targets.new()
	targets.ground = $World/Ground
	targets.cave = $Cave
	targets.props = props_root
	targets.decor = $World/Decor
	targets.ambient_parent = self
	targets.ambience_parent = $World
	targets.vignette = $UI/Vignette
	targets.obstacles_parent = self
	var layout := MapBuilder.build(theme, GameSession.map_seed(), Vector2(Arena.world_size), targets)
	rock_walls = layout.walls
	prop_positions = layout.pillars
	spawn_director.obstacles = targets.obstacles

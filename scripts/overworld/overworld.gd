class_name Overworld
extends Node2D
## The overworld (spec 1.6): a 32,000 x 32,000 px world streamed in chunks around the player, with the 108 markers of the map,
## checkpoints, caves and dungeons (played as arena stages), fog of war, a minimap and the world map. One character's journey
## (GameSession.journey) says where the player stands and what they carry; it is saved at checkpoints, on entering and leaving
## a dungeon, on Return to Hub and Exit, and every SAVE_INTERVAL seconds of play. Hordes roam it (spec 1.8, started by
## `_start_hordes()` when the scene has a HordeDirector); a death respawns the hero at the last lit checkpoint with the journey's
## progress kept, and the gold of the run purse is banked at every save, rest, cave or dungeon entry and respawn.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const LOCKOUT := 0.2
const BANNER_TIME := 2.5
const REVEAL_INTERVAL := 0.25
const DEATH_TIME := 1.2  # seconds the death animation plays before the screen closes
const FADE_TIME := 0.5
## The banner's colour for everything but an item.
const BANNER_COLOR := Color(1, 0.85, 0.4)

var world: WorldData
var journey: Journey
var fog: FogMap
var player: Player
var markers: Array[OverworldMarker] = []
var minimap: Minimap
var world_map: WorldMap
## The marker the player could use now (null when none), found each physics frame.
var target: OverworldMarker
var playtime_since_save := 0.0
## Whether `_start_hordes()` starts the HordeDirector (tests that need a quiet world set it false before add_child).
var hordes_enabled := true

var _lockout := 0.0
var _reveal_timer := 0.0
var _save_timer := 0.0
var _saved_position := Vector2.ZERO
var _banner_id := 0
var _entering := false
var _respawning := false

@onready var terrain: WorldTerrain = $World/Terrain
@onready var props: WorldProps = $World/Props
@onready var markers_root: Node2D = $World/Markers
@onready var players_root: Node2D = $World/Players
@onready var hud: Hud = $UI/Hud
@onready var prompt: Label = $UI/Prompt
@onready var banner: Label = $UI/Banner
@onready var pause_menu: Control = $UI/PauseMenu
@onready var level_up_menu: LevelUpMenu = $UI/LevelUpMenu
@onready var pickups: Pickups = $Pickups
@onready var obstacles: WorldObstacles = $WorldObstacles


func _ready() -> void:
	Audio.music(&"world")
	add_to_group(&"overworld")
	world = WorldData.shared()
	journey = GameSession.journey
	if journey == null:
		journey = JourneySave.load_for(GameSession.character.id, world)
		GameSession.journey = journey
	fog = FogMap.new(journey.fog)
	EnemyGrid.clear()
	$Arena.visible = false  # hides the debug border, keeps the wall bodies
	terrain.setup(world)
	props.setup(world, load("res://content/overworld/nature/mossy_hollow.tres"), terrain)
	obstacles.setup_world(world)
	obstacles.player_source = func() -> Vector2: return player.global_position if is_instance_valid(player) and not player.dead else Vector2.INF
	pickups.inventory = GameSession.inventory
	pickups.walkable = func(pos: Vector2) -> bool: return world.is_walkable(WorldData.tile_of(pos))
	pickups.item_collected.connect(_on_item_collected)
	_build_markers()
	_spawn_player()
	_build_ui()
	pause_menu.level_up_menu = level_up_menu
	pause_menu.return_to_hub_requested.connect(_on_return_to_hub)
	pause_menu.exit_requested.connect(_on_exit)
	_saved_position = player.global_position
	fog.reveal(player.global_position)
	terrain.focus(player.global_position)
	_lockout = LOCKOUT
	_start_hordes()


## Starts the hordes (spec 1.8): the scene's HordeDirector node, when it has one and `hordes_enabled` is set, is given the
## world, the horde plan and the nodes it fills. Does nothing without the node.
func _start_hordes() -> void:
	if not hordes_enabled or not has_node("HordeDirector"):
		return
	var director := $HordeDirector
	var rules: HordeRules = load("res://content/overworld/hordes.tres")
	director.setup(world, HordePlan.build(world, HordeSites.shared(), rules), rules, obstacles, $World/Enemies, pickups, journey)
	director.den_cleared.connect(_on_den_cleared)
	director.prewarm(8)


## A den's last member died: a banner, and a burst of coins around the marker (`HordeRules.den_bonus_coins`).
func _on_den_cleared(kind: String, marker: int) -> void:
	show_banner("%s cleared" % kind.capitalize())
	var rules: HordeRules = load("res://content/overworld/hordes.tres")
	var centre := WorldData.marker_world(world.markers[marker])
	for i in rules.den_bonus_coins:
		pickups.spawn_coin(centre + Vector2.from_angle(randf() * TAU) * randf_range(8.0, 44.0))


func _build_markers() -> void:
	for i in world.markers.size():
		var m := OverworldMarker.new()
		m.setup(world.markers[i], i, world)
		m.lit = m.data.name in journey.checkpoints and m.kind in [&"checkpoint", &"start_camp"]
		m.cleared = m.kind in [&"cave", &"dungeon", &"final_dungeon"] and journey.is_cleared(m.data.name)
		markers_root.add_child(m)
		if m.kind == &"gate" and not journey.gate_open(m.data.name):
			m.set_locked(true)
		markers.append(m)


## The Player as the hub makes it (hub_mode false: mana is limited and relics work), at the journey's position, with the
## carried progress restored before anything connects to leveled_up.
func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.character = GameSession.character
	player.hub_mode = false
	player.attribute_levels = GameSession.attribute_levels
	player.equipment = GameSession.inventory.worn_items(GameSession.character.id)
	player.position = journey.position
	players_root.add_child(player)
	RunProgress.restore(player, journey.progress)
	player.died.connect(_on_player_died)
	player.xp.leveled_up.connect(func(_level: int) -> void: level_up_menu.queue_level_up(player))
	hud.bind(player)


func _build_ui() -> void:
	minimap = Minimap.new()
	minimap.name = "Minimap"
	$UI.add_child(minimap)
	minimap.bind(world, fog, player)
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	$UI.add_child(world_map)
	world_map.bind(world, fog, player)
	world_map.lit_checkpoints = journey.checkpoints
	# The map pauses the tree, which stops _update_markers: hide the prompt when it opens.
	world_map.visibility_changed.connect(func() -> void: prompt.visible = prompt.visible and not world_map.visible)
	prompt.visible = false
	banner.visible = false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_lockout = maxf(_lockout - delta, 0.0)
	terrain.focus(player.global_position)
	_update_markers()
	_reveal_timer += delta
	if _reveal_timer >= REVEAL_INTERVAL:
		_reveal_timer = 0.0
		if fog.reveal(player.global_position):
			world_map.queue_redraw()
	journey.playtime += delta
	_save_timer += delta
	if _save_timer >= OverworldRules.SAVE_INTERVAL:
		_save_timer = 0.0
		if player.global_position.distance_to(_saved_position) >= OverworldRules.SAVE_MIN_MOVE:
			save_now()


## Names near the player, far markers hidden, the nearest usable marker and the prompt.
func _update_markers() -> void:
	var pos := player.global_position
	var best: OverworldMarker = null
	var best_dist := OverworldRules.INTERACT_RADIUS
	for m in markers:
		var d := pos.distance_to(m.position)
		m.visible = d < OverworldRules.REDRAW_RADIUS + 200.0
		m.set_show_name(d < OverworldRules.NAME_RADIUS)
		if m.is_interactive() and d < best_dist:
			best_dist = d
			best = m
	target = best
	var text := "" if best == null or world_map.is_open else best.prompt_text()
	prompt.visible = text != ""
	prompt.text = text


func _unhandled_input(event: InputEvent) -> void:
	if SceneFader.busy or _entering or not event.is_action_pressed(&"interact"):
		return
	if _lockout > 0.0 or target == null or get_tree().paused:
		return
	_interact(target)
	get_viewport().set_input_as_handled()


## Uses a marker: lights a checkpoint, enters a cave or dungeon, examines a special.
func _interact(m: OverworldMarker) -> void:
	_lockout = LOCKOUT
	match m.kind:
		&"start_camp", &"checkpoint":
			_rest(m)
		&"cave", &"dungeon", &"final_dungeon":
			_enter(m)
		&"special":
			show_banner("%s (%s)" % [m.data.name, m.data.get("subtype", "")])


func _rest(m: OverworldMarker) -> void:
	var first := journey.activate_checkpoint(m.data.name)
	GameSession.bank_run()
	m.set_lit(true)
	world_map.lit_checkpoints = journey.checkpoints
	player.health.heal(player.health.max_health)
	save_now()
	show_banner("Checkpoint reached" if first else "Rested")
	Audio.play(&"stage_clear")
	SceneFader.flash(Color(1.0, 0.92, 0.6, 0.3), 0.3)


func _enter(m: OverworldMarker) -> void:
	_entering = true
	GameSession.bank_run()  # enter_dungeon zeroes the purse
	_sync_journey()
	Audio.play(&"door_enter")
	GameSession.enter_dungeon(m.data)


## Copies what the scene knows into the journey (position, fog, progress; the checkpoints list is shared).
func _sync_journey() -> void:
	journey.position = player.global_position if is_instance_valid(player) else journey.position
	journey.fog = fog.bytes()
	if is_instance_valid(player):
		journey.progress = RunProgress.capture(player, false)  # levels gained here are saved (granted relics left out)


func save_now() -> void:
	GameSession.bank_run()
	_sync_journey()
	_saved_position = journey.position
	GameSession.save_journey()


func show_banner(text: String, color := BANNER_COLOR) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.modulate.a = 1.0
	banner.visible = true
	_banner_id += 1
	var mine := _banner_id
	# The tree may be paused: the timer and the tween must keep running.
	await get_tree().create_timer(BANNER_TIME, true).timeout
	if mine != _banner_id or not is_instance_valid(banner):
		return
	var tween := banner.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(banner, "modulate:a", 0.0, 0.5)
	await tween.finished
	if mine == _banner_id and is_instance_valid(banner):
		banner.visible = false


## An item was taken from the ground: unlock it (saved at once) and announce it with its rating's colour.
func _on_item_collected(item_id: StringName) -> void:
	if not GameSession.inventory.unlock(item_id):
		return
	Audio.play(&"level_up")
	var item := ItemRegistry.find(item_id)
	show_banner("Found: %s (%s)" % [item.display_name, ItemData.rating_name(item.rating)], ItemData.rating_color(item.rating))


## Death: the hero lies there a moment, the screen closes, and they stand up at the last lit checkpoint with level, XP and
## upgrades kept (the journey's progress is not touched), full health, the purse banked and the hordes reset.
func _on_player_died() -> void:
	if _respawning or _entering:
		return
	_respawning = true
	await get_tree().create_timer(DEATH_TIME, true).timeout
	if not is_instance_valid(player):
		return
	level_up_menu.dismiss()
	get_tree().paused = false
	SceneFader.iris_hold(0.0, FADE_TIME)
	await get_tree().create_timer(FADE_TIME, true).timeout
	if not is_instance_valid(player):
		return
	if has_node("HordeDirector"):
		$HordeDirector.reset()
	var spot := WorldData.marker_world(world.marker_named(journey.respawn))
	player.revive(spot)
	var cam := get_tree().get_first_node_in_group(&"camera") as CameraFollow
	if cam:
		cam.snap()
	terrain.focus(spot)
	fog.reveal(spot)
	GameSession.bank_run()
	save_now()
	SceneFader.iris_release()
	SceneFader.flash(Color(0, 0, 0, 1), FADE_TIME)
	_respawning = false


func _on_return_to_hub() -> void:
	save_now()
	get_tree().paused = false
	GameSession.go_to_hub()


func _on_exit() -> void:
	save_now()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(player):
		save_now()

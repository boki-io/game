class_name Overworld
extends Node2D
## The overworld (spec 1.6): a 32,000 x 32,000 px world streamed in chunks around the player, with the 108 markers of the map,
## checkpoints, caves and dungeons (played as arena stages), fog of war, a minimap and the world map. One character's journey
## (GameSession.journey) says where the player stands and what they carry; it is saved at checkpoints, on entering and leaving
## a dungeon, on Return to Hub and Exit, and every SAVE_INTERVAL seconds of play. There are no enemies here yet.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const LOCKOUT := 0.2
const BANNER_TIME := 2.5
const REVEAL_INTERVAL := 0.25

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

var _lockout := 0.0
var _reveal_timer := 0.0
var _save_timer := 0.0
var _saved_position := Vector2.ZERO
var _banner_id := 0
var _entering := false

@onready var terrain: WorldTerrain = $World/Terrain
@onready var props: WorldProps = $World/Props
@onready var markers_root: Node2D = $World/Markers
@onready var players_root: Node2D = $World/Players
@onready var hud: Hud = $UI/Hud
@onready var prompt: Label = $UI/Prompt
@onready var banner: Label = $UI/Banner
@onready var pause_menu: Control = $UI/PauseMenu


func _ready() -> void:
	add_to_group(&"overworld")
	world = WorldData.shared()
	journey = GameSession.journey
	if journey == null:
		journey = JourneySave.load_for(GameSession.character.id, world)
		GameSession.journey = journey
	fog = FogMap.new(journey.fog)
	$Arena.visible = false  # hides the debug border, keeps the wall bodies
	terrain.setup(world)
	props.setup(world, load("res://content/overworld/nature/mossy_hollow.tres"), terrain)
	_build_markers()
	_spawn_player()
	_build_ui()
	pause_menu.return_to_hub_requested.connect(_on_return_to_hub)
	pause_menu.exit_requested.connect(_on_exit)
	_saved_position = player.global_position
	fog.reveal(player.global_position)
	terrain.focus(player.global_position)
	_lockout = LOCKOUT


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
	m.set_lit(true)
	world_map.lit_checkpoints = journey.checkpoints
	player.health.heal(player.health.max_health)
	save_now()
	show_banner("Checkpoint reached" if first else "Rested")
	Audio.play(&"stage_clear")
	SceneFader.flash(Color(1.0, 0.92, 0.6, 0.3), 0.3)


func _enter(m: OverworldMarker) -> void:
	_entering = true
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
	_sync_journey()
	_saved_position = journey.position
	GameSession.save_journey()


func show_banner(text: String) -> void:
	banner.text = text
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

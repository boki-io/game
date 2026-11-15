extends Node2D
## The hub: a room with a pedestal per character. Browse mode is a camera and a cursor; choosing a character
## switches to walk mode, where you are that character (infinite mana, no damage) and can walk through the
## door in the north wall to start a run. Standing at a pedestal and pressing interact goes back to browsing.

enum Mode { BROWSE, WALK }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DUMMY_DATA := preload("res://data/enemies/training_dummy.tres")
const DUMMY_POSITIONS: Array[Vector2] = [Vector2(150, 140), Vector2(150, 200), Vector2(210, 170)]
const PEDESTAL_Y := 380.0
const PEDESTAL_SPACING := 140.0
const CENTER_X := 480.0
## Browse camera: the focused pedestal sits left of center so the info panel has room on the right.
const BROWSE_OFFSET := Vector2(90, 0)
const BROWSE_LIFT := 40.0
const MODE_LOCKOUT := 0.2  # confirm and interact are ignored this long after a mode change
const INTERACT_RADIUS := 60.0  # less than half the pedestal spacing, so at most one pedestal qualifies
const SPAWN_BELOW_PEDESTAL := 30.0
const SPAWN_BELOW_DOOR := 40.0  # below the door trigger, when returning from a run
const CAMERA_BLEND := 0.3
const BROWSE_HINT := "< >  Browse      Enter  Choose      Esc  Menu"
const WALK_HINT := "WASD  Move      Mouse  Aim      Q E R  Abilities      I  Info      Esc  Menu"

var mode := Mode.BROWSE
var characters: Array[CharacterData] = []
var pedestals: Array[HubPedestal] = []
var focus_index := 0  # browse: the focused pedestal. walk: the character being played
var player: Player

var _lockout := 0.0
var _entering_run := false

@onready var pedestals_root: Node2D = $World/Pedestals
@onready var players_root: Node2D = $World/Players
@onready var camera: CameraFollow = $Camera
@onready var door: HubDoor = $Door
@onready var panel: HubInfoPanel = $UI/InfoPanel
@onready var hint: Label = $UI/HintBar
@onready var prompt: Label = $UI/Prompt
@onready var hud: Hud = $UI/Hud


func _ready() -> void:
	EnemyGrid.clear()
	characters = CharacterRegistry.all()
	_build_pedestals()
	_build_dummies()
	panel.choose_pressed.connect(_confirm)
	door.player_entered.connect(_enter_run)
	door.set_open(false)
	# Coming back from a run: walk mode as the character just played, below the door.
	var last := GameSession.last_character
	if last:
		for i in characters.size():
			if characters[i].id == last.id:
				_enter_walk(i, Vector2(door.position.x, SPAWN_BELOW_DOOR + HubDoor.SIZE.y), true)
				return
	_enter_browse(0, true)


func _process(delta: float) -> void:
	_lockout = maxf(_lockout - delta, 0.0)
	prompt.visible = mode == Mode.WALK and is_instance_valid(player) and _pedestal_near_player() != null


func _unhandled_input(event: InputEvent) -> void:
	if SceneFader.busy:
		return
	if mode == Mode.BROWSE:
		if event.is_action_pressed(&"hub_left"):
			_focus(posmod(focus_index - 1, characters.size()))
		elif event.is_action_pressed(&"hub_right"):
			_focus(posmod(focus_index + 1, characters.size()))
		elif event.is_action_pressed(&"hub_confirm"):
			_confirm()
		else:
			return
	else:
		if event.is_action_pressed(&"interact"):
			if _lockout <= 0.0 and _pedestal_near_player() != null:
				_enter_browse(focus_index, false)
		elif event.is_action_pressed(&"hub_info"):
			panel.visible = not panel.visible
		else:
			return
	get_viewport().set_input_as_handled()


func _build_pedestals() -> void:
	var first_x := CENTER_X - PEDESTAL_SPACING * (characters.size() - 1) / 2.0
	for i in characters.size():
		var p := HubPedestal.new()
		p.position = Vector2(first_x + PEDESTAL_SPACING * i, PEDESTAL_Y)
		pedestals_root.add_child(p)
		p.setup(characters[i])
		p.clicked.connect(_on_pedestal_clicked)
		pedestals.append(p)


## Three indestructible training dummies north-west of the room. Their data is set before they enter the tree
## and they are activated right away (an inactive enemy ignores damage).
func _build_dummies() -> void:
	for pos in DUMMY_POSITIONS:
		var dummy: Enemy = ENEMY_SCENE.instantiate()
		dummy.data = DUMMY_DATA
		$World/Dummies.add_child(dummy)
		dummy.activate(pos, 1.0)
		var readout := DummyReadout.new()
		readout.position = Vector2(0, -DUMMY_DATA.body_size.y - 18.0)
		readout.track(dummy.health)
		dummy.add_child(readout)


func _on_pedestal_clicked(pedestal: HubPedestal) -> void:
	if SceneFader.busy or mode != Mode.BROWSE:
		return
	_focus(pedestals.find(pedestal))


func _focus(index: int, instant: bool = false) -> void:
	var changed := index != focus_index
	focus_index = index
	for i in pedestals.size():
		pedestals[i].focused = i == index
	panel.show_character(characters[index])
	camera.browse_to(pedestals[index].position - Vector2(0, BROWSE_LIFT), instant)
	if changed:
		Audio.play(&"hub_focus")


## Browse mode with `index` focused. Removes the Player (if any) and everything it left pending.
func _enter_browse(index: int, instant: bool) -> void:
	_remove_player()
	mode = Mode.BROWSE
	_lockout = MODE_LOCKOUT
	for p in pedestals:
		p.set_figure_visible(true)
	door.set_open(false)
	camera.set_base_offset(BROWSE_OFFSET, 0.0 if instant else 0.25)
	panel.visible = true
	_place_hint(BROWSE_HINT, false)
	focus_index = -1  # so _focus reports a change only when the player moves it
	_focus(index, instant)
	focus_index = index


func _place_hint(text: String, at_top: bool) -> void:
	hint.text = text
	hint.anchor_top = 0.0 if at_top else 1.0
	hint.anchor_bottom = hint.anchor_top
	hint.offset_top = 4.0 if at_top else -16.0
	hint.offset_bottom = hint.offset_top + 12.0


func _confirm() -> void:
	if _lockout > 0.0 or SceneFader.busy or mode != Mode.BROWSE:
		return
	Audio.play(&"hub_choose")
	var pedestal := pedestals[focus_index]
	var fx := Effects.get_for(self)
	if fx:
		fx.ring(pedestal.position, 30.0)
		fx.puff(pedestal.position + Vector2(0, -12), Color("ffd866"))
	_enter_walk(focus_index, pedestal.position + Vector2(0, SPAWN_BELOW_PEDESTAL), false)
	Audio.play(&"door_open")


## Walk mode as characters[index], standing at `pos`.
func _enter_walk(index: int, pos: Vector2, instant: bool) -> void:
	_remove_player()
	mode = Mode.WALK
	_lockout = MODE_LOCKOUT
	focus_index = index
	for i in pedestals.size():
		pedestals[i].focused = false
		pedestals[i].set_figure_visible(i != index)
	player = PLAYER_SCENE.instantiate()
	player.character = characters[index]
	player.hub_mode = true
	player.position = pos
	players_root.add_child(player)
	hud.bind(player)
	panel.visible = false
	_place_hint(WALK_HINT, true)  # the ability icons sit at the bottom in walk mode
	camera.set_base_offset(Vector2.ZERO, 0.0 if instant else CAMERA_BLEND)
	if instant:
		camera.browse_to(pos - Vector2(0, 12), true)
	door.set_open(true)


## Removes the Player immediately (not queue_free, so a same-frame spawn can never leave two) and clears
## anything it left pending: meteors, damage fields, bolts in flight and effects.
func _remove_player() -> void:
	if is_instance_valid(player):
		PlayerRegistry.unregister(player)
		players_root.remove_child(player)
		player.free()
	player = null
	for node in [$World/Effects, $World/Zones, $World/PlayerProjectiles]:
		node.clear()


func _pedestal_near_player() -> HubPedestal:
	for p in pedestals:
		if p.position.distance_to(player.global_position) < INTERACT_RADIUS:
			return p
	return null


func _enter_run() -> void:
	if _entering_run or mode != Mode.WALK or SceneFader.busy:
		return
	_entering_run = true
	Audio.play(&"door_enter")
	GameSession.start_run(characters[focus_index])


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(CENTER_X - 100.0, 290.0)
	draw_string(font, pos + Vector2(1, 1), "HERO HORDE", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(90, 100), "TRAINING", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 8, Color(1, 1, 1, 0.4))
	draw_string(font, pos, "HERO HORDE", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color("ffd866"))

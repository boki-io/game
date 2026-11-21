extends Node2D
## The hub: a room with a pedestal per character. Browse mode is a camera and a cursor; choosing a character
## switches to walk mode, where you are that character (infinite mana, no damage) and can walk through the
## door in the north wall to start a run. Standing at a pedestal and pressing interact goes back to browsing.

enum Mode { BROWSE, WALK }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DUMMY_DATA := preload("res://content/enemies/training_dummy.tres")
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
const WALL_BAND := 16.0  # the rock band; matches the Arena's wall_band in hub.tscn
const SIGN_POS := Vector2(480, 290)
const TRAINING_AREA := Rect2(110, 100, 140, 120)
const CAMP_POS := Vector2(170, 300)  # below the training dummies
const CAMP_RADIUS := 48.0  # interact within this of CAMP_POS to open the camp
const CHEST_POS := Vector2(570, 64)  # right of the door, on the floor below the wall band (the chest's base)
const CHEST_RADIUS := 40.0  # interact within this of CHEST_POS to open the inventory
const BROWSE_HINT := "< >  Browse      Enter  Choose      Esc  Menu"
const WALK_HINT := "WASD  Move      Mouse  Aim      Q E R  Abilities      I  Info      Esc  Menu"

var mode := Mode.BROWSE
var characters: Array[CharacterData] = []
var pedestals: Array[HubPedestal] = []
var focus_index := 0  # browse: the focused pedestal. walk: the character being played
var player: Player

## The camp screen (a Control with `open()`, spec 0.7 7), built by `_build_camp_screen()`.
var camp_screen: Control
var camp_site: CampSite
var chest: HubChest
## The inventory screen (a Control with `open(character)` and a `closed(changed)` signal), built by `_build_inventory_screen()`.
var inventory_screen: Control
var gold_counter: GoldCounter
var reward_banner: Label

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
	_build_camp()
	_build_chest()
	_build_cave()
	MapLook.apply_ambience($World, MapRegistry.default(), 0)  # the hub builds no theme: the default cave's dust
	panel.choose_pressed.connect(_confirm)
	door.player_entered.connect(_enter_run)
	door.set_open(false)
	_build_camp_screen()
	_build_inventory_screen()
	_show_reward(GameSession.take_reward())  # before the early return below
	# Coming back from a run: walk mode as the character just played, below the door.
	var last := GameSession.last_character
	if last:
		for i in characters.size():
			if characters[i].id == last.id:
				_enter_walk(i, Vector2(door.position.x, WALL_BAND + SPAWN_BELOW_DOOR + HubDoor.SIZE.y), true)
				return
	_enter_browse(0, true)


func _process(delta: float) -> void:
	_lockout = maxf(_lockout - delta, 0.0)
	var target := _interact_target()
	prompt.visible = target != &""
	if target == &"camp":
		prompt.text = "F: Camp"
	elif target == &"chest":
		prompt.text = "F: Inventory"
	elif target == &"pedestal":
		prompt.text = "F: Change character"


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
			if _lockout > 0.0:
				pass
			elif _interact_target() == &"pedestal":
				_enter_browse(focus_index, false)
			elif _interact_target() == &"camp":
				_open_camp()
			elif _interact_target() == &"chest":
				_open_inventory()
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


func _build_camp() -> void:
	camp_site = CampSite.new()
	camp_site.position = CAMP_POS
	camp_site.z_index = -1  # under the Player wherever it stands
	$World.add_child(camp_site)


func _build_chest() -> void:
	chest = HubChest.new()
	chest.position = CHEST_POS
	$World.add_child(chest)  # World Y-sorts, so the player passes in front of or behind it by its base


## What interact would act on now: &"pedestal", &"camp", &"chest" or &"" (nothing, and always nothing in browse mode).
func _interact_target() -> StringName:
	if mode != Mode.WALK or not is_instance_valid(player):
		return &""
	if _pedestal_near_player() != null:
		return &"pedestal"
	if CAMP_POS.distance_to(player.global_position) < CAMP_RADIUS:
		return &"camp"
	if CHEST_POS.distance_to(player.global_position) < CHEST_RADIUS:
		return &"chest"
	return &""


## Opens the camp screen, if one has been assigned.
func _open_camp() -> void:
	if camp_screen != null:
		camp_screen.open()


## Opens the inventory of the character being played, with the sound and the ring and puff a pedestal choice has.
func _open_inventory() -> void:
	if inventory_screen == null:
		return
	Audio.play(&"door_open")
	var fx := Effects.get_for(self)
	if fx:
		fx.ring(CHEST_POS, 24.0)
		fx.puff(CHEST_POS + Vector2(0, -16), Color("ffd866"))
	inventory_screen.open(characters[focus_index])


func _on_inventory_closed(changed: bool) -> void:
	_lockout = MODE_LOCKOUT
	if changed:
		_rebuild_player()


## Torches on the walls and the decor, which keeps clear of everything gameplay uses.
func _build_cave() -> void:
	var size := Vector2(Arena.world_size)
	var cave: CaveWalls = $Cave
	var b := WALL_BAND
	cave.wall_band = b
	cave.torches = [Vector2(door.position.x - 44.0, 9.0), Vector2(door.position.x + 44.0, 9.0),
		Vector2(150.0, size.y - b + 1.0), Vector2(size.x - 150.0, size.y - b + 1.0), Vector2(b - 3.0, 170.0)]
	for item in CaveDecor.layout(size, b, reserved_areas()):
		var decor := CaveDecor.new()
		decor.kind = item.kind
		decor.variant = item.variant
		decor.position = item.pos
		$World/Decor.add_child(decor)


## Floor the decor must stay off: the pedestals, the training area, the lane from the door, the sign, the camp and the chest.
func reserved_areas() -> Array[Rect2]:
	var out: Array[Rect2] = [TRAINING_AREA, Rect2(SIGN_POS.x - 70.0, SIGN_POS.y - 30.0, 140.0, 50.0),
		Rect2(door.position.x - 24.0, 0.0, 48.0, 110.0),
		Rect2(CAMP_POS.x - 50.0, CAMP_POS.y - 45.0, 100.0, 80.0),
		Rect2(CHEST_POS.x - 24.0, CHEST_POS.y - 40.0, 48.0, 56.0)]
	for p in pedestals:
		out.append(Rect2(p.position + Vector2(-34, -60), Vector2(68, 90)))
	return out


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
	_spawn_player(index, pos)
	panel.visible = false
	_place_hint(WALK_HINT, true)  # the ability icons sit at the bottom in walk mode
	camera.set_base_offset(Vector2.ZERO, 0.0 if instant else CAMERA_BLEND)
	if instant:
		camera.browse_to(pos - Vector2(0, 12), true)
	door.set_open(true)


## Creates the hub Player as characters[index] at `pos` and binds the HUD to it.
func _spawn_player(index: int, pos: Vector2) -> void:
	player = PLAYER_SCENE.instantiate()
	player.character = characters[index]
	player.hub_mode = true
	player.attribute_levels = GameSession.attribute_levels
	player.equipment = GameSession.inventory.worn_items(characters[index].id)
	player.position = pos
	players_root.add_child(player)
	hud.bind(player)


## Top-right gold counter, and after a run a "+N gold" banner while the counter counts up from the old total
## (spec 0.7, 7.4). `reward` is what the run just banked (GameSession.take_reward()).
func _show_reward(reward: int) -> void:
	gold_counter = GoldCounter.new()
	gold_counter.name = "GoldCounter"
	gold_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gold_counter.offset_left = -76.0
	gold_counter.offset_top = 6.0
	gold_counter.offset_right = -8.0
	gold_counter.offset_bottom = 18.0
	$UI.add_child(gold_counter)
	gold_counter.set_amount(GameSession.gold - reward)
	if reward <= 0:
		return
	reward_banner = UiKit.label("+%d gold" % reward, 12, Color("ffd866"))
	reward_banner.name = "RewardBanner"
	reward_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	reward_banner.offset_top = 30.0
	$UI.add_child(reward_banner)
	gold_counter.count_to(GameSession.gold, 1.2)
	var tween := create_tween()
	tween.tween_property(reward_banner, "modulate:a", 0.0, 0.5).set_delay(2.0)
	tween.tween_callback(reward_banner.queue_free)


## Camp screen block (spec 0.7, 6.4, 7): the screen lives in the UI layer; closing it after a change rebuilds the Player
## in place, because attributes are applied once, at Player creation.
func _build_camp_screen() -> void:
	var screen := CampScreen.new()
	screen.name = "CampScreen"
	$UI.add_child(screen)
	screen.closed.connect(_on_camp_closed)
	camp_screen = screen


## The inventory screen (spec 1.4) lives in the UI layer; closing it after a change rebuilds the Player, as the camp does.
func _build_inventory_screen() -> void:
	var screen := InventoryScreen.new()
	screen.name = "InventoryScreen"
	$UI.add_child(screen)
	screen.closed.connect(_on_inventory_closed)
	inventory_screen = screen


func _on_camp_closed(changed: bool) -> void:
	_lockout = MODE_LOCKOUT
	if changed:
		_rebuild_player()


## A fresh Player at the old one's position (same creation path as _enter_walk; cooldowns and effects reset).
func _rebuild_player() -> void:
	if mode != Mode.WALK or not is_instance_valid(player):
		return
	var pos := player.position
	_remove_player()
	_spawn_player(focus_index, pos)


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


## The title on a wooden post sign.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(SIGN_POS + Vector2(-3, -8), Vector2(6, 28)), Color("4a3320"))
	draw_rect(Rect2(SIGN_POS + Vector2(-62, -32), Vector2(124, 26)), Color("6b4a2b"))
	draw_rect(Rect2(SIGN_POS + Vector2(-62, -32), Vector2(124, 26)), Color("3a2716"), false, 2.0)
	draw_string(font, SIGN_POS + Vector2(-100, -13) + Vector2(1, 1), "HERO HORDE", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color(0, 0, 0, 0.6))
	draw_string(font, SIGN_POS + Vector2(-100, -13), "HERO HORDE", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color("ffd866"))
	draw_string(font, Vector2(90, 100), "TRAINING", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 8, Color(1, 1, 1, 0.4))

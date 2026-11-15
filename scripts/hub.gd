extends Node2D
## The hub: a room with a pedestal per character. Browse mode is a camera and a cursor; walk mode (as the
## chosen character, with a door to the run) comes in the next milestone.

enum Mode { BROWSE, WALK }

const PEDESTAL_Y := 380.0
const PEDESTAL_SPACING := 140.0
const CENTER_X := 480.0
## Browse camera: the focused pedestal sits left of center so the info panel has room on the right.
const BROWSE_OFFSET := Vector2(90, 0)
const BROWSE_LIFT := 40.0
const MODE_LOCKOUT := 0.2  # confirm and interact are ignored this long after a mode change

var mode := Mode.BROWSE
var characters: Array[CharacterData] = []
var pedestals: Array[HubPedestal] = []
var focus_index := 0

var _lockout := 0.0
var _confirmed := false

@onready var pedestals_root: Node2D = $World/Pedestals
@onready var camera: CameraFollow = $Camera
@onready var door: HubDoor = $Door
@onready var panel: HubInfoPanel = $UI/InfoPanel
@onready var hint: Label = $UI/HintBar


func _ready() -> void:
	EnemyGrid.clear()
	characters = CharacterRegistry.all()
	_build_pedestals()
	camera.base_offset = BROWSE_OFFSET
	panel.choose_pressed.connect(_confirm)
	door.set_open(false)
	# Coming back from a run lands on the character just played (walk mode replaces this later).
	var last := GameSession.last_character
	var start := 0
	if last:
		for i in characters.size():
			if characters[i].id == last.id:
				start = i
	_focus(start, true)


func _process(delta: float) -> void:
	_lockout = maxf(_lockout - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if SceneFader.busy or mode != Mode.BROWSE:
		return
	if event.is_action_pressed(&"hub_left"):
		_focus(posmod(focus_index - 1, characters.size()))
	elif event.is_action_pressed(&"hub_right"):
		_focus(posmod(focus_index + 1, characters.size()))
	elif event.is_action_pressed(&"hub_confirm"):
		_confirm()
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


func _confirm() -> void:
	if _lockout > 0.0 or _confirmed or SceneFader.busy or mode != Mode.BROWSE:
		return
	_confirmed = true
	Audio.play(&"hub_choose")
	# TEMPORARY until walk mode lands: choosing starts a run straight away.
	GameSession.start_run(characters[focus_index])


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(CENTER_X - 100.0, 290.0)
	draw_string(font, pos + Vector2(1, 1), "HERO HORDE", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color(0, 0, 0, 0.8))
	draw_string(font, pos, "HERO HORDE", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color("ffd866"))

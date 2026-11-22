extends Node2D
## The stage select screen: the path's three columns as cards with connection lines. Pick one of the stages the
## path allows (arrows / W S / D-pad or the mouse), Enter or a click starts it. Esc asks to abandon the run.

const COLUMN_X := [20.0, 240.0, 460.0]
const TOP_Y := 60.0
const ROW_STEP := 90.0
const WALL_BAND := 16.0
const HINT := "W S  Choose      Enter  Start      Esc  Abandon run"

var cards: Array = []  # cards[column][row]
## Cursor: index into the available cards.
var focus_index := 0

var _available: Array[StageCard] = []
var _prompt: AbandonPrompt
var _lines: Lines
var _starting := false

@onready var ui: CanvasLayer = $UI


func _ready() -> void:
	Audio.music(&"menu")
	if GameSession.path == null:
		# The scene opened directly from the editor: make a run so there is something to show.
		GameSession.new_run(GameSession.character, randi())
	_build_cave()
	_build_ui()
	refresh()


func _build_cave() -> void:
	var size := Vector2(Arena.world_size)
	var cave: CaveWalls = $Cave
	cave.wall_band = WALL_BAND
	var torches: Array[Vector2] = []
	for x in [90.0, 320.0, 550.0]:
		torches.append(Vector2(x, 9.0))
		torches.append(Vector2(x, size.y - WALL_BAND + 1.0))
	cave.torches = torches


func _build_ui() -> void:
	var path := GameSession.path
	_lines = Lines.new()
	_lines.screen = self
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_lines)
	for column in path.column_count():
		var column_cards: Array = []
		var count: int = path.columns[column].size()
		for row in count:
			var card := StageCard.new()
			card.setup(path.stage_at(column, row), column, row)
			var y := TOP_Y + ROW_STEP * (row + (1.0 if count == 1 else 0.0))
			card.position = Vector2(COLUMN_X[column], y)
			card.hovered.connect(_on_card_hovered)
			card.chosen.connect(_on_card_chosen)
			ui.add_child(card)
			column_cards.append(card)
		cards.append(column_cards)
	var title := UiKit.label("Choose your path", 12, Color("ffd866"))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -100.0
	title.offset_right = 100.0
	title.offset_top = 22.0
	title.name = "Title"
	ui.add_child(title)
	var hint := UiKit.label(HINT, 8, Color(1, 1, 1, 0.7))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -200.0
	hint.offset_right = 200.0
	hint.offset_top = -30.0
	hint.name = "Hint"
	ui.add_child(hint)
	_prompt = AbandonPrompt.new()
	_prompt.name = "AbandonPrompt"
	ui.add_child(_prompt)


## Card states, the cursor and the lines for the session's current column.
func refresh() -> void:
	var column := GameSession.current_column
	var rows := GameSession.available_rows()
	_available.clear()
	for c in cards.size():
		for r in cards[c].size():
			var card: StageCard = cards[c][r]
			card.focused = false
			if c < column:
				card.state = StageCard.State.BEATEN if GameSession.beaten[c] == r else StageCard.State.LOCKED
			elif c == column and rows.has(r):
				card.state = StageCard.State.AVAILABLE
				_available.append(card)
			else:
				card.state = StageCard.State.LOCKED
	focus_index = 0
	_set_focus(0, false)
	_lines.queue_redraw()


func _set_focus(index: int, sound: bool) -> void:
	if _available.is_empty():
		return
	var changed := index != focus_index
	focus_index = posmod(index, _available.size())
	for i in _available.size():
		_available[i].focused = i == focus_index
	if sound and changed:
		Audio.play(&"hub_focus")


func focused_card() -> StageCard:
	return _available[focus_index] if not _available.is_empty() else null


func _on_card_hovered(card: StageCard) -> void:
	if SceneFader.busy or _prompt.visible:
		return
	_set_focus(_available.find(card), true)


func _on_card_chosen(card: StageCard) -> void:
	if SceneFader.busy or _prompt.visible or card.state != StageCard.State.AVAILABLE:
		return
	_start(card)


func _start(card: StageCard) -> void:
	if _starting:
		return
	_starting = true
	Audio.play(&"hub_choose")
	GameSession.select_stage(card.stage)


func _unhandled_input(event: InputEvent) -> void:
	if SceneFader.busy or _prompt.visible:
		return
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
		_set_focus(focus_index - 1, true)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
		_set_focus(focus_index + 1, true)
	elif event.is_action_pressed(&"hub_confirm"):
		if focused_card():
			_start(focused_card())
	elif event.is_action_pressed(&"pause"):
		_prompt.open()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_lines.queue_redraw()


## Called by Lines: a line from every stage to the stages it connects to. Highlighted from the beaten stage to
## the stages now available; muted otherwise.
func draw_connections(canvas: Control) -> void:
	var path := GameSession.path
	if path == null:
		return
	for c in path.column_count() - 1:
		for r in cards[c].size():
			var from: Vector2 = cards[c][r].right_middle()
			for target in path.next_rows(c, r):
				var to: Vector2 = cards[c + 1][target].left_middle()
				var live: bool = c == GameSession.current_column - 1 and not GameSession.beaten.is_empty() \
					and GameSession.beaten[c] == r
				canvas.draw_line(from, to, Color("ffd866") if live else Color(0.75, 0.68, 0.55, 0.28), 2.0 if live else 1.0)


class Lines extends Control:
	var screen: Node2D

	func _draw() -> void:
		screen.draw_connections(self)

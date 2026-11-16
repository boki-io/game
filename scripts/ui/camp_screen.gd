class_name CampScreen
extends Control
## The camp menu (spec 0.7, section 7): eight attribute rows with buy and undo, Reset all and Close. Pauses the tree
## while open. Rows are not focus targets; only Reset all and Close are. `closed(changed)` says whether any level
## differs from when it opened, so the hub knows to rebuild its Player.

signal closed(changed: bool)

const PIP_SIZE := Vector2(6, 6)
const PIP_GAP := 2.0
const DIM_ALPHA := 0.4
const ROW_SELECTED := Color(1, 1, 1, 0.12)
const ROW_FLASH := Color(1.0, 0.85, 0.25, 0.35)
const COST_COLOR := Color("ffd866")
const COST_RED := Color("ff5a4a")

var is_open := false
## The row Enter, Left and Backspace act on (0 when the screen opens).
var selected_row := 0
## The last sound played, so tests can check the feedback without audio files.
var last_sound: StringName = &""

var attributes: Array[AttributeData] = []
var gold_counter: GoldCounter
var reset_button: Button
var close_button: Button

var _rows: Array[PanelContainer] = []
var _pips: Array[Control] = []
var _levels: Array[Label] = []
var _summaries: Array[Label] = []
var _costs: Array[Label] = []
var _minus: Array[Button] = []
var _plus: Array[Button] = []
var _opened_levels: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attributes = AttributeRegistry.all()
	add_child(UiKit.dim(0.75))

	var panel := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.09, 0.12, 0.96)
	back.set_content_margin_all(8)
	back.set_border_width_all(1)
	back.border_color = Color("6b4a2b")
	panel.add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var header := HBoxContainer.new()
	var title := UiKit.label("CAMP", 16, Color("ffd866"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	gold_counter = GoldCounter.new()
	gold_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(gold_counter)
	box.add_child(header)

	for i in attributes.size():
		box.add_child(_build_row(i))

	var footer := HBoxContainer.new()
	reset_button = UiKit.button("Reset all", Vector2(70, 16))
	reset_button.pressed.connect(_on_reset)
	close_button = UiKit.button("Close", Vector2(70, 16))
	close_button.pressed.connect(close)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(reset_button)
	footer.add_child(spacer)
	footer.add_child(close_button)
	box.add_child(footer)

	add_child(UiKit.centered(panel))
	GameSession.attributes_changed.connect(_refresh)


func _build_row(i: int) -> PanelContainer:
	var attr := attributes[i]
	var row := PanelContainer.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(430, 24)
	row.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	row.mouse_entered.connect(func() -> void: _select(i))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _left(UiKit.label(attr.display_name, UiKit.FONT_SIZE, Color.WHITE))
	name_label.custom_minimum_size.x = 56
	line.add_child(name_label)
	var pips := Control.new()
	pips.custom_minimum_size = Vector2(attr.max_level * (PIP_SIZE.x + PIP_GAP), 10)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.draw.connect(_draw_pips.bind(pips, attr))
	line.add_child(pips)
	var level := _left(UiKit.label("", UiKit.FONT_SIZE, Color("bbbbbb")))
	line.add_child(level)
	left.add_child(line)
	var summary := _left(UiKit.label("", UiKit.FONT_SIZE, Color("9fd3ff")))
	left.add_child(summary)
	hbox.add_child(left)

	var cost := UiKit.label("", UiKit.FONT_SIZE, COST_COLOR)
	cost.custom_minimum_size.x = 56
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(cost)
	var minus := _row_button("-")
	minus.pressed.connect(_on_minus.bind(i))
	var plus := _row_button("+")
	plus.pressed.connect(_on_plus.bind(i))
	hbox.add_child(minus)
	hbox.add_child(plus)

	_rows.append(row)
	_pips.append(pips)
	_levels.append(level)
	_summaries.append(summary)
	_costs.append(cost)
	_minus.append(minus)
	_plus.append(plus)
	return row


## A plain Button (not UiKit.button, which plays menu_click on every press): no focus, small.
func _row_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(18, 16)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", UiKit.FONT_SIZE)
	return b


func _left(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _draw_pips(pips: Control, attr: AttributeData) -> void:
	var owned := GameSession.level_of(attr.id)
	for n in attr.max_level:
		var rect := Rect2(Vector2(n * (PIP_SIZE.x + PIP_GAP), 2.0), PIP_SIZE)
		if n < owned:
			pips.draw_rect(rect, COST_COLOR)
		else:
			pips.draw_rect(rect, Color(1, 1, 1, 0.5), false, 1.0)


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	selected_row = 0
	_opened_levels = GameSession.attribute_levels.duplicate()
	var owner_ctrl := get_viewport().gui_get_focus_owner()
	if owner_ctrl:
		owner_ctrl.release_focus()
	get_tree().paused = true
	gold_counter.set_amount(GameSession.gold)
	_refresh()


## Closes, unpauses and reports whether any level differs from when it opened.
func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	var changed := false
	for a in attributes:
		if GameSession.level_of(a.id) != int(_opened_levels.get(a.id, 0)):
			changed = true
	closed.emit(changed)


## True while Reset all or Close has focus; the row keys are ignored then.
func buttons_have_focus() -> bool:
	return reset_button.has_focus() or close_button.has_focus()


func _play(sound: StringName) -> void:
	last_sound = sound
	Audio.play(sound)


func _select(i: int) -> void:
	if i != selected_row:
		selected_row = i
		_refresh_highlight()


func _on_plus(i: int) -> void:
	if not is_open:
		return
	_select(i)
	var attr := attributes[i]
	if GameSession.level_of(attr.id) >= attr.max_level:
		return
	if GameSession.buy_attribute(attr.id):
		_play(&"hub_choose")
		_flash(i, ROW_FLASH)
	else:
		_play(&"no_mana")
		_flash_cost(i)


func _on_minus(i: int) -> void:
	if not is_open:
		return
	_select(i)
	if GameSession.undo_attribute(attributes[i].id):
		_play(&"menu_click")


func _on_reset() -> void:
	if GameSession.spent_total() > 0:
		GameSession.reset_attributes()
	gold_counter.set_amount(GameSession.gold)


func _refresh() -> void:
	if _rows.is_empty():
		return
	if is_open:
		gold_counter.set_amount(GameSession.gold)
	for i in attributes.size():
		var attr := attributes[i]
		var level := GameSession.level_of(attr.id)
		var maxed := level >= attr.max_level
		var price := -1 if maxed else CampShop.cost(attr, level + 1)
		var affordable := not maxed and GameSession.gold >= price
		_levels[i].text = "Lv %d/%d" % [level, attr.max_level]
		_summaries[i].text = attr.describe(level) if maxed else "%s  ->  %s" % [attr.describe(level), attr.describe(level + 1)]
		_costs[i].text = "MAX" if maxed else "%d gold" % price
		_costs[i].add_theme_color_override("font_color", COST_COLOR if (affordable or maxed) else COST_RED)
		_plus[i].disabled = maxed
		_plus[i].modulate.a = DIM_ALPHA if (not maxed and not affordable) else 1.0
		_minus[i].disabled = level <= 0
		_pips[i].queue_redraw()
	_refresh_highlight()


func _refresh_highlight() -> void:
	for i in _rows.size():
		var style := StyleBoxFlat.new()
		style.bg_color = ROW_SELECTED if i == selected_row and not buttons_have_focus() else Color(0, 0, 0, 0)
		_rows[i].add_theme_stylebox_override("panel", style)


func _flash(i: int, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	_rows[i].add_theme_stylebox_override("panel", style)
	var t := create_tween()
	t.tween_interval(0.12)
	t.tween_callback(_refresh_highlight)


func _flash_cost(i: int) -> void:
	var cost := _costs[i]
	cost.add_theme_color_override("font_color", Color.WHITE)
	var t := create_tween()
	t.tween_interval(0.12)
	t.tween_callback(_refresh)


## Esc, Start and B close the camp. Handled here (before any _unhandled_input) so the PauseMenu never sees them.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up") and buttons_have_focus():
		# Back from the buttons to the last row (rows are not focus targets, so the default navigation has nowhere to go).
		get_viewport().gui_get_focus_owner().release_focus()
		selected_row = attributes.size() - 1
		_refresh_highlight()
		get_viewport().set_input_as_handled()


## The row keys. Ignored while Reset all or Close has focus (Enter then presses the button).
func _unhandled_input(event: InputEvent) -> void:
	if not is_open or buttons_have_focus():
		return
	if event.is_action_pressed(&"ui_down"):
		if selected_row >= attributes.size() - 1:
			reset_button.grab_focus()
			_refresh_highlight()
		else:
			_select(selected_row + 1)
	elif event.is_action_pressed(&"ui_up"):
		_select(maxi(selected_row - 1, 0))
	elif event.is_action_pressed(&"ui_accept"):
		_on_plus(selected_row)
	elif event.is_action_pressed(&"ui_left") or (event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_BACKSPACE):
		_on_minus(selected_row)
	else:
		return
	get_viewport().set_input_as_handled()

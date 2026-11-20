class_name InventoryScreen
extends Control
## The inventory screen opened from the hub chest (spec 1.4): the character's seven equipment slots on the left, the pool of
## unlocked items as a grid on the right, and the description of the item under the cursor. Pauses the tree while open.
## Click or Enter on a grid item wears it, on a worn slot takes it off; Esc closes. `closed(changed)` says whether the
## character's loadout differs from when the screen opened, so the hub knows to rebuild its Player. Cells are plain
## Controls (not Buttons, no focus), as CampScreen's rows are; Esc is read in _input, the cursor keys in _unhandled_input.

signal closed(changed: bool)

const CELL := 28.0
const GAP := 4.0
const COLUMNS := 6
const VISIBLE_ROWS := 5
const FRAME := Color("6b4a2b")
const FRAME_FULL := Color("c8a15a")
const CURSOR := Color("ffd866")
const SLOT_LABELS := {&"helmet": "Helm", &"chestplate": "Chest", &"necklace": "Neck", &"ring_1": "Ring", &"ring_2": "Ring", &"pants": "Pants", &"shoes": "Shoes"}
const TYPE_NAMES := {&"helmet": "Helmet", &"chestplate": "Chestplate", &"necklace": "Necklace", &"ring": "Ring", &"pants": "Pants", &"shoes": "Shoes"}
## Slot index (Inventory.SLOTS order) -> its place in the 3 x 5 slot layout (column, row).
const SLOT_CELLS := [Vector2i(1, 0), Vector2i(1, 2), Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2), Vector2i(1, 3), Vector2i(1, 4)]
## Cursor moves between the slots: slot index -> {direction -> slot index}; "right" off the last column goes to the grid.
const SLOT_MOVES := {
	0: {&"down": 2},
	2: {&"up": 0, &"down": 1},
	1: {&"up": 2, &"down": 5, &"left": 3, &"right": 4},
	3: {&"up": 2, &"down": 5, &"right": 1},
	4: {&"up": 2, &"down": 5, &"left": 1},
	5: {&"up": 1, &"down": 6},
	6: {&"up": 5},
}

enum Zone { SLOTS, GRID }


## One slot or grid cell. Draws through the screen, which knows what it holds.
class Cell extends Control:
	var screen: InventoryScreen
	var zone := Zone.SLOTS
	var index := 0

	func _init() -> void:
		custom_minimum_size = Vector2(CELL, CELL)
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		screen.draw_cell(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			screen.click(zone, index)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER and screen != null:
			screen.hover(zone, index)


var is_open := false
## The last sound played, so tests can check the feedback without audio files.
var last_sound: StringName = &""
var zone := Zone.GRID
var slot_cursor := 0
var grid_cursor := 0
var slot_cells: Array[Cell] = []
var grid_cells: Array[Cell] = []
var items: Array[ItemData] = []  # the pool, in unlock order

var _character: CharacterData
var _opened_loadout: Dictionary = {}
var _title: Label
var _empty_label: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _name_label: Label
var _type_label: Label
var _desc_label: Label


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.75))

	var panel := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.09, 0.12, 0.96)
	back.set_content_margin_all(8)
	back.set_border_width_all(1)
	back.border_color = FRAME
	panel.add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_title = UiKit.label("INVENTORY", 16, Color("ffd866"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)
	columns.add_child(_build_slots())

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	columns.add_child(right)
	var heading := UiKit.label("Items", UiKit.FONT_SIZE, Color("bbbbbb"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(heading)
	var grid_width := COLUMNS * CELL + (COLUMNS - 1) * GAP
	var grid_height := VISIBLE_ROWS * CELL + (VISIBLE_ROWS - 1) * GAP
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(grid_width + 8.0, grid_height)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_scroll.add_child(_grid)
	_empty_label = UiKit.label("No items yet", UiKit.FONT_SIZE, Color("888888"))
	_empty_label.custom_minimum_size = Vector2(grid_width + 8.0, grid_height)
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var stack := Control.new()
	stack.custom_minimum_size = _scroll.custom_minimum_size
	stack.add_child(_scroll)
	stack.add_child(_empty_label)
	right.add_child(stack)

	_name_label = UiKit.label("", UiKit.FONT_SIZE, Color.WHITE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(_name_label)
	_type_label = UiKit.label("", UiKit.FONT_SIZE, Color("9fd3ff"))
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(_type_label)
	_desc_label = UiKit.label("", UiKit.FONT_SIZE, Color("dddddd"))
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(grid_width, 22.0)  # two lines
	_desc_label.clip_text = true
	right.add_child(_desc_label)

	var footer := Label.new()
	footer.text = "Click or Enter: wear / take off      Esc: close"
	footer.add_theme_font_size_override("font_size", 7)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	box.add_child(footer)

	add_child(UiKit.centered(panel))
	GameSession.inventory.changed.connect(_refresh)


## The seven slots in their 3 x 5 layout; empty places are spacers.
func _build_slots() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP))
	slot_cells.clear()
	for i in Inventory.SLOTS.size():
		var cell := Cell.new()
		cell.screen = self
		cell.zone = Zone.SLOTS
		cell.index = i
		slot_cells.append(cell)
	for row in 5:
		for col in 3:
			var found: Cell = null
			for i in SLOT_CELLS.size():
				if SLOT_CELLS[i] == Vector2i(col, row):
					found = slot_cells[i]
			if found != null:
				grid.add_child(found)
			else:
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(CELL, CELL)
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_child(spacer)
	return grid


## Opens the screen for `character` (a CharacterData): pauses the tree and puts the cursor on the first item.
func open(character: CharacterData) -> void:
	if is_open:
		return
	_character = character
	is_open = true
	visible = true
	_title.text = "INVENTORY - %s" % character.display_name
	_opened_loadout = _loadout()
	var owner_ctrl := get_viewport().gui_get_focus_owner()
	if owner_ctrl:
		owner_ctrl.release_focus()
	get_tree().paused = true
	_rebuild_pool()
	zone = Zone.GRID if not items.is_empty() else Zone.SLOTS
	slot_cursor = 0
	grid_cursor = 0
	_scroll.scroll_vertical = 0
	_refresh()


## Closes, unpauses and reports whether the character's loadout differs from when it opened.
func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	closed.emit(_loadout() != _opened_loadout)


func _loadout() -> Dictionary:
	return GameSession.inventory.worn_state().get(_character.id, {})


## The grid's cells follow the pool (unlocked items, in the order they were unlocked).
func _rebuild_pool() -> void:
	for cell in grid_cells:
		_grid.remove_child(cell)
		cell.free()
	grid_cells.clear()
	items.clear()
	for id in GameSession.inventory.unlocked:
		var item := ItemRegistry.find(id)
		if item != null:
			items.append(item)
	for i in items.size():
		var cell := Cell.new()
		cell.screen = self
		cell.zone = Zone.GRID
		cell.index = i
		_grid.add_child(cell)
		grid_cells.append(cell)
	_scroll.visible = not items.is_empty()
	_empty_label.visible = items.is_empty()


func _refresh() -> void:
	if not is_open:
		return
	_rebuild_pool()
	grid_cursor = clampi(grid_cursor, 0, maxi(items.size() - 1, 0))
	if items.is_empty() and zone == Zone.GRID:
		zone = Zone.SLOTS
	_redraw()


func _redraw() -> void:
	for cell in slot_cells:
		cell.queue_redraw()
	for cell in grid_cells:
		cell.queue_redraw()
	var item := _cursor_item()
	_name_label.text = "" if item == null else item.display_name
	_type_label.text = "" if item == null else TYPE_NAMES.get(item.slot, "")
	_desc_label.text = "" if item == null else item.description
	if zone == Zone.SLOTS and item == null:
		_type_label.text = _slot_name(Inventory.SLOTS[slot_cursor])


## The item under the cursor: the one in the slot, or the grid's. Null when there is none.
func _cursor_item() -> ItemData:
	if zone == Zone.SLOTS:
		return GameSession.inventory.worn(_character.id, Inventory.SLOTS[slot_cursor])
	return items[grid_cursor] if grid_cursor < items.size() else null


func _slot_name(slot: StringName) -> String:
	return "%s slot" % TYPE_NAMES.get(&"ring" if slot in [&"ring_1", &"ring_2"] else slot, "")


## Draws one cell: a frame (gold for the cursor), the item's icon or letter, the faint slot name when empty, and the marks.
func draw_cell(cell: Cell) -> void:
	var rect := Rect2(Vector2.ZERO, cell.size)
	var inv := GameSession.inventory
	var item: ItemData = null
	var elsewhere := &""
	var worn_here := false
	if cell.zone == Zone.SLOTS:
		item = inv.worn(_character.id, Inventory.SLOTS[cell.index])
	else:
		item = items[cell.index]
		var wearer := inv.wearer_of(item.id)
		worn_here = wearer == _character.id
		if wearer != &"" and wearer != _character.id:
			elsewhere = wearer
	var active: bool = is_open and zone == cell.zone and (slot_cursor if cell.zone == Zone.SLOTS else grid_cursor) == cell.index
	cell.draw_rect(rect, Color(0.16, 0.14, 0.18))
	var frame: Color = CURSOR if active else (FRAME_FULL if (item != null and (cell.zone == Zone.SLOTS or worn_here)) else FRAME)
	cell.draw_rect(rect, frame, false, 2.0 if active else 1.0)
	var font := ThemeDB.fallback_font
	if item == null:
		cell.draw_string(font, Vector2(0, CELL / 2.0 + 3.0), SLOT_LABELS[Inventory.SLOTS[cell.index]], HORIZONTAL_ALIGNMENT_CENTER, CELL, 7, Color(1, 1, 1, 0.3))
		return
	var alpha := 0.45 if elsewhere != &"" else 1.0
	if item.icon != null:
		cell.draw_texture_rect(item.icon, Rect2(Vector2(2, 2), Vector2(CELL - 4.0, CELL - 4.0)), false, Color(1, 1, 1, alpha))
	else:
		var hue := float(hash(str(item.id)) % 360) / 360.0
		cell.draw_rect(Rect2(Vector2(4, 4), Vector2(CELL - 8.0, CELL - 8.0)), Color.from_hsv(hue, 0.5, 0.8, alpha))
		var letter := item.display_name.substr(0, 1).to_upper()
		cell.draw_string(font, Vector2(0, CELL / 2.0 + 4.0), letter, HORIZONTAL_ALIGNMENT_CENTER, CELL, 10, Color(0, 0, 0, alpha))
	if cell.zone == Zone.GRID and worn_here:
		cell.draw_string(font, Vector2(CELL - 8.0, CELL - 3.0), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, CURSOR)
	if elsewhere != &"":
		cell.draw_string(font, Vector2(CELL - 8.0, CELL - 3.0), String(elsewhere).substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("9fd3ff"))


## The mouse is over a cell: the cursor goes there.
func hover(cell_zone: Zone, index: int) -> void:
	if not is_open:
		return
	_set_cursor(cell_zone, index)


## A left click on a cell (the cursor goes there, then it acts as Enter would).
func click(cell_zone: Zone, index: int) -> void:
	if not is_open:
		return
	_set_cursor(cell_zone, index)
	_activate()


func _set_cursor(cell_zone: Zone, index: int) -> void:
	zone = cell_zone
	if cell_zone == Zone.SLOTS:
		slot_cursor = clampi(index, 0, Inventory.SLOTS.size() - 1)
	else:
		grid_cursor = clampi(index, 0, maxi(items.size() - 1, 0))
		_scroll_to_cursor()
	_redraw()


## Wears the item under the cursor (grid) or takes off the one in the slot (slots).
func _activate() -> void:
	var inv := GameSession.inventory
	if zone == Zone.SLOTS:
		if inv.unequip(_character.id, Inventory.SLOTS[slot_cursor]):
			_play(&"menu_click")
		return
	if items.is_empty():
		return
	var id := items[grid_cursor].id
	if inv.slot_of(_character.id, id) != &"":
		return  # already worn here: taking it off is done from its slot
	if inv.equip(_character.id, id) == &"":
		_play(&"no_mana")
	else:
		_play(&"hub_choose")


func _play(sound: StringName) -> void:
	last_sound = sound
	Audio.play(sound)


## The ScrollContainer does not follow a custom cursor: keep the cursor's row inside the view.
func _scroll_to_cursor() -> void:
	var top := float(grid_cursor / COLUMNS) * (CELL + GAP)
	var view := float(VISIBLE_ROWS) * CELL + float(VISIBLE_ROWS - 1) * GAP
	if top < _scroll.scroll_vertical:
		_scroll.scroll_vertical = int(top)
	elif top + CELL > _scroll.scroll_vertical + view:
		_scroll.scroll_vertical = int(top + CELL - view)


## Esc, Start and B close the screen. Handled here (before any _unhandled_input) so the PauseMenu never sees them.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## The cursor keys.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"ui_down"):
		_move(&"down")
	elif event.is_action_pressed(&"ui_up"):
		_move(&"up")
	elif event.is_action_pressed(&"ui_left"):
		_move(&"left")
	elif event.is_action_pressed(&"ui_right"):
		_move(&"right")
	elif event.is_action_pressed(&"ui_accept"):
		_activate()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(direction: StringName) -> void:
	if zone == Zone.SLOTS:
		var moves: Dictionary = SLOT_MOVES[slot_cursor]
		if moves.has(direction):
			slot_cursor = moves[direction]
		elif direction == &"right" and not items.is_empty():
			zone = Zone.GRID
		_redraw()
		return
	if items.is_empty():
		return
	var col := grid_cursor % COLUMNS
	match direction:
		&"left":
			if col == 0:
				zone = Zone.SLOTS
			else:
				grid_cursor -= 1
		&"right":
			if col < COLUMNS - 1 and grid_cursor < items.size() - 1:
				grid_cursor += 1
		&"up":
			if grid_cursor >= COLUMNS:
				grid_cursor -= COLUMNS
		&"down":
			if grid_cursor + COLUMNS < items.size():
				grid_cursor += COLUMNS
			elif grid_cursor / COLUMNS < (items.size() - 1) / COLUMNS:
				grid_cursor = items.size() - 1  # the last row is shorter: land on its last cell
	_scroll_to_cursor()
	_redraw()

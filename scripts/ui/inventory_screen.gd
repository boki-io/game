class_name InventoryScreen
extends Control
## The inventory screen opened from the hub chest (spec 1.4), drawn on the "Character" menu art (assets/ui/character_menu.png,
## 320 x 234, shown at 1.5x): the character's seven equipment slots on the left, the pool of unlocked items as a 6 x 7 grid on
## the right, and the description of the item under the cursor in a panel beside the art. Pauses the tree while open. Click or Enter on a grid item wears it, on a worn slot takes it off; Esc
## closes. `closed(changed)` says whether the character's loadout differs from when the screen opened, so the hub knows to
## rebuild its Player. Cells are plain Controls placed on the art (not Buttons, no focus), as CampScreen's rows are; Esc is read
## in _input, the cursor keys in _unhandled_input.

signal closed(changed: bool)

const ART := preload("res://assets/ui/character_menu.png")
const ART_SCALE := 1.5
## Where the art's top-left corner sits in the 640 x 360 view: at the left, the description panel takes the space to its right.
const ART_POS := Vector2(3, 4)
const PANEL_WIDTH := 148.0
const COLUMNS := 6
const VISIBLE_ROWS := 7
const ICON := 32.0
const FRAME := Color("6b4a2b")
const CURSOR := Color("ffd866")
const TYPE_NAMES := {&"helmet": "Helmet", &"chestplate": "Chestplate", &"necklace": "Necklace", &"ring": "Ring", &"pants": "Pants", &"shoes": "Shoes"}
## Each slot's interior in the art's pixels (Inventory.SLOTS order: helmet, chestplate, necklace, ring_1, ring_2, pants, shoes).
const SLOT_RECTS := [Rect2(66, 49, 24, 24), Rect2(66, 119, 24, 24), Rect2(66, 84, 24, 24), Rect2(24, 119, 24, 24),
	Rect2(108, 119, 24, 24), Rect2(66, 154, 24, 24), Rect2(66, 189, 24, 24)]
## The grid's first cell interior in the art's pixels and the step between cells (22 x 22 cells, 24 apart).
const GRID_ORIGIN := Vector2(163, 46)
const GRID_STEP := 24.0
const GRID_CELL := 22.0
## Cursor moves between the slots: slot index -> {direction -> slot index}. A slot with no "right" goes to the grid.
const SLOT_MOVES := {
	0: {&"down": 2},
	2: {&"up": 0, &"down": 1},
	1: {&"up": 2, &"down": 5, &"left": 3, &"right": 4},
	3: {&"up": 2, &"right": 1, &"down": 5},
	4: {&"up": 2, &"left": 1, &"down": 5},
	5: {&"up": 1, &"down": 6},
	6: {&"up": 5},
}

enum Zone { SLOTS, GRID }


## One slot or grid cell. Draws through the screen, which knows what it holds. `index` is the slot number, or the place in the
## visible 6 x 7 window for the grid.
class Cell extends Control:
	var screen: InventoryScreen
	var zone := Zone.SLOTS
	var index := 0

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		screen.draw_cell(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			screen.click(zone, screen.item_index(self))
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER and screen != null:
			screen.hover(zone, screen.item_index(self))


var is_open := false
## The last sound played, so tests can check the feedback without audio files.
var last_sound: StringName = &""
var zone := Zone.GRID
var slot_cursor := 0
## The cursor's place in `items` (not in the window).
var grid_cursor := 0
## The first row of items the grid window shows (the art holds 7 rows; more items scroll).
var scroll_row := 0
var slot_cells: Array[Cell] = []
var grid_cells: Array[Cell] = []  # the 42 cells of the window
var items: Array[ItemData] = []  # the pool, in unlock order

var _character: CharacterData
var _opened_loadout: Dictionary = {}
var _title: Label
var _empty_label: Label
var _name_label: Label
var _type_label: Label
var _desc_label: Label


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.75))

	var back := TextureRect.new()
	back.texture = ART
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.mouse_filter = Control.MOUSE_FILTER_STOP  # swallows clicks on the art's own panels
	back.position = ART_POS
	back.size = ART.get_size() * ART_SCALE
	add_child(back)

	for i in Inventory.SLOTS.size():
		var cell := Cell.new()
		cell.screen = self
		cell.zone = Zone.SLOTS
		cell.index = i
		_place(cell, SLOT_RECTS[i])
		add_child(cell)
		slot_cells.append(cell)
	for i in COLUMNS * VISIBLE_ROWS:
		var cell := Cell.new()
		cell.screen = self
		cell.zone = Zone.GRID
		cell.index = i
		_place(cell, Rect2(GRID_ORIGIN + Vector2(i % COLUMNS, i / COLUMNS) * GRID_STEP, Vector2(GRID_CELL, GRID_CELL)))
		add_child(cell)
		grid_cells.append(cell)

	_empty_label = UiKit.label("No items yet", UiKit.FONT_SIZE, Color("8a8070"))
	_empty_label.position = _to_view(GRID_ORIGIN + Vector2(0, 72))
	_empty_label.custom_minimum_size = Vector2(GRID_STEP * COLUMNS - 2.0, 0) * ART_SCALE
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_empty_label)

	# The description panel beside the art: the character, then the item under the cursor.
	var panel_x := ART_POS.x + ART.get_width() * ART_SCALE + 3.0
	var panel := ColorRect.new()  # hides the hub's HUD, which shows through the dim
	panel.color = Color(0.1, 0.09, 0.11, 0.97)
	panel.position = Vector2(panel_x, ART_POS.y)
	panel.size = Vector2(PANEL_WIDTH, ART.get_height() * ART_SCALE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(panel_x + 6.0, ART_POS.y + 8.0)
	box.custom_minimum_size = Vector2(PANEL_WIDTH - 12.0, 0)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _panel_label(box, 12, Color("ffd866"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)
	_name_label = _panel_label(box, UiKit.FONT_SIZE, Color.WHITE)
	_type_label = _panel_label(box, UiKit.FONT_SIZE, Color("9fd3ff"))
	_desc_label = _panel_label(box, UiKit.FONT_SIZE, Color("dddddd"))
	var footer := _panel_label(null, 7, Color(1, 1, 1, 0.4))
	footer.position = Vector2(panel_x + 6.0, ART_POS.y + ART.get_height() * ART_SCALE - 30.0)
	footer.custom_minimum_size = Vector2(PANEL_WIDTH - 12.0, 0)
	footer.text = "Click or Enter: wear / take off\nEsc: close"
	add_child(footer)

	GameSession.inventory.changed.connect(_refresh)


## A wrapping, left-aligned label of the panel (in `box` when given).
func _panel_label(box: Control, size: int, color: Color) -> Label:
	var label := UiKit.label("", size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(PANEL_WIDTH - 12.0, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if box != null:
		box.add_child(label)
	return label


## A point of the art in the 640 x 360 view.
func _to_view(art_point: Vector2) -> Vector2:
	return (ART_POS + art_point * ART_SCALE).round()


## Puts `cell` on a rectangle of the art.
func _place(cell: Control, art_rect: Rect2) -> void:
	cell.position = _to_view(art_rect.position)
	cell.size = (art_rect.size * ART_SCALE).round()


## Opens the screen for `character` (a CharacterData): pauses the tree and puts the cursor on the first item.
func open(character: CharacterData) -> void:
	if is_open:
		return
	_character = character
	is_open = true
	visible = true
	_title.text = character.display_name
	_opened_loadout = _loadout()
	var owner_ctrl := get_viewport().gui_get_focus_owner()
	if owner_ctrl:
		owner_ctrl.release_focus()
	get_tree().paused = true
	_rebuild_pool()
	zone = Zone.GRID if not items.is_empty() else Zone.SLOTS
	slot_cursor = 0
	grid_cursor = 0
	scroll_row = 0
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


## The pool, in the order the items were unlocked.
func _rebuild_pool() -> void:
	items.clear()
	for id in GameSession.inventory.unlocked:
		var item := ItemRegistry.find(id)
		if item != null:
			items.append(item)
	_empty_label.visible = items.is_empty()


func _refresh() -> void:
	if not is_open:
		return
	_rebuild_pool()
	grid_cursor = clampi(grid_cursor, 0, maxi(items.size() - 1, 0))
	scroll_row = clampi(scroll_row, 0, _max_scroll_row())
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
	_name_label.add_theme_color_override("font_color", Color.WHITE if item == null else ItemData.rating_color(item.rating))
	_type_label.text = "" if item == null else _type_text(item)
	_desc_label.text = "" if item == null else _desc_text(item)
	if zone == Zone.SLOTS and item == null:
		_type_label.text = _slot_name(Inventory.SLOTS[slot_cursor])


## "Epic Helmet", or "Legendary Shoes - Fire Trail" for a legendary that grants a relic.
func _type_text(item: ItemData) -> String:
	var text := "%s %s" % [ItemData.rating_name(item.rating), TYPE_NAMES.get(item.slot, "")]
	if item.relic_id != &"":
		var relic := RelicRegistry.find(item.relic_id)
		text += " - %s" % (relic.display_name if relic != null else String(item.relic_id))
	return text


## The stat line, and under it the flavour line when there is one.
func _desc_text(item: ItemData) -> String:
	return item.stat_text() if item.description.is_empty() else "%s\n%s" % [item.stat_text(), item.description]


## The place in `items` that a cell stands for: a slot's own number, or the window position plus the scrolled rows.
func item_index(cell: Cell) -> int:
	return cell.index if cell.zone == Zone.SLOTS else scroll_row * COLUMNS + cell.index


## The item a cell holds, or null (an empty slot, or a window place past the end of the pool).
func cell_item(cell: Cell) -> ItemData:
	if cell.zone == Zone.SLOTS:
		return GameSession.inventory.worn(_character.id, Inventory.SLOTS[cell.index])
	var i := item_index(cell)
	return items[i] if i < items.size() else null


func _is_cursor(cell: Cell) -> bool:
	return is_open and zone == cell.zone and (slot_cursor if cell.zone == Zone.SLOTS else grid_cursor) == item_index(cell)


## The frame colour of a cell: gold for the cursor, else the rating colour of the item it holds (brighter for an item worn
## here), else the plain frame.
func frame_color(cell: Cell) -> Color:
	if _is_cursor(cell):
		return CURSOR
	var item := cell_item(cell)
	if item == null:
		return FRAME
	var rated := ItemData.rating_color(item.rating)
	var worn_here := cell.zone == Zone.SLOTS or GameSession.inventory.wearer_of(item.id) == _character.id
	return rated.lightened(0.3) if worn_here else rated


## The item under the cursor: the one in the slot, or the grid's. Null when there is none.
func _cursor_item() -> ItemData:
	if zone == Zone.SLOTS:
		return GameSession.inventory.worn(_character.id, Inventory.SLOTS[slot_cursor])
	return items[grid_cursor] if grid_cursor < items.size() else null


func _slot_name(slot: StringName) -> String:
	return "%s slot" % TYPE_NAMES.get(&"ring" if slot in [&"ring_1", &"ring_2"] else slot, "")


## Draws one cell on the art: the rating frame (gold for the cursor) when it holds
## something or has the cursor, the item's icon or letter, and the marks. Empty cells show the art's own slot.
func draw_cell(cell: Cell) -> void:
	var rect := Rect2(Vector2.ZERO, cell.size)
	var inv := GameSession.inventory
	var item := cell_item(cell)
	var active := _is_cursor(cell)
	if item == null:
		if active:
			cell.draw_rect(rect, CURSOR, false, 2.0)
		return
	var elsewhere := &""
	var worn_here := false
	if cell.zone == Zone.GRID:
		var wearer := inv.wearer_of(item.id)
		worn_here = wearer == _character.id
		if wearer != &"" and wearer != _character.id:
			elsewhere = wearer
	cell.draw_rect(rect, frame_color(cell), false, 2.0 if active else 1.0)
	var font := ThemeDB.fallback_font
	var alpha := 0.45 if elsewhere != &"" else 1.0
	var at := ((cell.size - Vector2(ICON, ICON)) / 2.0).floor()
	if item.icon != null:
		cell.draw_texture_rect(item.icon, Rect2(at, Vector2(ICON, ICON)), false, Color(1, 1, 1, alpha))
	else:
		var hue := float(hash(str(item.id)) % 360) / 360.0
		cell.draw_rect(Rect2(at + Vector2(4, 4), Vector2(ICON - 8.0, ICON - 8.0)), Color.from_hsv(hue, 0.5, 0.8, alpha))
		var letter := item.display_name.substr(0, 1).to_upper()
		cell.draw_string(font, Vector2(0, cell.size.y / 2.0 + 4.0), letter, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, 10, Color(0, 0, 0, alpha))
	if worn_here:
		cell.draw_string(font, Vector2(cell.size.x - 8.0, cell.size.y - 3.0), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, CURSOR)
	if elsewhere != &"":
		cell.draw_string(font, Vector2(cell.size.x - 8.0, cell.size.y - 3.0), String(elsewhere).substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("9fd3ff"))


## The mouse is over a cell: the cursor goes there. `index` is the slot number, or the place in `items`.
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
	if cell_zone == Zone.GRID and index >= items.size():
		return  # an empty place in the grid is not a target
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


func _max_scroll_row() -> int:
	var rows := ceili(float(items.size()) / COLUMNS)
	return maxi(rows - VISIBLE_ROWS, 0)


## The window follows the cursor: scroll so the cursor's row is one of the seven shown.
func _scroll_to_cursor() -> void:
	var row := grid_cursor / COLUMNS
	if row < scroll_row:
		scroll_row = row
	elif row >= scroll_row + VISIBLE_ROWS:
		scroll_row = row - VISIBLE_ROWS + 1


## Esc, Start and B close the screen. Handled here (before any _unhandled_input) so the PauseMenu never sees them.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		scroll_row = clampi(scroll_row + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, _max_scroll_row())
		_redraw()
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

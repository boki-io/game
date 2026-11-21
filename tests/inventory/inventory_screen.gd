extends SceneTree
## The inventory screen (spec 1.4): seven slots and the item grid, "No items yet" with an empty pool, wearing and taking
## off by click and by keyboard, rings, an item worn by another character (dimmed, moves on click), the description line,
## cursor movement between the slots and the grid, scrolling, Esc closing with the right `changed` flag and unpausing, the
## feedback sounds, and the hub opening the real screen from the chest.
## Run: godot --headless --path . --script tests/inventory/inventory_screen.gd

const SG := preload("res://scripts/systems/save_game.gd")
const ItemDataS := preload("res://scripts/inventory/item_data.gd")
const Reg := preload("res://scripts/inventory/item_registry.gd")

var _failed := false
var _gs: Node
var _screen: Control


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _item(id: String, name: String, slot: String, desc := "", rating := "standard", relic := "") -> Resource:
	var it = ItemDataS.new()
	it.rating = StringName(rating)
	it.relic_id = StringName(relic)
	it.id = StringName(id)
	it.display_name = name
	it.slot = StringName(slot)
	it.description = desc
	return it


func _key(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	await process_frame  # buffered events are flushed per frame: give the press time to arrive before the release
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame
	await process_frame


func _character(id: StringName):
	for c in CharacterRegistry.all():
		if c.id == id:
			return c
	return null


func _init() -> void:
	await process_frame
	await process_frame
	_gs = root.get_node("GameSession")
	SG.override_path = ""  # nothing is written to the player's save
	_gs.inventory.set_state([], {})
	_screen = load("res://scripts/ui/inventory_screen.gd").new()
	root.add_child(_screen)
	await process_frame
	await _empty()
	await _items()
	await _rated()
	await _keyboard()
	await _other_character_and_close()
	await _many()
	await _hub()
	_gs.inventory.set_state([], {})
	Reg.test_items.clear()
	SG.override_path = null
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _empty() -> void:
	var knight = _character(&"knight")
	_screen.open(knight)
	_check(_screen.is_open and paused, "open() shows the screen and pauses the tree")
	_check(_screen.slot_cells.size() == 7, "seven slots")
	_check(_screen.items.is_empty() and _screen._empty_label.visible, "an empty pool reads No items yet")
	_check(_screen._empty_label.text == "No items yet", "the empty text")
	_check(_screen.zone == _screen.Zone.SLOTS and _screen.slot_cursor == 0, "with nothing to wear the cursor starts on the helmet slot")
	_check(_screen._title.text == knight.display_name, "the strip names the character: %s" % _screen._title.text)
	_layout()
	await _key(&"ui_cancel")
	_check(not _screen.is_open and not paused, "Esc closes and unpauses")


## The cells sit on the art: slots and grid cells inside the art's rectangle, none overlapping, the grid a regular 6 x 6, the
## chestplate slot (not in the art) right of the necklace and clear of everything.
func _layout() -> void:
	var art := Rect2(_screen.ART_POS, _screen.ART.get_size() * _screen.ART_SCALE)
	var rects: Array[Rect2] = []
	for c in _screen.slot_cells + _screen.grid_cells:
		var r := Rect2(c.position, c.size)
		_check(art.encloses(r), "a cell at %s is inside the art" % [r])
		for other in rects:
			_check(not r.intersects(other), "cell %s overlaps another" % [r])
		rects.append(r)
	_check(_screen.grid_cells.size() == 36 and _screen.grid_cells[7].position.x == _screen.grid_cells[1].position.x and _screen.grid_cells[7].position.y == _screen.grid_cells[6].position.y, "the grid is a regular 6 x 6")
	var neck: Control = _screen.slot_cells[2]
	var chest: Control = _screen.slot_cells[1]
	_check(chest.position.y == neck.position.y and chest.position.x > neck.position.x + neck.size.x, "the chestplate slot sits right of the necklace")
	_check(_screen.ICON <= _screen.grid_cells[0].size.x and _screen.ICON <= _screen.slot_cells[0].size.x, "a 32 px icon fits every cell")
	var view := Rect2(Vector2.ZERO, Vector2(640, 360))
	_check(view.encloses(art), "the art fits the 640 x 360 view")


func _items() -> void:
	for it in [_item("cap", "Iron Cap", "helmet", "A plain cap."), _item("mail", "Chain Mail", "chestplate", "Heavy but safe."), _item("band", "Brass Band", "ring"),
			_item("loop", "Silver Loop", "ring"), _item("stud", "Jade Stud", "ring"), _item("boots", "Road Boots", "shoes")]:
		Reg.test_items.append(it)
	for it in Reg.test_items:
		_gs.inventory.unlock(it.id)
	var knight = _character(&"knight")
	var closed_flags := []
	_screen.closed.connect(func(changed: bool) -> void: closed_flags.append(changed))
	_screen.open(knight)
	_check(_screen.grid_cells.size() == 36 and _screen.items.size() == 6 and not _screen._empty_label.visible, "the 6 x 6 window holds the six items")
	_check(_screen.zone == _screen.Zone.GRID and _screen.grid_cursor == 0, "the cursor starts on the first item")
	_check(_screen._name_label.text == "Iron Cap" and _screen._type_label.text == "Standard Helmet" and _screen._desc_label.text == "\nA plain cap.", "the labels show the item under the cursor (type '%s', text '%s')" % [_screen._type_label.text, _screen._desc_label.text])
	_check(_screen._name_label.get_theme_color("font_color") == ItemDataS.rating_color(&"standard"), "the name is in the rating colour")
	_check(_screen._desc_label.custom_minimum_size.y == 33.0, "the description label is three lines high")

	# Click wears; the slot shows it; a second click does nothing; a click on the slot takes it off.
	_screen.click(_screen.Zone.GRID, 0)
	_check(_gs.inventory.worn(&"knight", &"helmet").id == &"cap" and _screen.last_sound == &"hub_choose", "a click on an item wears it (sound %s)" % _screen.last_sound)
	_screen.last_sound = &""
	_screen.click(_screen.Zone.GRID, 0)
	_check(_gs.inventory.worn(&"knight", &"helmet").id == &"cap" and _screen.last_sound == &"", "a click on a worn item does nothing and plays nothing")
	_screen.click(_screen.Zone.SLOTS, 0)
	_check(_gs.inventory.worn(&"knight", &"helmet") == null and _screen.last_sound == &"menu_click", "a click on the worn slot takes it off (sound %s)" % _screen.last_sound)
	_screen.last_sound = &""
	_screen.click(_screen.Zone.SLOTS, 0)
	_check(_screen.last_sound == &"", "a click on an empty slot does nothing")

	# Rings fill both ring slots.
	_screen.click(_screen.Zone.GRID, 2)
	_screen.click(_screen.Zone.GRID, 3)
	_check(_gs.inventory.worn(&"knight", &"ring_1").id == &"band" and _gs.inventory.worn(&"knight", &"ring_2").id == &"loop", "two rings fill ring_1 and ring_2")
	# Hover moves the cursor and the description.
	_screen.hover(_screen.Zone.GRID, 1)
	_check(_screen._name_label.text == "Chain Mail" and _screen.grid_cursor == 1, "hover moves the cursor and shows the description")
	_screen.hover(_screen.Zone.SLOTS, 3)
	_check(_screen._name_label.text == "Brass Band", "hovering a worn slot describes its item")
	_screen.hover(_screen.Zone.SLOTS, 0)
	_check(_screen._name_label.text == "" and _screen._type_label.text == "Helmet slot", "an empty slot names itself")
	await _key(&"ui_cancel")
	_check(closed_flags == [true], "closing after wearing something reports changed (%s)" % [closed_flags])

	# Opening and closing with no change reports false.
	_screen.open(knight)
	await _key(&"ui_cancel")
	_check(closed_flags == [true, false], "closing with no change reports false (%s)" % [closed_flags])
	# Wearing and taking off again is no change.
	_screen.open(knight)
	_screen.click(_screen.Zone.GRID, 5)
	_screen.click(_screen.Zone.SLOTS, 6)
	await _key(&"ui_cancel")
	_check(closed_flags == [true, false, false], "wear then take off is not a change (%s)" % [closed_flags])


## Rating colours on the frames and labels, the relic in the type line, stat lines (spec 1.5 section 6).
func _rated() -> void:
	_gs.inventory.set_state(Reg.test_items.map(func(it): return it.id), {})
	var epic = _item("helm", "Warden Helm", "helmet", "", "epic")
	epic.adds = {&"hp_regen": 0.6, &"max_hp": 10}
	var legend = _item("boots2", "Emberstep Boots", "shoes", "Every step leaves a spark.", "legendary", "fire_trail")
	legend.scales = {&"move_speed": 0.12}
	var ring = _item("ring2", "Gold Ring", "ring", "", "legendary")
	Reg.test_items.append_array([epic, legend, ring])
	_gs.inventory.unlock(&"helm")
	_gs.inventory.unlock(&"boots2")
	_gs.inventory.unlock(&"ring2")
	_screen.open(_character(&"knight"))
	var i_epic: int = _screen.items.find(epic)
	var i_leg: int = _screen.items.find(legend)
	var i_ring: int = _screen.items.find(ring)
	_screen.hover(_screen.Zone.GRID, i_epic)
	_check(_screen._type_label.text == "Epic Helmet" and _screen._desc_label.text == "+0.6 HP/s, +10 max HP", "epic type and stat line: '%s' '%s'" % [_screen._type_label.text, _screen._desc_label.text])
	_check(_screen._name_label.get_theme_color("font_color") == ItemDataS.rating_color(&"epic"), "the name of an epic is purple")
	_screen.hover(_screen.Zone.GRID, i_leg)
	_check(_screen._type_label.text == "Legendary Shoes - Fire Trail", "a legendary names its relic: '%s'" % _screen._type_label.text)
	_check(_screen._desc_label.text == "+12% move speed\nEvery step leaves a spark.", "stat line then flavour line: '%s'" % _screen._desc_label.text)
	_check(_screen._name_label.get_theme_color("font_color") == ItemDataS.rating_color(&"legendary"), "the name of a legendary is orange")
	_screen.hover(_screen.Zone.GRID, i_ring)
	_check(_screen._type_label.text == "Legendary Ring", "a legendary without a relic has no relic in the type line: '%s'" % _screen._type_label.text)
	# Frames: cursor gold, others in the rating colour, worn ones brighter, empty slots plain.
	_check(_screen.frame_color(_screen.grid_cells[i_ring]) == _screen.CURSOR, "the cursor frame stays gold")
	_check(_screen.frame_color(_screen.grid_cells[i_epic]) == ItemDataS.rating_color(&"epic"), "an epic cell has a purple frame")
	_check(_screen.frame_color(_screen.grid_cells[i_leg]) == ItemDataS.rating_color(&"legendary"), "a legendary cell has an orange frame")
	var std_index: int = _screen.items.find(Reg.test_items[0])
	_check(_screen.frame_color(_screen.grid_cells[std_index]) == ItemDataS.rating_color(&"standard"), "a standard cell has a stone frame")
	_check(_screen.frame_color(_screen.slot_cells[6]) == _screen.FRAME, "an empty slot has the plain frame")
	_screen.click(_screen.Zone.GRID, i_epic)
	_screen.hover(_screen.Zone.GRID, i_ring)
	_check(_screen.frame_color(_screen.grid_cells[i_epic]) == ItemDataS.rating_color(&"epic").lightened(0.3), "a worn item's frame is brighter")
	_check(_screen.frame_color(_screen.slot_cells[0]) == ItemDataS.rating_color(&"epic").lightened(0.3), "the slot holding it shows its rating")
	_screen.click(_screen.Zone.SLOTS, 0)
	_screen.hover(_screen.Zone.SLOTS, 6)
	_check(_screen._type_label.text == "Shoes slot", "an empty slot still names itself")
	Reg.test_items.erase(epic)
	Reg.test_items.erase(legend)
	Reg.test_items.erase(ring)
	_gs.inventory.set_state(Reg.test_items.map(func(it): return it.id), {})
	_screen.close()
	_gs.inventory.set_state(Reg.test_items.map(func(it): return it.id), {})


func _keyboard() -> void:
	var knight = _character(&"knight")
	_gs.inventory.set_state(_gs.inventory.unlocked, {})
	_screen.open(knight)
	_check(_screen.zone == _screen.Zone.GRID and _screen.grid_cursor == 0, "keyboard: starts on the first item")
	await _key(&"ui_right")
	await _key(&"ui_right")
	_check(_screen.grid_cursor == 2, "right moves along the grid")
	await _key(&"ui_accept")
	_check(_gs.inventory.worn(&"knight", &"ring_1").id == &"band", "Enter wears the item under the cursor (a ring takes the first free ring slot)")
	await _key(&"ui_right")
	await _key(&"ui_accept")
	_check(_gs.inventory.worn(&"knight", &"ring_2").id == &"loop", "the next ring takes ring_2")
	await _key(&"ui_down")
	_check(_screen.grid_cursor == 3, "down in a one-row grid stays (cursor %d)" % _screen.grid_cursor)
	# Left from the first column goes to the slots, Right from a right-hand slot comes back.
	for i in 4:
		await _key(&"ui_left")
	_check(_screen.grid_cursor == 0, "left walks back to the first column (%d)" % _screen.grid_cursor)
	await _key(&"ui_left")
	_check(_screen.zone == _screen.Zone.SLOTS, "left from the first column goes to the slots")
	_screen.slot_cursor = 0
	await _key(&"ui_down")
	_check(_screen.slot_cursor == 2, "down from the helmet goes to the necklace")
	await _key(&"ui_down")
	_check(_screen.slot_cursor == 5, "down again reaches the pants slot")
	await _key(&"ui_right")
	_check(_screen.slot_cursor == 4, "right from the pants reaches ring_2")
	await _key(&"ui_accept")
	_check(_gs.inventory.worn(&"knight", &"ring_2") == null, "Enter on a worn slot takes it off")
	await _key(&"ui_right")
	_check(_screen.zone == _screen.Zone.GRID, "right from the last column of slots goes to the grid")
	await _key(&"ui_cancel")
	_gs.inventory.set_state(_gs.inventory.unlocked, {})


func _other_character_and_close() -> void:
	var knight = _character(&"knight")
	var wizard = _character(&"wizard")
	_gs.inventory.equip(&"knight", &"cap")
	_screen.open(wizard)
	_check(_screen._title.text == wizard.display_name, "the strip follows the character")
	_check(_gs.inventory.wearer_of(&"cap") == &"knight" and _screen.items[0].id == &"cap", "the pool is shared: the Knight's cap is listed for the Wizard")
	_screen.click(_screen.Zone.GRID, 0)
	_check(_gs.inventory.wearer_of(&"cap") == &"wizard" and _gs.inventory.worn(&"knight", &"helmet") == null, "a click moves an item worn by another character")
	await _key(&"ui_cancel")
	_gs.inventory.set_state(_gs.inventory.unlocked, {})


func _many() -> void:
	Reg.test_items.clear()
	_gs.inventory.set_state([], {})
	for i in 40:
		Reg.test_items.append(_item("it%d" % i, "Item %d" % i, "ring"))
	for it in Reg.test_items:
		_gs.inventory.unlock(it.id)
	_screen.open(_character(&"knight"))
	_check(_screen.items.size() == 40 and _screen.grid_cells.size() == 36, "forty items, a window of 36 cells")
	for i in 7:
		await _key(&"ui_down")
	_check(_screen.grid_cursor == 36, "down walks to the last row, same column (%d)" % _screen.grid_cursor)
	await _physics_wait(2)
	_check(_screen.scroll_row == 1, "the window follows the cursor to the last row (scroll_row %d)" % _screen.scroll_row)
	_check(_screen.item_index(_screen.grid_cells[0]) == 6 and _screen.cell_item(_screen.grid_cells[0]).id == &"it6", "after scrolling, the first cell stands for item 6")
	_check(_screen.cell_item(_screen.grid_cells[33]).id == &"it39" and _screen.cell_item(_screen.grid_cells[34]) == null, "the last row shows items 36 to 39, then empty places")
	_screen.click(_screen.Zone.GRID, 36)
	_check(_gs.inventory.wearer_of(&"it36") == &"knight", "a click on a scrolled cell wears the item it stands for")
	_screen.click(_screen.Zone.GRID, 36)
	_gs.inventory.unequip(&"knight", &"ring_1")
	for i in 7:
		await _key(&"ui_up")
	_check(_screen.grid_cursor == 0 and _screen.scroll_row == 0, "up scrolls back to the top (%d, %d)" % [_screen.grid_cursor, _screen.scroll_row])
	# From a column the last row has, down lands on the last cell of the shorter row.
	_screen.grid_cursor = 4
	await _key(&"ui_down")
	_check(_screen.grid_cursor == 10, "plain down moves one row (%d)" % _screen.grid_cursor)
	_screen.grid_cursor = 34
	await _key(&"ui_down")
	_check(_screen.grid_cursor == 39, "down from a column the last row lacks lands on its last cell (%d)" % _screen.grid_cursor)
	_screen.grid_cursor = 0
	# A third ring when both are worn replaces ring_1.
	_screen.click(_screen.Zone.GRID, 0)
	_screen.click(_screen.Zone.GRID, 1)
	_screen.click(_screen.Zone.GRID, 2)
	_check(_gs.inventory.worn(&"knight", &"ring_1").id == &"it2" and _gs.inventory.worn(&"knight", &"ring_2").id == &"it1", "a third ring replaces ring_1")
	await _key(&"ui_cancel")
	_gs.inventory.set_state([], {})
	Reg.test_items.clear()


func _physics_wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## The hub builds the real screen and the chest opens it for the character being played.
func _hub() -> void:
	for it in [_item("cap", "Iron Cap", "helmet", "A plain cap.")]:
		Reg.test_items.append(it)
	_gs.inventory.set_state([], {})
	_gs.inventory.unlock(&"cap")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(0.5).timeout
	_check(hub.inventory_screen != null and hub.inventory_screen.get_script() == load("res://scripts/ui/inventory_screen.gd"), "the hub builds the real InventoryScreen")
	hub._focus(2, true)
	await _physics_wait(10)
	await _key(&"hub_confirm")
	var p = hub.player
	var hp_before: float = p.health.max_health
	p.global_position = hub.CHEST_POS + Vector2(0, 10)
	hub._lockout = 0.0
	await _physics_wait(3)
	await _key(&"interact")
	_check(hub.inventory_screen.is_open and paused, "interact at the chest opens the real screen over a paused game")
	_check(hub.inventory_screen._title.text == hub.characters[hub.focus_index].display_name, "for the character being played")
	hub.inventory_screen.click(hub.inventory_screen.Zone.GRID, 0)
	await _key(&"ui_cancel")
	_check(not paused and not hub.inventory_screen.is_open, "Esc closes it and the game runs again")
	await _physics_wait(3)
	_check(hub.player != p and is_instance_valid(hub.player), "wearing something rebuilt the hub player")
	hub.queue_free()
	await process_frame
	paused = false

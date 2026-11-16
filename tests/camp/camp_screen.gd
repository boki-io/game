extends SceneTree
## The camp screen (spec 0.7, 7 and 6.4) inside the real hub: Esc and Enter with the camp closed, buy and undo by key
## and by mouse (the buttons' pressed signal), unaffordable and MAX, reset all, row keys ignored while a button has
## focus, Esc closing without opening the pause menu, and the hub rebuilding its Player on close after a change.
## Run: godot --headless --path . --script tests/camp/camp_screen.gd

var _failed := false
var _session: Node
var _closed_args: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _action(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame


func _backspace() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_BACKSPACE
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = InputEventKey.new()
	e.keycode = KEY_BACKSPACE
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame


func _reset_state(gold: int) -> void:
	_session.attribute_levels = {}
	_session.gold = gold


func _init() -> void:
	await process_frame
	await process_frame
	_session = root.get_node("GameSession")
	_session.gold = 1000
	_session.attribute_levels = {}
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	for i in 30:
		await physics_frame
	hub._enter_walk(1, Vector2(480, 300), true)
	await process_frame
	var camp = hub.camp_screen
	var pause_menu: Control = hub.get_node("UI/PauseMenu")
	camp.closed.connect(func(changed: bool) -> void: _closed_args.append(changed))
	var ids: Array = AttributeRegistry.all().map(func(a: AttributeData) -> StringName: return a.id)
	_check(camp != null and camp.get_parent() == hub.get_node("UI"), "the hub builds a CampScreen in its UI layer")
	_check(camp.process_mode == Node.PROCESS_MODE_ALWAYS, "the camp screen is Always-processing")
	_check(not camp.visible and not camp.is_open, "the camp is closed at first")

	# Closed: Esc opens the PauseMenu, Enter buys nothing.
	await _action(&"ui_accept")
	_check(_session.attribute_levels.is_empty() and _session.gold == 1000, "Enter with the camp closed buys nothing")
	await _action(&"pause")
	_check(pause_menu.visible and paused, "Esc with the camp closed opens the PauseMenu")
	await _action(&"pause")
	_check(not pause_menu.visible and not paused, "Esc again closes it")

	# Open: eight rows, paused.
	var old_player = hub.player
	camp.open()
	await process_frame
	_check(paused and camp.visible and camp.is_open, "the tree is paused while the camp is open")
	_check(camp._rows.size() == 8 and camp.attributes.size() == 8, "a row for each of the eight attributes")
	for i in 8:
		_check(camp._summaries[i].text.contains("->"), "row %d shows current and next" % i)
		_check(camp._levels[i].text == "Lv 0/7", "row %d level text" % i)
	_check(camp.selected_row == 0, "selected_row is 0 on open")
	_check(camp.gold_counter.shown == 1000, "the header counter shows the gold")
	_check(camp._minus[0].disabled, "minus is disabled at level 0")
	_check(camp._costs[0].text == "40 gold", "next cost shown")

	# Buy and undo by key.
	await _action(&"ui_accept")
	_check(_session.level_of(ids[0]) == 1 and _session.gold == 960, "Enter buys level 1 of the selected row")
	_check(camp.last_sound == &"hub_choose", "a buy plays hub_choose")
	_check(camp._levels[0].text == "Lv 1/7" and camp.gold_counter.shown == 960, "row and counter update")
	await _action(&"ui_down")
	_check(camp.selected_row == 1, "Down selects the next row")
	await _action(&"ui_accept")
	_check(_session.level_of(ids[1]) == 1, "Enter buys on the second row")
	await _action(&"ui_left")
	_check(_session.level_of(ids[1]) == 0 and camp.last_sound == &"menu_click", "Left undoes and plays menu_click")
	await _action(&"ui_up")
	_check(camp.selected_row == 0, "Up goes back")
	await _action(&"ui_up")
	_check(camp.selected_row == 0, "Up clamps at the top")
	await _backspace()
	_check(_session.level_of(ids[0]) == 0 and _session.gold == 1000, "Backspace undoes and refunds exactly")

	# Buy and undo by mouse (the buttons' pressed signal).
	camp._plus[2].pressed.emit()
	_check(_session.level_of(ids[2]) == 1 and camp.selected_row == 2, "clicking plus buys and selects the row")
	camp._minus[2].pressed.emit()
	_check(_session.level_of(ids[2]) == 0 and _session.gold == 1000, "clicking minus undoes")

	# Unaffordable: dimmed, red cost, no_mana, nothing bought.
	_reset_state(10)
	camp._refresh()
	_check(camp._plus[0].modulate.a < 1.0 and not camp._plus[0].disabled, "unaffordable plus is dimmed, not disabled")
	_check(camp._costs[0].get_theme_color("font_color") == camp.COST_RED, "the unaffordable price is red")
	camp.last_sound = &""
	camp._plus[0].pressed.emit()
	_check(camp.last_sound == &"no_mana" and _session.level_of(ids[0]) == 0 and _session.gold == 10,
		"unaffordable click gives no_mana and buys nothing")
	camp.selected_row = 0
	await _action(&"ui_accept")
	_check(_session.level_of(ids[0]) == 0, "Enter does not buy what is unaffordable")

	# MAX.
	_reset_state(100000)
	_session.attribute_levels = {ids[0]: 7}
	camp._refresh()
	_check(camp._plus[0].disabled and camp._costs[0].text == "MAX", "MAX at level 7: plus disabled")
	camp.last_sound = &""
	await _action(&"ui_accept")
	_check(camp.last_sound == &"" and _session.level_of(ids[0]) == 7, "MAX is silent and buys nothing")

	# Reset all refunds.
	_reset_state(1000)
	camp._refresh()
	camp._plus[0].pressed.emit()
	camp._plus[3].pressed.emit()
	_check(_session.spent_total() > 0, "bought something")
	camp.reset_button.pressed.emit()
	_check(_session.spent_total() == 0 and _session.gold == 1000, "Reset all refunds everything")

	# Row keys are ignored while Reset has focus.
	_session.attribute_levels = {ids[7]: 2}
	_session.gold = 500
	camp._refresh()
	camp.selected_row = 7
	await _action(&"ui_down")
	_check(camp.reset_button.has_focus(), "Down from the last row focuses Reset all")
	await _action(&"ui_left")
	_check(_session.level_of(ids[7]) == 2, "Left with Reset focused does not undo")
	await _backspace()
	_check(_session.level_of(ids[7]) == 2, "Backspace with Reset focused does not undo")
	await _action(&"ui_right")
	_check(camp.close_button.has_focus(), "Right moves focus to Close")
	await _action(&"ui_left")
	_check(camp.reset_button.has_focus(), "Left moves focus back to Reset")
	await _action(&"ui_accept")
	_check(_session.level_of(ids[7]) == 0 and _session.gold == 500 + 40 + 60,
		"Enter on Reset presses Reset (and buys nothing)")
	await _action(&"ui_up")
	_check(not camp.buttons_have_focus() and camp.selected_row == 7, "Up returns to the last row")

	# Esc closes, leaves the pause menu hidden, and a change rebuilds the Player.
	_reset_state(1000)
	camp._refresh()
	await _action(&"ui_accept")
	_check(_session.level_of(ids[camp.selected_row]) == 1, "bought before closing")
	_closed_args.clear()
	await _action(&"pause")
	_check(not camp.is_open and not camp.visible and not paused, "Esc closes the camp and unpauses")
	_check(not pause_menu.visible, "Esc with the camp open does not open the PauseMenu")
	_check(_closed_args == [true], "closed(true) after a change")
	_check(is_instance_valid(hub.player) and hub.player != old_player, "the hub rebuilt its Player")
	_check(hub.player.position == Vector2(480, 300), "the new Player is at the same position")
	_check(hub._lockout > 0.0, "the hub lockout is set on close")
	if "attribute_levels" in hub.player:
		_check(hub.player.attribute_levels == _session.attribute_levels, "the Player got the camp levels")
	# (Without a Player.attribute_levels property, i.e. before the effects step, the levels assertion is skipped.)

	# No change: closed(false) and the same Player.
	var kept = hub.player
	camp.open()
	await process_frame
	_closed_args.clear()
	camp._plus[0].pressed.emit()
	camp._minus[0].pressed.emit()
	await _action(&"ui_cancel")
	_check(_closed_args == [false] and hub.player == kept, "no net change: closed(false), Player kept")

	# Open handlers do nothing while closed.
	_session.gold = 1000
	await _action(&"ui_down")
	await _action(&"ui_accept")
	_check(camp.selected_row == 0 and _session.gold == 1000, "a closed camp ignores keys")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

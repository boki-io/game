extends SceneTree
## The stage select screen: card states per column, the cursor (skips locked cards, wraps), keyboard and mouse
## picking, the abandon prompt, and ignoring input while a fade runs.
## Run: godot --headless --path . --script tests/select_screen.gd

var _failed := false
var _loaded: Array[String] = []
var _gs: Node
var _fader: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	await process_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame


func _states(screen: Node, column: int) -> Array:
	return screen.cards[column].map(func(c) -> int: return c.state)


func _idle() -> void:
	for i in 200:
		if not _fader.busy:
			return
		await physics_frame


func _open(seed_value: int, column: int, beaten: Array) -> Node:
	_gs.new_run(CharacterRegistry.all()[0], seed_value)
	for row in beaten:
		_gs.beaten.append(row)
	_gs.current_column = column
	var screen: Node = load("res://scenes/select.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	return screen


func _init() -> void:
	await process_frame
	await process_frame
	_gs = root.get_node("GameSession")
	_fader = root.get_node("SceneFader")
	_gs.scene_hook = func(p: String) -> void: _loaded.append(p)
	await _idle()
	var A := 1  # StageCard.State.AVAILABLE
	var B := 0
	var L := 2

	# Column 1: all three available, everything later locked; the cursor starts on the first card.
	var screen := _open(5, 0, [])
	await process_frame
	_check(screen.cards.size() == 3 and screen.cards[0].size() == 3 and screen.cards[1].size() == 3 and screen.cards[2].size() == 1,
		"7 cards in 3 columns")
	_check(_states(screen, 0) == [A, A, A], "column 1: all available")
	_check(_states(screen, 1) == [L, L, L] and _states(screen, 2) == [L], "later columns locked")
	_check(screen.focus_index == 0 and screen.focused_card() == screen.cards[0][0], "cursor starts on the first available card")
	await _press(&"ui_down")
	_check(screen.focus_index == 1, "ui_down moves the cursor")
	await _press(&"move_down")
	_check(screen.focus_index == 2, "move_down (S) moves the cursor")
	await _press(&"ui_down")
	_check(screen.focus_index == 0, "the cursor wraps from the bottom")
	await _press(&"ui_up")
	_check(screen.focus_index == 2, "ui_up wraps from the top")
	await _press(&"move_up")
	_check(screen.focus_index == 1, "move_up (W)")

	# Mouse: hovering an available card moves the cursor; a click on a locked card does nothing.
	screen.cards[0][2].hovered.emit(screen.cards[0][2])
	_check(screen.focus_index == 2, "hover moves the cursor")
	screen.cards[1][0].chosen.emit(screen.cards[1][0])
	_check(_loaded.is_empty(), "a locked card cannot be chosen")

	# Esc opens the abandon prompt, which blocks the screen until dismissed; No keeps the run.
	await _press(&"pause")
	_check(screen.get_node("UI/AbandonPrompt").visible, "Esc opens the abandon prompt")
	await _press(&"hub_confirm")
	_check(_loaded.is_empty(), "confirm is ignored while the prompt is open")
	await _press(&"pause")
	_check(not screen.get_node("UI/AbandonPrompt").visible and _gs.path != null, "Esc closes the prompt and keeps the run")
	screen.get_node("UI/AbandonPrompt").open()
	for b in screen.get_node("UI/AbandonPrompt").find_children("*", "Button", true, false):
		if b.text == "Yes":
			b.pressed.emit()
	_check(_loaded == [_gs.HUB] and _gs.path == null, "Yes abandons: hub, path discarded")
	_loaded.clear()
	screen.free()

	# Confirm starts the focused stage.
	screen = _open(5, 0, [])
	await process_frame
	await _press(&"ui_down")
	var picked = screen.focused_card().stage
	await _press(&"hub_confirm")
	_check(_loaded == [_gs.RUN] and _gs.current_stage == picked, "confirm starts the focused stage")
	_loaded.clear()
	screen.free()

	# A click starts a stage.
	screen = _open(5, 0, [])
	await process_frame
	screen.cards[0][1].chosen.emit(screen.cards[0][1])
	_check(_loaded == [_gs.RUN] and _gs.current_stage == screen.cards[0][1].stage, "a click starts the stage")
	_loaded.clear()
	screen.free()

	# Column 2 after beating each column 1 stage: only the connected two are available and the beaten one is marked.
	for beaten_row in 3:
		screen = _open(5, 1, [beaten_row])
		await process_frame
		var expected: Array = _gs.path.next_rows(0, beaten_row)
		var states: Array = _states(screen, 1)
		var available_rows := []
		for r in 3:
			if states[r] == A:
				available_rows.append(r)
		_check(available_rows == expected, "after column-1 row %d: available %s (expected %s)" % [beaten_row, available_rows, expected])
		_check(states.count(L) == 1, "exactly one locked card in column 2")
		_check(_states(screen, 0)[beaten_row] == B and _states(screen, 0).count(B) == 1, "the beaten stage is marked")
		_check(screen.focused_card() == screen.cards[1][expected[0]], "the cursor starts on the first available card")
		_check(_states(screen, 2) == [L], "the final stage is still locked")
		# The cursor skips the locked card.
		await _press(&"ui_down")
		_check(screen.focused_card() == screen.cards[1][expected[1]], "the cursor skips the locked card")
		await _press(&"ui_down")
		_check(screen.focused_card() == screen.cards[1][expected[0]], "and wraps over it")
		screen.free()

	# Column 3: one card, available, with the two earlier picks beaten.
	screen = _open(5, 2, [1, 1])
	await process_frame
	_check(_states(screen, 2) == [A], "the final stage is available")
	await _press(&"ui_down")
	_check(screen.focus_index == 0, "one card: the cursor stays")
	screen.free()

	# While a fade runs the screen ignores input.
	screen = _open(5, 0, [])
	await process_frame
	_fader.busy = true
	await _press(&"hub_confirm")
	await _press(&"pause")
	_check(_loaded.is_empty() and not screen.get_node("UI/AbandonPrompt").visible, "input ignored while the fader is busy")
	_fader.busy = false
	screen.free()

	_gs.scene_hook = Callable()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

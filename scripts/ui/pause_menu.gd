extends Control
## Esc / Start pauses with Continue and Exit. Ignored while the level-up or end screen is up.

@export var level_up_menu: LevelUpMenu
@export var end_screen: Control

var _continue: Button


func _ready() -> void:
	visible = false
	add_child(UiKit.dim(0.6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiKit.label("PAUSED", 16))
	_continue = UiKit.button("Continue")
	_continue.pressed.connect(_resume)
	box.add_child(_continue)
	var menu := UiKit.button("Main Menu")
	menu.pressed.connect(GameSession.go_to_main_menu)
	box.add_child(menu)
	var exit := UiKit.button("Exit")
	exit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(exit)
	add_child(UiKit.centered(box))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if visible:
		_resume()
	elif not get_tree().paused and not (level_up_menu and level_up_menu.active) and not end_screen.visible:
		visible = true
		get_tree().paused = true
		_continue.grab_focus.call_deferred()
	get_viewport().set_input_as_handled()


func _resume() -> void:
	visible = false
	get_tree().paused = false

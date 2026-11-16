class_name AbandonPrompt
extends Control
## "Abandon this run?" with Yes / No. Yes calls GameSession.abandon_run(). Used by the stage pause menu and by
## the select screen. Esc or No closes it. It works while the tree is paused.

signal dismissed

var _no: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.7))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiKit.label("Abandon this run?", 12))
	var yes := UiKit.button("Yes")
	yes.pressed.connect(_on_yes)
	box.add_child(yes)
	_no = UiKit.button("No")
	_no.pressed.connect(close)
	box.add_child(_no)
	add_child(UiKit.centered(box))


func open() -> void:
	visible = true
	_no.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	dismissed.emit()


func _on_yes() -> void:
	visible = false
	GameSession.abandon_run()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not SceneFader.busy and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()

extends Control
## First screen: Start New Game and Exit.


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14161e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiKit.label("HERO HORDE", 24, Color("ffd866")))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)
	var start := UiKit.button("Start New Game", Vector2(110, 20))
	start.pressed.connect(GameSession.go_to_character_select)
	box.add_child(start)
	var exit := UiKit.button("Exit", Vector2(110, 20))
	exit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(exit)
	add_child(UiKit.centered(box))

	var version := UiKit.label("v0.2", 8, Color(1, 1, 1, 0.35))
	version.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	version.offset_top = -14
	add_child(version)

	start.grab_focus.call_deferred()

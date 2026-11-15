class_name UiKit
extends RefCounted
## Small helpers so menus built in code look consistent at 480x270.

const FONT_SIZE := 8


static func label(text: String, size: int = FONT_SIZE, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_size: Vector2 = Vector2(80, 18)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(func() -> void: Audio.play(&"menu_click"))
	return b


## Full-screen dim layer; swallows mouse input behind a menu.
static func dim(alpha: float = 0.6) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, alpha)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	return d


static func centered(content: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(content)
	return c


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]

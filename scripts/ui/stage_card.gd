class_name StageCard
extends Control
## One stage on the select screen: thumbnail, name, tier and the four modifiers. Drawn from one canvas item.
## States: BEATEN (dimmed, check mark), AVAILABLE (bright, selectable), LOCKED (dim, not selectable).

signal hovered(card: StageCard)
signal chosen(card: StageCard)

enum State { BEATEN, AVAILABLE, LOCKED }

const CARD_SIZE := Vector2(160, 80)
const THUMB_SIZE := Vector2(64, 40)
const GOOD := Color("7be08a")
const BAD := Color("ff6a6a")
const TIER_COLORS := [Color("7be08a"), Color("e8e8e8"), Color("ff8a5a")]

var stage: StageData
var column := 0
var row := 0
var state := State.LOCKED:
	set(v):
		state = v
		modulate = Color(0.55, 0.55, 0.55) if v == State.BEATEN else (Color(0.42, 0.42, 0.42) if v == State.LOCKED else Color.WHITE)
		queue_redraw()
var focused := false:
	set(v):
		focused = v
		queue_redraw()


func setup(data: StageData, col: int, r: int) -> void:
	stage = data
	column = col
	row = r
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		if state == State.AVAILABLE:
			hovered.emit(self))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT and state == State.AVAILABLE:
		chosen.emit(self)
		accept_event()


func left_middle() -> Vector2:
	return position + Vector2(0, CARD_SIZE.y / 2.0)


func right_middle() -> Vector2:
	return position + Vector2(CARD_SIZE.x, CARD_SIZE.y / 2.0)


## "+15%", "-10%" or "0%".
static func signed_percent(value: int) -> String:
	return "%+d%%" % value if value != 0 else "0%"


## Tint of a modifier row. `harder_when_positive`: Population and Difficulty (red when they rise, green when they
## fall); otherwise Experience and Gold (green when they rise, red when they fall). Zero stays white.
static func modifier_color(value: int, harder_when_positive: bool) -> Color:
	if value == 0:
		return Color.WHITE
	return BAD if (value > 0) == harder_when_positive else GOOD


func _draw() -> void:
	if stage == null:
		return
	var font := ThemeDB.fallback_font
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	draw_rect(rect, Color("1d1914", 0.92))
	var border := Color("ffd866") if focused else Color("5a4d3c")
	draw_rect(rect, border, false, 2.0 if focused else 1.0)
	_text(font, Vector2(6, 12), stage.name, 8, HORIZONTAL_ALIGNMENT_LEFT, 100.0, Color.WHITE)
	_text(font, Vector2(CARD_SIZE.x - 106, 12), stage.tier_name(), 8, HORIZONTAL_ALIGNMENT_RIGHT, 100.0, TIER_COLORS[stage.tier])
	var thumb := Rect2(Vector2(6, 20), THUMB_SIZE)
	if stage.thumbnail:
		draw_texture_rect(stage.thumbnail, thumb, false)
	else:
		draw_rect(thumb, Color("33291e"))
	draw_rect(thumb, Color(0, 0, 0, 0.6), false, 1.0)
	var rows := [
		["Population", stage.population, true],
		["Difficulty", stage.difficulty, true],
		["Experience", stage.experience, false],
		["Gold", stage.currency, false],
	]
	for i in rows.size():
		var y := 29.0 + 10.0 * i
		var value: int = rows[i][1]
		_text(font, Vector2(76, y), rows[i][0], 8, HORIZONTAL_ALIGNMENT_LEFT, 50.0, Color("c8c0b0"))
		_text(font, Vector2(CARD_SIZE.x - 36, y), signed_percent(value), 8, HORIZONTAL_ALIGNMENT_RIGHT, 32.0,
			modifier_color(value, rows[i][2]))
	if state == State.BEATEN:
		var c := thumb.get_center()
		draw_polyline(PackedVector2Array([c + Vector2(-9, 0), c + Vector2(-3, 7), c + Vector2(10, -8)]), Color("7be08a"), 3.0)


func _text(font: Font, pos: Vector2, text: String, size: int, align: HorizontalAlignment, width: float, color: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), text, align, width, size, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, align, width, size, color)

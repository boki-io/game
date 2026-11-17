class_name HubInfoPanel
extends PanelContainer
## The hub's info panel: name, description, stats, trait and the four abilities of one character,
## plus a Choose button. Every number comes from CharacterData / AbilityData.

signal choose_pressed

const WIDTH := 270.0
const SLOTS := [
	{key = "Auto", color = Color("e8e8e8")},
	{key = "Q", color = Color("6cb4ff")},
	{key = "E", color = Color("7be08a")},
	{key = "R", color = Color("ff9a4a")},
]

var character: CharacterData
var name_label: Label
var description_label: Label
var stats_label: Label
var trait_label: Label
var ability_stat_labels: Array[Label] = []

var _rows: VBoxContainer
var _choose: Button


## A number without trailing zeros: 100 -> "100", 0.65 -> "0.65".
static func num(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 2)


## "HP 100   Speed 90   Mana 100   Regen 8/s" ("HP 85   Speed 95" without mana).
static func stats_text(c: CharacterData) -> String:
	if not c.uses_mana:
		return "HP %s   Speed %s" % [num(c.max_hp), num(c.move_speed)]
	return "HP %s   Speed %s   Mana %s   Regen %s/s" % [
		num(c.max_hp), num(c.move_speed), num(c.max_mana),
		num(c.mana_regen)]


## "Cooldown 0.65s   Mana 20   Damage 12" (no mana part for free abilities).
static func ability_stats_text(a: AbilityData) -> String:
	var text := "Cooldown %ss" % num(a.cooldown)  # 0.65 and 1.8 both print exactly
	if a.mana_cost > 0.0:
		text += "   Mana %s" % num(a.mana_cost)
	text += "   Damage %s" % num(a.damage)
	return text


static func trait_text(c: CharacterData) -> String:
	if c.trait_name.is_empty():
		return "Trait: none"
	return "Trait: %s. %s" % [c.trait_name, c.trait_description]


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	style.border_color = Color("e0c060")
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	name_label = _left_label(14, Color("ffd866"))
	box.add_child(name_label)
	description_label = _left_label(8, Color(1, 1, 1, 0.75))
	box.add_child(description_label)
	stats_label = _left_label(8, Color(0.6, 0.75, 1.0))
	box.add_child(stats_label)
	trait_label = _left_label(8, Color("c9a0ff"))
	box.add_child(trait_label)
	box.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	box.add_child(_rows)
	_choose = UiKit.button("Choose", Vector2(0, 20))
	_choose.focus_mode = Control.FOCUS_NONE  # Enter / South are handled once, by the hub
	_choose.pressed.connect(choose_pressed.emit)
	box.add_child(_choose)


func show_character(c: CharacterData) -> void:
	character = c
	name_label.text = c.display_name
	description_label.text = c.description
	stats_label.text = stats_text(c)
	trait_label.text = trait_text(c)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	ability_stat_labels.clear()
	var abilities := [c.ability_auto, c.ability_q, c.ability_e, c.ability_r]
	for i in SLOTS.size():
		if abilities[i]:
			_rows.add_child(_ability_row(SLOTS[i].key, SLOTS[i].color, abilities[i]))
	size = Vector2(WIDTH, 0)  # shrink back to fit the new content


func _ability_row(key: String, color: Color, data: AbilityData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if data.icon:
		var icon := TextureRect.new()
		icon.texture = data.icon
		icon.custom_minimum_size = data.icon.get_size()
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
	var text_width := WIDTH - 16.0 - 6.0 - (data.icon.get_size().x if data.icon else 0.0)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(_left_label(8, color, "[%s] %s" % [key, data.display_name], text_width))
	var stats := _left_label(8, Color(0.6, 0.75, 1.0), ability_stats_text(data), text_width)
	ability_stat_labels.append(stats)
	text.add_child(stats)
	text.add_child(_left_label(8, Color(1, 1, 1, 0.7), data.description, text_width))
	row.add_child(text)
	return row


## A left-aligned, wrapping label. Wrapped labels need a minimum width or they collapse to one column.
func _left_label(size_px: int, color: Color, text: String = "", width: float = WIDTH - 16.0) -> Label:
	var l := UiKit.label(text, size_px, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l

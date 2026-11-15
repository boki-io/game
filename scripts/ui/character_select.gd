extends Control
## Shows the character large with their abilities (numbers read from AbilityData).
## Prev/Next appear only when there is more than one character.

const PREVIEW_SCALE := 3.0
const PLACEHOLDER_SPRITE := preload("res://scripts/player/placeholder_sprite.gd")
const SLOTS := [
	{key = "Auto", color = Color("e8e8e8")},
	{key = "Q", color = Color("6cb4ff")},
	{key = "E", color = Color("7be08a")},
	{key = "R", color = Color("ff9a4a")},
]

var _characters: Array[CharacterData] = []
var _index := 0

var _preview: Node2D
var _name: Label
var _description: Label
var _rows: VBoxContainer
var _prev: Button
var _next: Button


func _ready() -> void:
	_characters = CharacterRegistry.all()
	_build()
	_show_character(0)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14161e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(UiKit.label("SELECT CHARACTER", 16, Color("ffd866")))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_build_character_panel())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_rows)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)
	var back := UiKit.button("Back", Vector2(80, 20))
	back.pressed.connect(GameSession.go_to_main_menu)
	buttons.add_child(back)
	var select := UiKit.button("Select", Vector2(80, 20))
	select.pressed.connect(func() -> void: GameSession.start_game(_characters[_index]))
	buttons.add_child(select)
	select.grab_focus.call_deferred()


func _build_character_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(150, 0)
	panel.add_theme_constant_override("separation", 4)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150, 92)
	panel.add_child(holder)
	_preview = Node2D.new()
	_preview.set_script(PLACEHOLDER_SPRITE)
	_preview.position = Vector2(75, 80)
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview.show_aim = false
	holder.add_child(_preview)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_prev = UiKit.button("<", Vector2(16, 16))
	_prev.pressed.connect(_switch.bind(-1))
	name_row.add_child(_prev)
	_name = UiKit.label("", 12)
	_name.custom_minimum_size = Vector2(100, 0)
	name_row.add_child(_name)
	_next = UiKit.button(">", Vector2(16, 16))
	_next.pressed.connect(_switch.bind(1))
	name_row.add_child(_next)
	panel.add_child(name_row)
	var multiple := _characters.size() > 1
	_prev.visible = multiple
	_next.visible = multiple

	_description = UiKit.label("", 8, Color(1, 1, 1, 0.75))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(150, 0)
	panel.add_child(_description)
	return panel


func _switch(step: int) -> void:
	_show_character(posmod(_index + step, _characters.size()))


func _show_character(index: int) -> void:
	_index = index
	var c := _characters[index]
	_preview.body_color = c.body_color
	_preview.queue_redraw()
	_name.text = c.display_name
	_description.text = c.description
	for child in _rows.get_children():
		child.queue_free()
	var abilities := [c.ability_auto, c.ability_q, c.ability_e, c.ability_r]
	for i in SLOTS.size():
		if abilities[i]:
			_rows.add_child(_ability_row(SLOTS[i].key, SLOTS[i].color, abilities[i]))


func _ability_row(key: String, color: Color, data: AbilityData) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var title := UiKit.label("[%s] %s" % [key, data.display_name], 8, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(title)
	var stats := "Cooldown %.1fs" % data.cooldown
	if data.mana_cost > 0.0:
		stats += "   Mana %d" % roundi(data.mana_cost)
	stats += "   Damage %d" % roundi(data.damage)
	var stat_label := UiKit.label(stats, 8, Color(0.6, 0.75, 1.0))
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(stat_label)
	var desc := UiKit.label(data.description, 8, Color(1, 1, 1, 0.7))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)
	return row

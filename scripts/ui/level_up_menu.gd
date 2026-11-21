class_name LevelUpMenu
extends Control
## Pauses the game and offers 3 random upgrades. Pick with mouse, keys 1/2/3, or D-pad + confirm.
## Level-ups that arrive while the menu is open (or from several players) are queued.

const TABLET := preload("res://assets/ui/stone_tablet.png")
const TABLET_FOCUS := preload("res://assets/ui/stone_tablet_focus.png")
const TABLET_TEXT := Color("e8dcc8")

var active := false

var _queue: Array[Player] = []
var _player: Player
var _choices: Array[LevelUpChoice] = []
var _title: Label
var _row: HBoxContainer


func _ready() -> void:
	visible = false
	add_child(UiKit.dim(0.65))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_title = UiKit.label("LEVEL UP!", 16, Color("ffd866"))
	box.add_child(_title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	box.add_child(_row)
	add_child(UiKit.centered(box))


## Drops the queued level-ups and closes the menu if it is open (the overworld's respawn). The tree is unpaused.
func dismiss() -> void:
	_queue.clear()
	if active:
		_close()


func queue_level_up(player: Player) -> void:
	_queue.append(player)
	if not active:
		_show_next()


func _show_next() -> void:
	while not _queue.is_empty():
		_player = _queue.pop_front()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([GameSession.path_seed, _player.xp.level, Time.get_ticks_usec() if GameSession.path_seed == 0 else 0])
		_choices = LevelUpRoller.roll(_player, 3, rng)
		if not _choices.is_empty():
			_open()
			return
	_close()


func _open() -> void:
	active = true
	visible = true
	get_tree().paused = true
	Audio.play(&"level_up")
	for child in _row.get_children():
		child.queue_free()
	var first: Button
	for i in _choices.size():
		var u := _choices[i]
		var b := UiKit.button("[%d] %s\n%s\n\n%s\n%s" % [i + 1, u.title, u.tag,
			u.description, u.level_text()], Vector2(120, 84))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_tablet(b)
		b.pressed.connect(_pick.bind(i))
		_row.add_child(b)
		if first == null:
			first = b
	first.grab_focus.call_deferred()


## Cracked, bloodied stone tablet instead of the default grey button.
static func _tablet_box(tex: Texture2D) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 12)
		sb.set_content_margin(side, 12)
	return sb


static func _style_tablet(b: Button) -> void:
	var normal := _tablet_box(TABLET)
	var lit := _tablet_box(TABLET_FOCUS)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("pressed", lit)
	# The focus glow only shows once a key or D-pad is used (_input), so the card focused on open is not lit for mouse players.
	b.add_theme_stylebox_override("focus", normal)
	b.set_meta(&"lit", lit)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(c, TABLET_TEXT)
	b.add_theme_color_override("font_outline_color", Color("15120f"))
	b.add_theme_constant_override("outline_size", 2)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if (event is InputEventKey and event.pressed) or event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		for b in _row.get_children():
			if b is Button and b.has_meta(&"lit"):
				b.add_theme_stylebox_override("focus", b.get_meta(&"lit"))


func _pick(index: int) -> void:
	if not active or index >= _choices.size():
		return
	_choices[index].apply.call()
	_show_next()


func _close() -> void:
	active = false
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1:
			_pick(0)
		KEY_2:
			_pick(1)
		KEY_3:
			_pick(2)

class_name LevelUpMenu
extends Control
## Pauses the game and offers 3 random upgrades. Pick with mouse, keys 1/2/3, or D-pad + confirm.
## Level-ups that arrive while the menu is open (or from several players) are queued.

var active := false

var _queue: Array[Player] = []
var _player: Player
var _choices: Array[UpgradeData] = []
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


func queue_level_up(player: Player) -> void:
	_queue.append(player)
	if not active:
		_show_next()


func _show_next() -> void:
	while not _queue.is_empty():
		_player = _queue.pop_front()
		_choices = _player.upgrades.roll(3)
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
		var lv := _player.upgrades.level_of(u)
		var b := UiKit.button("[%d] %s\n%s\n\n%s\nLv %d -> %d" % [i + 1, u.display_name, u.tag.to_upper(),
			u.description, lv, lv + 1], Vector2(120, 84))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_pick.bind(i))
		_row.add_child(b)
		if first == null:
			first = b
	first.grab_focus.call_deferred()


func _pick(index: int) -> void:
	if not active or index >= _choices.size():
		return
	_player.upgrades.apply(_choices[index])
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

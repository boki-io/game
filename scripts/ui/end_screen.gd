extends Control
## Win ("Survived!") or lose ("You died") with time survived, level and kills, and Restart.

var run_manager: RunManager

var _title: Label
var _stats: Label
var _restart: Button


func _ready() -> void:
	visible = false
	add_child(UiKit.dim(0.65))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_title = UiKit.label("", 16)
	box.add_child(_title)
	_stats = UiKit.label("")
	box.add_child(_stats)
	_restart = UiKit.button("Restart")
	_restart.pressed.connect(_on_restart)
	box.add_child(_restart)
	add_child(UiKit.centered(box))


func show_result(won: bool) -> void:
	var level := 1
	if not PlayerRegistry.players.is_empty():
		level = PlayerRegistry.players[0].xp.level
	_title.text = "Survived!" if won else "You died"
	_title.add_theme_color_override("font_color", Color("7be08a") if won else Color("ff6060"))
	_stats.text = "Time survived  %s\nLevel  %d\nKills  %d" % [
		UiKit.format_time(run_manager.elapsed), level, run_manager.kills]
	visible = true
	get_tree().paused = true
	_restart.grab_focus.call_deferred()


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

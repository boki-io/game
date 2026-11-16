class_name EndScreen
extends Control
## The end of a run: DEATH ("You died", stage reached, kills in it, time, level) or VICTORY ("Victory!", stages
## cleared, total kills, gold earned, final level). Return to Hub is the only button.

enum Mode { DEATH, VICTORY }

var run_manager: RunManager

var _mode := Mode.DEATH
var _title: Label
var _stats: Label
var _hub: Button


func _ready() -> void:
	visible = false
	add_child(UiKit.dim(0.65))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_title = UiKit.label("", 16)
	box.add_child(_title)
	_stats = UiKit.label("")
	box.add_child(_stats)
	_hub = UiKit.button("Return to Hub")
	_hub.pressed.connect(_return_to_hub)
	box.add_child(_hub)
	add_child(UiKit.centered(box))


func show_result(mode: Mode) -> void:
	_mode = mode
	var won := mode == Mode.VICTORY
	_title.text = "Victory!" if won else "You died"
	_title.add_theme_color_override("font_color", Color("7be08a") if won else Color("ff6060"))
	if won:
		var summary: Dictionary = GameSession.run_summary
		_stats.text = "Stages cleared  %d of 3\nTotal kills  %d\nGold earned  %d\nFinal level  %d" % [
			summary.get("stages_cleared", 0), summary.get("kills", 0), summary.get("gold_earned", 0),
			summary.get("level", 1)]
	else:
		var level := 1
		if not PlayerRegistry.players.is_empty():
			level = PlayerRegistry.players[0].xp.level
		_stats.text = "Stage reached  %d\nKills in this stage  %d\nTime survived  %s\nLevel  %d" % [
			GameSession.current_column + 1, run_manager.kills, UiKit.format_time(run_manager.elapsed), level]
	visible = true
	get_tree().paused = true
	_hub.grab_focus.call_deferred()


func _return_to_hub() -> void:
	if _mode == Mode.DEATH:
		GameSession.fail_run()
	else:
		GameSession.go_to_hub()

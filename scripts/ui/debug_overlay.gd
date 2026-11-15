extends Label
## F3 toggles: mana, cooldowns, kills per minute, enemy count and FPS.

var run_manager: RunManager
var spawn_director: SpawnDirector


func _ready() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible or PlayerRegistry.players.is_empty():
		return
	var p: Player = PlayerRegistry.players[0]
	var minutes := maxf(run_manager.elapsed / 60.0, 0.01)
	var cds := ""
	for slot: StringName in [&"q", &"e", &"r"]:
		cds += " %s %.1f" % [String(slot).to_upper(), p.caster.cooldowns[slot]]
	text = "MP %d/%d   CD%s\nkills/min %.0f   enemies %d   %d fps" % [
		p.mana.current, p.mana.max_mana(), cds, run_manager.kills / minutes,
		spawn_director.alive, Engine.get_frames_per_second()]

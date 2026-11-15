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
	if not visible:
		return
	if PlayerRegistry.players.is_empty():
		text = "%d fps" % Engine.get_frames_per_second()
		return
	var p: Player = PlayerRegistry.players[0]
	var cds := ""
	for slot: StringName in [&"q", &"e", &"r"]:
		cds += " %s %.1f" % [String(slot).to_upper(), p.caster.cooldowns[slot]]
	if run_manager == null or spawn_director == null:
		# The hub has no run: just mana, cooldowns and fps.
		text = "MP %d/%d   CD%s\n%d fps" % [p.mana.current, p.mana.max_mana(), cds, Engine.get_frames_per_second()]
		return
	var minutes := maxf(run_manager.elapsed / 60.0, 0.01)
	var types := ""
	for id: StringName in spawn_director.alive_by_type:
		types += " %s %d" % [id, spawn_director.alive_by_type[id]]
	text = "MP %d/%d   CD%s\nkills/min %.0f   enemies %d (%s )   %d fps" % [
		p.mana.current, p.mana.max_mana(), cds, run_manager.kills / minutes,
		spawn_director.alive, types.strip_edges(), Engine.get_frames_per_second()]

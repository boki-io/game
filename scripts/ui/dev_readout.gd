extends Label
## Placeholder dev readout until the real HUD (M6) and F3 debug overlay exist.

var run_manager: RunManager
var spawn_director: SpawnDirector


func _process(_delta: float) -> void:
	var player: Player = PlayerRegistry.players[0] if not PlayerRegistry.players.is_empty() else null
	var hp := "-" if player == null else "%d/%d" % [player.health.current, player.health.max_health]
	var remaining := maxf(RunManager.RUN_DURATION - run_manager.elapsed, 0.0)
	var mp := "-"
	var cds := ""
	if player:
		mp = "%d/%d" % [player.mana.current, player.mana.max_mana()]
		for slot: StringName in [&"q", &"e", &"r"]:
			cds += " %s %.1f" % [slot.to_upper(), player.caster.cooldowns[slot]]
	text = "HP %s  MP %s %s\n%d:%02d   enemies %d   kills %d   %d fps" % [
		hp, mp, cds, int(remaining) / 60, int(remaining) % 60, spawn_director.alive, run_manager.kills, Engine.get_frames_per_second()]

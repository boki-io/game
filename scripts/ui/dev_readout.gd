extends Label
## Placeholder dev readout until the real HUD (M6) and F3 debug overlay exist.

var run_manager: RunManager
var spawn_director: SpawnDirector


func _process(_delta: float) -> void:
	var player: Player = PlayerRegistry.players[0] if not PlayerRegistry.players.is_empty() else null
	var hp := "-" if player == null else "%d/%d" % [player.health.current, player.health.max_health]
	var remaining := maxf(RunManager.RUN_DURATION - run_manager.elapsed, 0.0)
	text = "HP %s   %d:%02d   enemies %d   %d fps" % [
		hp, int(remaining) / 60, int(remaining) % 60, spawn_director.alive, Engine.get_frames_per_second()]

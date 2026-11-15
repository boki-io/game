class_name RunManager
extends Node

signal run_ended(won: bool)

const RUN_DURATION := 300.0  # seconds

var elapsed := 0.0
var kills := 0
var running := true


func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if elapsed >= RUN_DURATION:
		elapsed = RUN_DURATION
		_end(true)


func on_player_died() -> void:
	if running and PlayerRegistry.all_dead():
		_end(false)


func _end(won: bool) -> void:
	running = false
	run_ended.emit(won)

class_name StageBanner
extends Control
## "Stage cleared" between a won stage and the select screen. No buttons: main.gd shows it for a couple of
## seconds while the game is paused, then moves on.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.5))
	add_child(UiKit.centered(UiKit.label("Stage cleared", 20, Color("ffd866"))))


func show_banner() -> void:
	visible = true
	Audio.play(&"stage_clear")

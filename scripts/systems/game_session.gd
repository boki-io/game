extends Node
## Autoload. Remembers the selected character and owns scene changes between the Hub and a run.

const HUB := "res://scenes/hub.tscn"
const RUN := "res://scenes/main.tscn"

## The character of the current or next run.
var character: CharacterData
## The character last taken into a run this session. Null at boot: the hub then starts in browse mode.
var last_character: CharacterData


func _ready() -> void:
	# Default so the run scene also runs directly from the editor.
	character = CharacterRegistry.all()[0]


func start_run(selected: CharacterData) -> void:
	character = selected
	last_character = selected
	SceneFader.fade_to_scene(RUN)


## Same character, fresh run.
func restart_run() -> void:
	SceneFader.fade_to_scene(RUN)


func go_to_hub() -> void:
	SceneFader.fade_to_scene(HUB)

extends Node
## Autoload. Remembers the selected character and owns scene changes between
## Main Menu, Character Select and the Game.

const MAIN_MENU := "res://scenes/main_menu.tscn"
const CHARACTER_SELECT := "res://scenes/character_select.tscn"
const GAME := "res://scenes/main.tscn"

var character: CharacterData


func _ready() -> void:
	# Default so the Game scene also runs directly from the editor.
	character = CharacterRegistry.all()[0]


func go_to_character_select() -> void:
	_go(CHARACTER_SELECT)


func start_game(selected: CharacterData) -> void:
	character = selected
	_go(GAME)


## Same character, fresh run.
func restart() -> void:
	_go(GAME)


func go_to_main_menu() -> void:
	_go(MAIN_MENU)


func _go(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)

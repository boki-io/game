extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROP_SCRIPT := preload("res://scripts/systems/prop.gd")
const PROP_COUNT := 14
const PROP_MARGIN := 48.0

@onready var players_root: Node2D = $World/Players
@onready var props_root: Node2D = $World/Props


func _ready() -> void:
	_spawn_props()
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(Arena.SIZE) / 2.0
	players_root.add_child(player)


func _spawn_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var center := Vector2(Arena.SIZE) / 2.0
	for i in PROP_COUNT:
		var pos := Vector2(
			rng.randf_range(PROP_MARGIN, Arena.SIZE.x - PROP_MARGIN),
			rng.randf_range(PROP_MARGIN, Arena.SIZE.y - PROP_MARGIN))
		if pos.distance_to(center) < 60.0:
			continue
		var prop := StaticBody2D.new()
		prop.set_script(PROP_SCRIPT)
		prop.position = pos
		props_root.add_child(prop)

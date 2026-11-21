class_name HubChest
extends Node2D
## The chest in the hub, right of the door (spec 1.4): one 32x32 sprite (assets/hub/chest.png, exported from
## art/source/chest/chest.aseprite). The node's origin is the chest's base (the bottom centre of its opaque pixels), so it
## Y-sorts with the player by it. No collider and no click area, like the camp: the hub opens it with the interact key.

const TEXTURE := preload("res://assets/hub/chest.png")
## The base point inside the 32x32 frame: bottom centre of the opaque pixels (x 3 to 28, y 7 to 26).
const BASE := Vector2(16, 27)

var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.centered = false
	sprite.offset = -BASE
	add_child(sprite)

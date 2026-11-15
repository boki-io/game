class_name XPCollector
extends Area2D
## Pulls pickups (XP gems, coins: anything with attract()) toward the player once they enter the pickup radius.

const BASE_RADIUS := 48.0

var _shape := CircleShape2D.new()

@onready var player: Player = get_parent()
@onready var stats: Stats = player.get_node("Stats")


func _ready() -> void:
	$CollisionShape2D.shape = _shape
	refresh()
	area_entered.connect(_on_area_entered)


## Call after pickup_radius changes.
func refresh() -> void:
	_shape.radius = stats.value(&"pickup_radius", BASE_RADIUS)


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("attract"):
		area.attract(player)

class_name Hurtbox
extends Area2D
## Receives hits for its parent's sibling Health node. Set invulnerable for i-frames.

signal hit_taken(amount: float)

var invulnerable := false

@onready var health: Health = get_parent().get_node("Health")


## Returns true if the hit landed (false while invulnerable).
func receive_hit(amount: float) -> bool:
	if invulnerable:
		return false
	health.take_damage(amount)
	hit_taken.emit(amount)
	return true

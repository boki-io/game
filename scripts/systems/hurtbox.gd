class_name Hurtbox
extends Area2D
## Receives hits for its parent's sibling Health node. Set invulnerable for i-frames.

signal hit_taken(amount: float)

var invulnerable := false
## Seconds of extra immunity left (e.g. after a dash). Counts down by itself.
var grace_left := 0.0

@onready var health: Health = get_parent().get_node("Health")


func is_immune() -> bool:
	return invulnerable or grace_left > 0.0


func grant_grace(seconds: float) -> void:
	grace_left = maxf(grace_left, seconds)


func _physics_process(delta: float) -> void:
	grace_left = maxf(grace_left - delta, 0.0)


## Returns true if the hit landed (false while immune).
func receive_hit(amount: float) -> bool:
	if is_immune():
		return false
	health.take_damage(amount)
	hit_taken.emit(amount)
	return true

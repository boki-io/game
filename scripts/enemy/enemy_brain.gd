class_name EnemyBrain
extends RefCounted
## Behavior of one enemy type. The Enemy node owns health, knockback, stun, contact hits,
## pooling and drawing; the brain decides where it wants to move and when it acts.

var enemy: Enemy


func setup(e: Enemy) -> void:
	enemy = e


## Called every time the enemy is (re)activated from the pool. Reset all state here.
func reset() -> void:
	pass


## Desired velocity in px/s for this frame. Runs only when not stunned.
func think(_delta: float, _target: Player) -> Vector2:
	return Vector2.ZERO


## The enemy was stunned: cancel any wind-up or telegraph.
func cancel() -> void:
	pass


## False while the brain is standing still on purpose (holding, aiming, dashing): the stuck failsafe skips it.
func asks_to_move() -> bool:
	return true


func can_contact() -> bool:
	return true


func contact_damage() -> float:
	return enemy.data.contact_damage


## A contact hit landed on a player.
func on_contact_hit() -> void:
	pass

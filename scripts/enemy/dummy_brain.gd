class_name DummyBrain
extends EnemyBrain
## Training dummy: never moves, never attacks, never dies. Whenever a hit takes it below half health it is
## healed to full, so the `died` signal can never fire (a dead Enemy is not deactivated and would keep absorbing).


func setup(e: Enemy) -> void:
	super(e)
	e.health.damaged.connect(_top_up)


func can_contact() -> bool:
	return false


func _top_up(_amount: float) -> void:
	var health := enemy.health
	if health.current < health.max_health * 0.5:
		health.current = health.max_health
		health.changed.emit(health.current, health.max_health)

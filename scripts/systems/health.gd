class_name Health
extends Node

signal changed(current: float, maximum: float)
signal damaged(amount: float)
signal died

var max_health := 100.0
var current := 100.0


func setup(max_hp: float) -> void:
	max_health = max_hp
	current = max_hp
	changed.emit(current, max_health)


func take_damage(amount: float) -> void:
	if current <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount)
	changed.emit(current, max_health)
	if current <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if current <= 0.0:
		return
	current = minf(current + amount, max_health)
	changed.emit(current, max_health)

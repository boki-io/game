class_name Mana
extends Node

signal changed(current: float, maximum: float)

@export var base_max: float = 100.0
@export var base_regen: float = 8.0  # per second

var current := 0.0

@onready var stats: Stats = get_parent().get_node("Stats")


func _ready() -> void:
	current = max_mana()
	changed.emit(current, current)


func max_mana() -> float:
	return stats.value(&"max_mana", base_max)


func regen() -> float:
	return stats.value(&"mana_regen", base_regen)


func can_afford(cost: float) -> bool:
	return current >= cost


func spend(cost: float) -> void:
	current = maxf(current - cost, 0.0)
	changed.emit(current, max_mana())


func gain(amount: float) -> void:
	current = minf(current + amount, max_mana())
	changed.emit(current, max_mana())


func _physics_process(delta: float) -> void:
	if current < max_mana():
		gain(regen() * delta)

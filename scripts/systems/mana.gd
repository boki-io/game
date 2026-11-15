class_name Mana
extends Node

signal changed(current: float, maximum: float)

@export var base_max: float = 100.0
@export var base_regen: float = 8.0  # per second

var current := 0.0
var _known_max := 0.0

@onready var stats: Stats = get_parent().get_node("Stats")


func _ready() -> void:
	_known_max = max_mana()
	current = _known_max
	changed.emit(current, current)


func max_mana() -> float:
	return stats.value(&"max_mana", base_max)


func regen() -> float:
	return stats.value(&"mana_regen", base_regen)


## Call after max_mana changes; an increase also fills by the same amount.
func refresh() -> void:
	var new_max := max_mana()
	if new_max > _known_max:
		current += new_max - _known_max
	_known_max = new_max
	current = minf(current, new_max)
	changed.emit(current, new_max)


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

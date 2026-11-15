class_name Stats
extends Node
## Base values plus modifiers. Upgrades write here; they never edit the .tres files.
## Keys: global ("damage", "move_speed", "max_mana", ...) or per ability ("dash.cooldown").
## value() = (base + adds) * mults, so percent bonuses stack multiplicatively.

var _adds: Dictionary = {}
var _mults: Dictionary = {}
var _flags: Dictionary = {}
var _conditional: Dictionary = {}  # source -> {key -> factor}


func value(key: StringName, base: float) -> float:
	var result: float = (base + _adds.get(key, 0.0)) * _mults.get(key, 1.0)
	for source: StringName in _conditional:
		result *= _conditional[source].get(key, 1.0)
	return result


func add(key: StringName, amount: float) -> void:
	_adds[key] = _adds.get(key, 0.0) + amount


func multiply(key: StringName, factor: float) -> void:
	_mults[key] = _mults.get(key, 1.0) * factor


## A multiplier that a trait can switch on and off under its own `source` name without touching upgrades.
func set_conditional(source: StringName, key: StringName, factor: float) -> void:
	if not _conditional.has(source):
		_conditional[source] = {}
	_conditional[source][key] = factor


func clear_conditional(source: StringName) -> void:
	_conditional.erase(source)


func set_flag(key: StringName, on: bool = true) -> void:
	_flags[key] = on


func has_flag(key: StringName) -> bool:
	return _flags.get(key, false)

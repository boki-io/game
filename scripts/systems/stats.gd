class_name Stats
extends Node
## Base values plus modifiers. Upgrades write here; they never edit the .tres files.
## Keys: global ("damage", "move_speed", "max_mana", ...) or per ability ("dash.cooldown").
## value() = (base + adds) * mults, so percent bonuses stack multiplicatively.

var _adds: Dictionary = {}
var _mults: Dictionary = {}
var _flags: Dictionary = {}


func value(key: StringName, base: float) -> float:
	return (base + _adds.get(key, 0.0)) * _mults.get(key, 1.0)


func add(key: StringName, amount: float) -> void:
	_adds[key] = _adds.get(key, 0.0) + amount


func multiply(key: StringName, factor: float) -> void:
	_mults[key] = _mults.get(key, 1.0) * factor


func set_flag(key: StringName, on: bool = true) -> void:
	_flags[key] = on


func has_flag(key: StringName) -> bool:
	return _flags.get(key, false)

class_name PlayerXP
extends Node
## Per-player XP and level. XP needed for the next level = round(8 * 1.35^(level-1)).

signal changed(xp: int, needed: int, level: int)
signal leveled_up(level: int)

const BASE_XP := 8.0
const GROWTH := 1.35

var level := 1
var xp := 0


static func needed_for(lv: int) -> int:
	return roundi(BASE_XP * pow(GROWTH, lv - 1))


func needed() -> int:
	return needed_for(level)


func add(amount: int) -> void:
	xp += amount
	while xp >= needed():
		xp -= needed()
		level += 1
		leveled_up.emit(level)
	changed.emit(xp, needed(), level)

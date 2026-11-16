class_name PlayerUpgrades
extends Node
## Per-player upgrade levels. Applying an upgrade writes modifiers into Stats.

signal upgraded(data: UpgradeData, level: int)

var levels: Dictionary = {}  # id -> level
var pool: Array[UpgradeData] = []

@onready var player: Player = get_parent()
@onready var stats: Stats = player.get_node("Stats")


func level_of(data: UpgradeData) -> int:
	return levels.get(data.id, 0)


## Every upgrade in the pool that is not yet maxed.
func open_upgrades() -> Array[UpgradeData]:
	var open: Array[UpgradeData] = []
	for u in pool:
		if level_of(u) < u.max_level:
			open.append(u)
	return open


## Up to `count` distinct upgrades that are not yet maxed.
func roll(count: int = 3) -> Array[UpgradeData]:
	var open := open_upgrades()
	open.shuffle()
	var picks: Array[UpgradeData] = []
	for u: UpgradeData in open.slice(0, count):
		picks.append(u)
	return picks


func apply(data: UpgradeData) -> void:
	levels[data.id] = level_of(data) + 1
	for key: String in data.adds:
		stats.add(StringName(key), data.adds[key])
	for key: String in data.mults:
		stats.multiply(StringName(key), data.mults[key])
	player.refresh_stats()
	upgraded.emit(data, levels[data.id])

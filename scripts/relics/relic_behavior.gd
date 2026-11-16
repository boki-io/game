class_name RelicBehavior
extends Node
## Base of a relic's behavior node (a child of PlayerRelics). Subclasses read their numbers from `params()`.

var player: Player
var data: RelicData
var level := 1


## The dictionary of the current level (see RelicData.levels).
func params() -> Dictionary:
	return data.levels[level - 1]


## `base` scaled by the player's damage stat, at the moment the damage is dealt.
func dmg(base: float) -> float:
	return base * player.stats.value(&"damage", 1.0)


## 0 = ready, 1 = just fired; relics without a cooldown stay at 0. The HUD draws the sweep from it.
func cooldown_fraction() -> float:
	return 0.0


## Called when the behavior is created (with the level it starts at) and on every raise. Override and call super.
func set_level(new_level: int) -> void:
	level = new_level

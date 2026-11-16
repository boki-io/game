class_name RunProgress
extends RefCounted
## What a Player carries from one stage of a run to the next: level, XP progress and the upgrades chosen at
## level-ups. HP, mana and cooldowns are not carried: each stage starts at full health.


## A snapshot of `player`'s carried progress.
static func capture(player: Player) -> Dictionary:
	return {
		level = player.xp.level,
		xp = player.xp.xp,
		upgrades = player.upgrades.levels.duplicate(),
	}


## Applies `progress` to a Player that is already in the tree (the upgrade pool is only set in Player._ready).
## XP is assigned directly so `leveled_up` never fires and no level-up menu opens. Call before anything
## connects to `leveled_up`.
static func restore(player: Player, progress: Dictionary) -> void:
	player.xp.level = progress.level
	player.xp.xp = progress.xp
	player.xp.changed.emit(player.xp.xp, player.xp.needed(), player.xp.level)
	var levels: Dictionary = progress.upgrades
	for data in player.upgrades.pool:
		for i in levels.get(data.id, 0):
			player.upgrades.apply(data)
	# Full HP and mana at the upgraded maximums.
	player.health.setup(player.stats.value(&"max_hp", player.max_hp))
	player.mana.configure(player.mana.base_max, player.mana.base_regen)

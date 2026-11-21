class_name RunProgress
extends RefCounted
## What a Player carries from one stage of a run to the next: level, XP progress and the upgrades and relics chosen at
## level-ups. HP, mana and cooldowns are not carried: each stage starts at full health.


## A snapshot of `player`'s carried progress.
static func capture(player: Player) -> Dictionary:
	return {
		level = player.xp.level,
		xp = player.xp.xp,
		upgrades = player.upgrades.levels.duplicate(),
		relics = player.relics.levels.duplicate(),
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
	# Relics come back in slot order at their saved level, without flashing the HUD.
	var relic_levels: Dictionary = progress.get("relics", {})
	for id: StringName in relic_levels:
		var relic := RelicRegistry.find(id)
		if relic == null:
			continue
		# A granted relic already stands at level 1: raise to the saved level, never past it.
		while player.relics.level_of(relic) < relic_levels[id]:
			if not player.relics.add_or_raise(relic, false):
				break
	# Full HP and mana at the upgraded maximums.
	player.health.setup(player.stats.value(&"max_hp", player.max_hp))
	player.mana.configure(player.mana.base_max, player.mana.base_regen)

class_name LevelUpRoller
extends RefCounted
## Builds the pool of level-up cards (new relics, relic upgrades, stat upgrades) and draws from it (spec 1.0, section 5).

const RELIC_WEIGHT := 2.0
const STAT_WEIGHT := 1.0


## Up to `count` distinct cards. `player` is a Player (untyped so tests need not name it); `rng` makes the draw seedable.
static func roll(player: Node, count: int, rng: RandomNumberGenerator) -> Array[LevelUpChoice]:
	var relics: PlayerRelics = player.relics
	var pool: Array[LevelUpChoice] = []
	var new_relics: Array[LevelUpChoice] = []
	for data in RelicRegistry.all():
		var level := relics.level_of(data)
		if level == 0:
			if relics.free_slots() > 0:
				new_relics.append(_relic_card(relics, data, 0))
		elif level < PlayerRelics.MAX_LEVEL:
			pool.append(_relic_card(relics, data, level))
	pool.append_array(new_relics)
	for u in player.upgrades.open_upgrades():
		pool.append(_stat_card(player.upgrades, u))

	var picks: Array[LevelUpChoice] = []
	if relics.levels.is_empty() and not new_relics.is_empty() and count > 0:
		picks.append(_draw(new_relics, rng))
		pool.erase(picks[0])
	while picks.size() < count and not pool.is_empty():
		picks.append(_draw(pool, rng))
		pool.erase(picks[-1])
	return picks


## One weighted pick from `cards` (not removed).
static func _draw(cards: Array[LevelUpChoice], rng: RandomNumberGenerator) -> LevelUpChoice:
	var total := 0.0
	for c in cards:
		total += c.weight
	var r := rng.randf() * total
	for c in cards:
		r -= c.weight
		if r < 0.0:
			return c
	return cards[-1]


static func _relic_card(relics: PlayerRelics, data: RelicData, level: int) -> LevelUpChoice:
	var c := LevelUpChoice.new()
	c.title = data.display_name
	c.tag = "RELIC"
	c.is_relic = true
	c.description = data.levels[level].description
	c.from_level = level
	c.to_level = level + 1
	c.weight = RELIC_WEIGHT
	c.apply = func() -> void: relics.add_or_raise(data)
	return c


static func _stat_card(upgrades: PlayerUpgrades, u: UpgradeData) -> LevelUpChoice:
	var c := LevelUpChoice.new()
	c.title = u.display_name
	c.tag = u.tag.to_upper()
	c.description = u.description
	c.from_level = upgrades.level_of(u)
	c.to_level = c.from_level + 1
	c.weight = STAT_WEIGHT
	c.apply = func() -> void: upgrades.apply(u)
	return c

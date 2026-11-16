extends SceneTree
## Level-up cards with relics (spec 1.0, section 5): LevelUpRoller, LevelUpChoice, PlayerUpgrades.open_upgrades.
## Run: godot --headless --path . --script tests/relic_cards.gd

const SEED_COUNT := 30

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _ids(cards: Array) -> Array:
	return cards.map(func(c: LevelUpChoice) -> String: return "%s:%d" % [c.title, c.from_level])


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node("GameSession")
	gs.scene_hook = func(_path: String) -> void: pass
	var F: GDScript = load("res://tests/fixture.gd")
	var Roller: GDScript = load("res://scripts/relics/level_up_roller.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var p = F.player()
	var rel = p.relics
	var all := RelicRegistry.all()
	var stat_open: int = p.upgrades.open_upgrades().size()
	_check(stat_open > 0 and p.upgrades.open_upgrades().size() == p.upgrades.pool.size(), "open_upgrades lists the whole fresh pool")

	# No relic owned: three distinct cards, a new relic always among them.
	for s in SEED_COUNT:
		var cards: Array = Roller.roll(p, 3, _rng(s))
		_check(cards.size() == 3 and _ids(cards).size() == 3 and _unique(_ids(cards)), "seed %d: three distinct cards" % s)
		_check(cards.any(func(c: LevelUpChoice) -> bool: return c.tag == "RELIC" and c.from_level == 0), "seed %d: a new relic is among the three" % s)
		_check(Roller.roll(p, 3, _rng(s)).map(func(c): return c.title) == cards.map(func(c): return c.title), "seed %d: reproducible" % s)

	# Weights: with one relic owned at level 1 and three free slots, relic cards weigh 2, stat cards 1.
	rel.add_or_raise(all[0], false)
	var relic_cards := 4 + 1  # four unowned relics plus the upgrade of the owned one
	var expect := 2.0 * relic_cards / (2.0 * relic_cards + stat_open)
	var rng := _rng(7)
	var relic_picks := 0
	for i in 3000:
		var c: Array = Roller.roll(p, 1, rng)
		if c[0].tag == "RELIC":
			relic_picks += 1
	var share := relic_picks / 3000.0
	_check(absf(share - expect) <= 0.05, "relic share %.3f within 5 points of %.3f" % [share, expect])

	# Upgrade cards only for owned relics below 3; no new relic with 4 full.
	rel.add_or_raise(all[1], false)
	rel.add_or_raise(all[2], false)
	rel.add_or_raise(all[3], false)
	rel.add_or_raise(all[3], false)
	rel.add_or_raise(all[3], false)  # storm orbs at 3
	_check(rel.free_slots() == 0, "four slots full")
	for s in SEED_COUNT:
		var cards: Array = Roller.roll(p, 3, _rng(s))
		_check(_unique(_ids(cards)), "seed %d (full): distinct" % s)
		for c in cards:
			if c.tag == "RELIC":
				var data: RelicData = RelicRegistry.all().filter(func(r: RelicData) -> bool: return r.display_name == c.title)[0]
				_check(c.from_level > 0 and rel.owns(data.id), "seed %d: no new relic with 4 full (%s)" % [s, c.title])
				_check(rel.level_of(data) < 3 and c.from_level == rel.level_of(data) and c.to_level == c.from_level + 1, "seed %d: upgrade card only below 3 (%s)" % [s, c.title])

	# A relic card applied raises the level.
	var up: LevelUpChoice
	for s in 200:
		for c in Roller.roll(p, 3, _rng(s)):
			if c.tag == "RELIC":
				up = c
		if up != null:
			break
	_check(up != null and up.level_text() == "Lv %d -> %d" % [up.from_level, up.to_level], "an upgrade card reads Lv a -> b")
	var before: int = rel.levels.values().reduce(func(a, b): return a + b, 0)
	up.apply.call()
	_check(rel.levels.values().reduce(func(a, b): return a + b, 0) == before + 1, "applying an upgrade card raises the relic one level")

	# Everything maxed: only stat cards.
	for id in rel.levels.keys():
		while rel.level_of(RelicRegistry.find(id)) < 3:
			rel.add_or_raise(RelicRegistry.find(id), false)
	for s in SEED_COUNT:
		var cards: Array = Roller.roll(p, 3, _rng(s))
		_check(cards.size() == 3 and cards.all(func(c: LevelUpChoice) -> bool: return c.tag != "RELIC"), "seed %d: all maxed falls back to stat cards" % s)
	var stat: LevelUpChoice = Roller.roll(p, 3, _rng(1))[0]
	var lv_before: int = stat.from_level
	var pool_level: int = p.upgrades.levels.values().reduce(func(a, b): return a + b, 0)
	stat.apply.call()
	_check(stat.level_text() == "Lv %d -> %d" % [lv_before, lv_before + 1] and p.upgrades.levels.values().reduce(func(a, b): return a + b, 0) == pool_level + 1, "a stat card applies and keeps Lv text (%s %d %d)" % [stat.level_text(), pool_level, p.upgrades.levels.size()])

	# Fewer than three cards exist: maxed stats too.
	for u in p.upgrades.pool:
		p.upgrades.levels[u.id] = u.max_level
	_check(Roller.roll(p, 3, _rng(1)).is_empty(), "nothing left gives no cards")

	# A new relic takes the first free slot.
	main.queue_free()
	await process_frame
	root.get_node("PlayerRegistry").players.clear()
	main = F.start_run(self, &"knight")
	await F.frames(self, 2)
	p = F.player()
	rel = p.relics
	rel.add_or_raise(all[0], false)
	rel.add_or_raise(all[1], false)
	var fresh: LevelUpChoice
	for s in 200:
		for c in Roller.roll(p, 3, _rng(s)):
			if c.tag == "RELIC" and c.from_level == 0:
				fresh = c
		if fresh != null:
			break
	_check(fresh != null and fresh.level_text() == "NEW", "a new relic card reads NEW")
	fresh.apply.call()
	_check(rel.levels.size() == 3 and rel.slot_of(rel.levels.keys()[2]) == 2, "a new relic takes the first free slot (slot 2)")

	main.queue_free()
	paused = false
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _unique(a: Array) -> bool:
	for i in a.size():
		if a.find(a[i]) != i:
			return false
	return true

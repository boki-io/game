extends SceneTree
## Spec 1.1 step 4, Arrow and Dash Shot: the auto Arrow (nearest target, target range, cooldown, arrow.extra,
## Steady Aim damage) and Dash Shot (the Knight's dash rules, no path damage, grace after, a 60 degree fan
## centred on the opposite of the aim from the landing point, the arrow count, chain, no mana). The Archer does not
## exist yet, so a Wizard run gets the two abilities by hand.
## Run: godot --headless --path . --script tests/archer_arrow_dash.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## The live projectiles in the pool.
func _live(pool) -> Array:
	var out: Array = []
	for child in pool.get_children():
		if child.get("active"):
			out.append(child)
	return out


## Physics frames until a projectile is live (at most `limit` frames). Returns the live ones.
func _wait_for_arrows(F: GDScript, pool, limit: int = 120) -> Array:
	for i in limit:
		await F.frames(self, 1)
		var live := _live(pool)
		if not live.is_empty():
			return live
	return []


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var arrow_data: AbilityData = load("res://content/characters/archer/abilities/arrow/ability.tres")
	var dash_data: AbilityData = load("res://content/characters/archer/abilities/dashshot/ability.tres")

	# The data files, as the spec states them.
	_check(arrow_data.id == &"arrow" and arrow_data.cooldown == 0.8 and arrow_data.damage == 14.0, "arrow.tres numbers")
	_check(arrow_data.range == 220.0 and arrow_data.target_range == 180.0 and arrow_data.mana_cost == 0.0, "arrow.tres reach")
	_check(arrow_data.param(&"speed", 0.0) == 320.0 and arrow_data.behavior.resource_path.ends_with("/arrow/behavior.gd"), "arrow.tres speed, behavior")
	_check(dash_data.id == &"dashshot" and dash_data.animation == &"dash", "dash_shot.tres id and animation")
	_check(dash_data.cooldown == 4.0 and dash_data.range == 80.0 and dash_data.duration == 0.15, "dash_shot.tres dash")
	_check(dash_data.damage == 12.0 and dash_data.arc_degrees == 60.0 and dash_data.immunity_after == 0.2, "dash_shot.tres fan")
	_check(dash_data.param(&"arrows", 0.0) == 7.0 and dash_data.param(&"speed", 0.0) == 300.0, "dash_shot.tres params")
	_check(dash_data.mana_cost == 0.0 and dash_data.behavior.resource_path.ends_with("/dashshot/behavior.gd") and dash_data.sfx != null, "dash_shot.tres rest")
	var player_script: GDScript = load("res://scripts/player/player.gd")
	_check(player_script.ONE_SHOT_ANIMS.has(dash_data.animation), "the dash animation is a one-shot")

	var main: Node = F.start_run(self, &"wizard")
	await F.frames(self, 3)
	var p = F.player()
	var caster = p.caster
	var pool = get_first_node_in_group(&"player_projectiles")
	var origin: Vector2 = p.global_position
	caster.ability_auto = arrow_data
	caster.ability_q = dash_data
	caster.ability_e = null
	caster.ability_r = null
	var casts: Array = []
	caster.cast_started.connect(func(slot: StringName, _d: AbilityData) -> void: casts.append(slot))
	var mana_start: float = p.mana.current

	# --- Arrow ---
	# Out of target_range (180): nothing is shot.
	var far = F.spawn_enemy(main, "grunt", origin + Vector2(200, 0), 100.0, true)
	await F.seconds(self, 0.5)
	_check(casts.is_empty() and _live(pool).is_empty(), "no arrow at an enemy beyond the target range")
	far.queue_free()
	await F.frames(self, 2)

	# Nearest target: an enemy north at 60 and one east at 100: the first arrow goes north.
	var east = F.spawn_enemy(main, "grunt", origin + Vector2(100, 0), 100.0, true)
	var north = F.spawn_enemy(main, "grunt", origin + Vector2(0, -60), 100.0, true)
	await F.frames(self, 2)
	var live := await _wait_for_arrows(F, pool)
	_check(live.size() == 1, "one arrow per shot (got %d)" % live.size())
	if not live.is_empty():
		_check(live[0]._dir.distance_to(Vector2.UP) < 0.01, "the arrow flies at the nearest enemy")
		_check(live[0]._arrow and live[0]._steady, "the arrow draws as an arrow and uses Steady Aim")
		_check(is_equal_approx(live[0]._speed, 320.0) and live[0]._range_left > 200.0 and live[0]._range_left <= 220.0, "speed and range (%f, %f)" % [live[0]._speed, live[0]._range_left])
	_check(is_equal_approx(caster.cooldowns[&"auto"], arrow_data.cooldown) or caster.cooldowns[&"auto"] > 0.6,
		"the cooldown is 0.8 s (%f)" % caster.cooldowns[&"auto"])

	# The cooldown spaces the shots: casts over the next 2.0 s (the enemies are tough and frozen).
	casts.clear()
	await F.seconds(self, 2.0)
	_check(casts.size() >= 2 and casts.size() <= 3, "about one arrow per 0.8 s (%d casts in 2.0 s)" % casts.size())
	_check(p.mana.current >= mana_start, "the arrow costs no mana")
	east.queue_free()
	north.queue_free()
	await F.frames(self, 2)
	pool.clear()

	# arrow.extra: 1 extra is 2 arrows, 3 extra is 4 (a fan, max 4).
	p.stats.add(&"arrow.extra", 1.0)
	caster.cooldowns[&"auto"] = 0.0
	var target = F.spawn_enemy(main, "grunt", origin + Vector2(100, 0), 100.0, true)
	await F.frames(self, 2)
	live = await _wait_for_arrows(F, pool)
	_check(live.size() == 2, "arrow.extra 1 fires 2 arrows (got %d)" % live.size())
	var spread := 0.0
	for a in live:
		spread = maxf(spread, absf(rad_to_deg(a._dir.angle_to(Vector2.RIGHT))))
	_check(spread > 1.0, "the extra arrows fan out")
	target.queue_free()
	await F.frames(self, 2)
	pool.clear()
	p.stats.add(&"arrow.extra", 5.0)  # beyond the cap of 4 arrows
	caster.cooldowns[&"auto"] = 0.0
	target = F.spawn_enemy(main, "grunt", origin + Vector2(100, 0), 100.0, true)
	await F.frames(self, 2)
	live = await _wait_for_arrows(F, pool)
	_check(live.size() == 4, "arrows are capped at 4 (got %d)" % live.size())
	target.queue_free()
	await F.frames(self, 2)
	pool.clear()
	p.stats.add(&"arrow.extra", -6.0)

	# Damage: scales with the damage stat, and a far hit does more than a near one (Steady Aim).
	caster.ability_auto = null  # fire by hand through the behavior's cast, one shot at a time
	var behavior = arrow_data.behavior.new()
	var near_gain := 0.0
	var far_gain := 0.0
	for pass_number in 2:
		for distance in [30.0, 150.0]:
			pool.clear()
			var dummy = F.spawn_enemy(main, "grunt", origin + Vector2(distance, 0), 100.0, true)
			await F.frames(self, 2)
			var hp: float = dummy.health.current
			behavior.cast(caster, Vector2.RIGHT, arrow_data)
			await F.seconds(self, 0.7)
			var dealt: float = hp - dummy.health.current
			var base: float = 14.0 * p.stats.value(&"damage", 1.0)
			if distance < 40.0:
				_check(absf(dealt - base) < 0.5, "a near hit does base damage (%f vs %f)" % [dealt, base])
				near_gain = dealt
			else:
				var expected: float = base * SteadyAim.multiplier(distance)
				_check(absf(dealt - expected) < 0.5, "a far hit does Steady Aim damage (%f vs %f)" % [dealt, expected])
				far_gain = dealt
			dummy.queue_free()
			await F.frames(self, 2)
		if pass_number == 0:
			_check(far_gain > near_gain * 1.2, "a far arrow hits harder than a near one")
			p.stats.multiply(&"damage", 2.0)
	_check(p.stats.value(&"damage", 1.0) >= 2.0 and near_gain > 27.0, "damage follows the damage stat (%f)" % near_gain)
	p.stats.multiply(&"damage", 0.5)
	# steady.full moves the full-bonus distance, as Eagle Eye does.
	p.stats.add(&"steady.full", -60.0)
	pool.clear()
	var dummy2 = F.spawn_enemy(main, "grunt", origin + Vector2(100, 0), 100.0, true)
	await F.frames(self, 2)
	var hp2: float = dummy2.health.current
	behavior.cast(caster, Vector2.RIGHT, arrow_data)
	await F.seconds(self, 0.6)
	var eagle: float = hp2 - dummy2.health.current
	var eagle_expected: float = 14.0 * p.stats.value(&"damage", 1.0) * SteadyAim.multiplier(100.0, 100.0)
	_check(absf(eagle - eagle_expected) < 0.5, "steady.full reaches the opts (%f)" % eagle)
	p.stats.add(&"steady.full", 60.0)
	dummy2.queue_free()
	await F.frames(self, 2)
	pool.clear()
	caster.ability_auto = null

	# --- Dash Shot ---
	# Walk the player back to the middle, clear the field and let the grace of earlier casts end.
	p.global_position = origin
	casts.clear()
	await F.seconds(self, 0.3)
	var wall_enemy = F.spawn_enemy(main, "grunt", origin + Vector2(0, -40), 100.0, true)  # on the dash path
	var wall_hp: float = wall_enemy.health.current
	await F.frames(self, 2)
	var mana_before: float = p.mana.current
	F.cast(p, &"q", Vector2.UP)
	await F.frames(self, 3)
	_check(p.hurtbox.is_immune(), "invulnerable while dashing")
	var landing_arrows := await _wait_for_arrows(F, pool)
	_check(landing_arrows.size() == 7, "the spray is 7 arrows (got %d)" % landing_arrows.size())
	_check(is_equal_approx(wall_enemy.health.current, wall_hp), "no damage to an enemy on the dash path")
	var landed: Vector2 = p.global_position
	_check(absf(origin.distance_to(landed) - 80.0) < 6.0, "the dash covers 80 px (%f)" % origin.distance_to(landed))
	_check((landed - origin).normalized().distance_to(Vector2.UP) < 0.05, "the dash goes towards the aim")
	_check(p.hurtbox.is_immune(), "the grace time starts at the landing")
	var angles: Array = []
	var from_landing := true
	for a in landing_arrows:
		angles.append(rad_to_deg(a._dir.angle_to(Vector2.DOWN)))
		from_landing = from_landing and a._launch.distance_to(landed) < 8.0
		_check(a._range_left > 170.0 and a._range_left <= 180.0, "arrow range is 180")
	angles.sort()
	_check(from_landing, "the arrows start at the landing position")
	_check(absf(angles[0] + 30.0) < 0.5 and absf(angles[6] - 30.0) < 0.5, "the fan is 60 degrees (%s)" % str(angles))
	var mean := 0.0
	for angle: float in angles:
		mean += angle / 7.0
	_check(absf(mean) < 0.5, "the fan is centred on the opposite of the aim (mean %f)" % mean)
	_check(absf(angles[1] - angles[0] - 10.0) < 0.5 and absf(angles[4] - angles[3] - 10.0) < 0.5, "evenly spaced")
	_check(landing_arrows[0]._arrow and landing_arrows[0]._steady and is_equal_approx(landing_arrows[0]._speed, 300.0),
		"arrow look, Steady Aim and speed")
	_check(p.mana.current >= mana_before, "Dash Shot costs no mana")
	_check(caster.cooldowns[&"q"] > 3.0, "the cooldown is 4 s")
	await F.seconds(self, dash_data.immunity_after + 0.25)
	_check(not p.hurtbox.is_immune(), "the grace time ends")
	wall_enemy.queue_free()
	await F.frames(self, 2)

	# Long Dash: dashshot.range works. Wide Spray: dashshot.arrows adds arrows to the 7.
	caster.cooldowns[&"q"] = 0.0
	pool.clear()
	p.global_position = origin
	p.stats.multiply(&"dashshot.range", 1.3)
	p.stats.add(&"dashshot.arrows", 2.0)
	F.cast(p, &"q", Vector2.LEFT)
	live = await _wait_for_arrows(F, pool)
	_check(live.size() == 9, "dashshot.arrows +2 gives 9 arrows (got %d)" % live.size())
	_check(absf(origin.distance_to(p.global_position) - 104.0) < 6.0,
		"dashshot.range x1.3 dashes 104 px (%f)" % origin.distance_to(p.global_position))
	for a in live:
		_check(a._dir.x > 0.8, "a leftward dash sprays to the right")
	await F.seconds(self, 0.5)
	p.stats.multiply(&"dashshot.range", 1.0 / 1.3)
	p.stats.add(&"dashshot.arrows", -2.0)

	# Chain (Double Dash): a free follow-up, which sprays again.
	await F.seconds(self, 1.0)
	pool.clear()
	p.global_position = origin
	caster.cooldowns[&"q"] = 0.0
	p.stats.add(&"dashshot.chain", 1.0)
	F.cast(p, &"q", Vector2.UP)
	live = await _wait_for_arrows(F, pool)
	_check(live.size() == 7, "the first dash of a chain sprays")
	await F.seconds(self, 0.4)
	_check(caster.chain_open(&"q"), "a follow-up is open (dashshot.chain)")
	pool.clear()
	var mana_chain: float = p.mana.current
	var before_follow: Vector2 = p.global_position
	F.cast(p, &"q", Vector2.DOWN)
	live = await _wait_for_arrows(F, pool)
	_check(live.size() == 7, "the follow-up sprays again (got %d)" % live.size())
	_check(p.mana.current >= mana_chain, "the follow-up is free")
	await F.seconds(self, 0.3)
	_check(p.global_position.distance_to(before_follow) > 60.0, "the follow-up dashes")
	_check(not caster.chain_open(&"q"), "the chain ends after its follow-up")

	# Damage scales with the damage stat, and a far arrow does more (Steady Aim).
	await F.seconds(self, 4.5)
	p.global_position = origin
	pool.clear()
	caster.cooldowns[&"q"] = 0.0
	p.stats.multiply(&"damage", 2.0)
	# Aim up: the arrows fly down from (origin + 0,-80); a far enemy at 150 px below the landing, a near one is
	# not needed since the dash shows base damage through a 30 px pass: test the far hit only.
	var victim = F.spawn_enemy(main, "grunt", origin + Vector2(0, 70), 100.0, true)
	await F.frames(self, 2)
	var victim_hp: float = victim.health.current
	F.cast(p, &"q", Vector2.UP)
	await F.seconds(self, 1.2)
	var arrow_hits: float = victim_hp - victim.health.current
	# The landing is 150 px from the victim; arrows near the centre of the fan hit it, the rest pass by.
	var expected_hit: float = 12.0 * 2.0 * SteadyAim.multiplier(150.0)
	_check(arrow_hits >= expected_hit - 0.5, "a far Dash Shot arrow does Steady Aim damage x damage stat (%f vs %f)"
		% [arrow_hits, expected_hit])
	p.stats.multiply(&"damage", 0.5)

	main.queue_free()
	await process_frame
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

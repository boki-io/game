extends SceneTree
## Horde behaviour (spec 1.8 section 5) with the real Enemy, Player, WorldObstacles and plan: the arena's SpawnDirector still
## teleports and chases; dormant members stay put; one wakes within 300 px with a clear line and not beyond it or behind a
## wall; waking and damage alert the neighbours within 96 px and not those farther; an awake member beyond 600 px or without
## sight for the lose-sight time goes home, heals and is dormant; a rest point keeps dormant members asleep and sends awake
## ones home; a stuck member goes home (or is placed or dropped), never to the spawn ring.
## Run: godot --headless --path . --script tests/overworld/horde_behavior.gd

const Plan := preload("res://scripts/overworld/horde_plan.gd")

var _failed := false
var _F: GDScript
var _H: GDScript
var _ctx: Dictionary
var _d
var _hero


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	_F = load("res://tests/fixture.gd")
	_H = load("res://tests/overworld/horde_fixture.gd")
	await _arena_unchanged()
	await _dormant_and_wake()
	await _alert()
	await _leash()
	await _sight()
	await _safe()
	await _stuck()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _start(overrides := {}) -> void:
	_ctx = await _H.build(self, overrides)
	_d = _ctx.director
	_hero = _ctx.player


func _stop() -> void:
	await _H.finish(self, _ctx)


## Puts the hero 700 px from `h` and waits until it is materialised; returns its members.
func _materialise(h) -> Array:
	_d.reset()
	_hero.global_position = h.home + Vector2(700, 0)
	for i in 200:
		await physics_frame
		if _d._live.has(h.id):
			break
	await physics_frame
	return _d._live[h.id].members if _d._live.has(h.id) else []


## A horde of zone 0 (not a den, so it is small) with at least one member that has a neighbour within and one beyond 96 px.
func _alert_pair() -> Variant:
	for h in _ctx.plan:
		if h.zone != 0 or h.kind == Plan.KIND_DEN or h.members.size() < 6:
			continue
		var pos := Plan.member_positions(_ctx.world, h)
		for i in pos.size():
			var near := 0
			var far := 0
			for j in pos.size():
				if i != j:
					if pos[i].distance_to(pos[j]) <= 96.0:
						near += 1
					elif pos[i].distance_to(pos[j]) > 110.0:
						far += 1
			if near >= 1 and far >= 1:
				return [h, i]
	return null


## A hero spot `radius` px from `a` on a walkable tile whose line to `a` is clear (or blocked); null when none.
func _spot(a: Vector2, radius: float, clear: bool, hitbox := 8.0) -> Variant:
	for k in 48:
		var p := a + Vector2.from_angle(TAU * k / 48.0) * radius
		if not _ctx.world.is_walkable(WorldData.tile_of(p)):
			continue
		if _ctx.obstacles.segment_clear(a, p, hitbox) == clear:
			return p
	return null


## [horde, member index, clear250, clear330, blocked] for the first horde with such a member, or null.
func _wake_case() -> Variant:
	for h in _ctx.plan:
		if h.zone != 0 or h.members.size() < 3:
			continue
		var pos := Plan.member_positions(_ctx.world, h)
		for i in mini(pos.size(), 3):
			var c250 = _spot(pos[i], 250.0, true)
			var c330 = _spot(pos[i], 330.0, true)
			var blocked = null
			for r in [90.0, 130.0, 170.0, 210.0, 250.0]:
				blocked = _spot(pos[i], r, false)
				if blocked != null:
					break
			if c250 != null and c330 != null and blocked != null:
				return [h, i, c250, c330, blocked]
	return null


func _arena_unchanged() -> void:
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 3)
	var p = _F.player()
	var sd = main.spawn_director
	_check(sd.teleport_distance < 1000.0, "the arena director has a finite teleport distance")
	var e = sd._acquire(sd.enemy_types[0])
	e.activate(p.global_position + Vector2(1300, 0), 1.0)
	_check(e.state == e.State.CHASE, "an arena enemy is CHASE")
	await _F.frames(self, 3)
	_check(e.global_position.distance_to(p.global_position) < 700.0, "an arena enemy beyond the distance teleports to the ring")
	var d0: float = e.global_position.distance_to(p.global_position)
	await _F.seconds(self, 0.5)
	_check(e.global_position.distance_to(p.global_position) < d0 - 5.0 or p.health.current < p.health.max_health,
		"and chases the hero")
	main.queue_free()
	await process_frame
	paused = false


func _dormant_and_wake() -> void:
	await _start({alert_radius = 0.0})
	var c = _wake_case()
	_check(c != null, "a zone 0 member with a clear 250 px, a clear 330 px and a blocked spot exists")
	if c == null:
		await _stop()
		return
	var h = c[0]
	var members := await _materialise(h)
	var a = members[c[1]]
	var spots: Array[Vector2] = []
	for e in members:
		_check(e.state == e.State.DORMANT, "members are dormant when materialised")
		spots.append(e.global_position)
	await _F.seconds(self, 1.0)
	var moved := 0
	for i in members.size():
		if members[i].global_position.distance_to(spots[i]) > 0.01:
			moved += 1
	_check(moved == 0, "dormant members stay put (%d moved)" % moved)
	# 330 px with a clear line: asleep.
	_hero.global_position = c[3]
	await _F.seconds(self, 0.8)
	_check(a.state == a.State.DORMANT, "a member 330 px from the hero stays asleep")
	# 250 px but behind a wall: asleep.
	_hero.global_position = c[4]
	await _F.seconds(self, 0.8)
	_check(a.state == a.State.DORMANT, "a member behind a wall stays asleep")
	# 250 px with a clear line: wakes within a check interval or two.
	_hero.global_position = c[2]
	await _F.seconds(self, 0.6)
	_check(a.state == a.State.CHASE, "a member 250 px away with a clear line wakes (state %d)" % a.state)
	await _stop()


func _alert() -> void:
	await _start()
	var pair = _alert_pair()
	_check(pair != null, "a horde with a close and a far neighbour exists")
	if pair == null:
		await _stop()
		return
	var members := await _materialise(pair[0])
	var a = members[pair[1]]
	_d._wake(a)
	var near := 0
	var far := 0
	var wrong := 0
	for e in members:
		if e == a:
			continue
		var close: bool = e.global_position.distance_to(a.global_position) <= 96.0
		if close:
			near += 1
		else:
			far += 1
		if close != (e.state == e.State.CHASE):
			wrong += 1
	_check(near >= 1 and far >= 1, "the case has members within and beyond 96 px")
	_check(wrong == 0, "waking one wakes exactly the members within 96 px (%d wrong)" % wrong)
	# Damage wakes the horde too.
	members = await _materialise(pair[0])
	a = members[pair[1]]
	var neighbour = null
	for e in members:
		if e != a and e.global_position.distance_to(a.global_position) <= 96.0:
			neighbour = e
	a.take_damage(1.0)
	_check(a.state == a.State.CHASE, "a hit wakes the member")
	_check(neighbour.state == neighbour.State.CHASE, "and its close neighbour")
	await _stop()


func _leash() -> void:
	await _start()
	var h = _alert_pair()[0]
	var members := await _materialise(h)
	var arrived := [0]
	for e in members:
		e.arrived_home.connect(func(_x) -> void: arrived[0] += 1)
	var a = members[0]
	a.health.current = 1.0
	_d._wake(a)
	_check(a.state == a.State.CHASE, "the member is awake")
	await _F.seconds(self, 0.5)  # the hero is 700 px away: beyond the 600 px leash
	_check(a.state != a.State.CHASE, "an awake member beyond the leash gives up (state %d)" % a.state)
	await _F.seconds(self, 2.5)
	_check(a.state == a.State.DORMANT, "and is dormant again at its post (state %d)" % a.state)
	_check(a.health.current == a.health.max_health, "healed to full")
	_check(a.global_position.distance_to(a.home) <= 8.0, "standing at home")
	_check(arrived[0] >= 1, "arrived_home was emitted")
	await _stop()


func _sight() -> void:
	await _start({alert_radius = 0.0, lose_sight_time = 0.5})
	var c = _wake_case()
	var members := await _materialise(c[0])
	var a = members[c[1]]
	a.set_physics_process(false)  # it stays where it is: only the director's check acts
	_hero.global_position = c[2]
	_d._wake(a)
	await _F.seconds(self, 1.2)
	_check(a.state == a.State.CHASE, "an awake member that sees the hero keeps chasing")
	_hero.global_position = c[4]
	await _F.seconds(self, 0.3)
	_check(a.state == a.State.CHASE, "it does not give up at once")
	await _F.seconds(self, 1.2)
	_check(a.state == a.State.RETURNING, "without sight for the lose-sight time it returns (state %d)" % a.state)
	await _stop()


func _safe() -> void:
	await _start({alert_radius = 0.0, wake_radius = 5000.0})
	var camp: Vector2 = _ctx.director.safe_points[0]
	_check(camp.distance_to(WorldData.marker_world(_ctx.world.start_marker())) < 1.0, "safe_points start with the start camp")
	var found = null
	for sp in _d.safe_points:
		for h in _ctx.plan:
			if h.home.distance_to(sp) < 700.0:
				found = h
				camp = sp
				break
		if found != null:
			break
	_check(found != null, "a horde stands within 700 px of a rest point")
	if found == null:
		await _stop()
		return
	_d.reset()
	_hero.global_position = camp
	for i in 100:
		await physics_frame
	var members: Array = _d._live[found.id].members if _d._live.has(found.id) else []
	_check(not members.is_empty(), "the horde near the camp materialises")
	await _F.seconds(self, 0.8)
	var awake := 0
	for e in members:
		if e.state != e.State.DORMANT:
			awake += 1
	_check(awake == 0, "no dormant member wakes while the hero is in a rest point's radius (%d did)" % awake)
	var a = members[0]
	_d._wake(a)
	await _F.seconds(self, 0.5)
	_check(a.state == a.State.RETURNING or a.state == a.State.DORMANT, "an awake member returns while the hero rests (state %d)" % a.state)
	_hero.global_position = a.global_position + Vector2(20, 0)
	await _F.seconds(self, 0.6)
	_check(a.state == a.State.CHASE, "outside the radius it wakes again (state %d)" % a.state)
	await _stop()


func _stuck() -> void:
	await _start()
	var h = _alert_pair()[0]
	var members := await _materialise(h)
	var a = members[0]
	_d._wake(a)
	var before: Vector2 = a.global_position
	_d.on_stuck(a)
	_check(a.state == a.State.RETURNING, "a stuck chaser is sent home")
	_check(a.global_position == before, "it does not teleport")
	a.global_position = a.home + Vector2(30, 0)
	_hero.global_position = a.home + Vector2(2000, 0)
	_d.on_stuck(a)
	_check(a.global_position == a.home, "a stuck returning member off screen is placed at its post")
	var b = members[1]
	_d._wake(b)
	b.send_home()
	_hero.global_position = b.home + Vector2(100, 0)
	var live: int = _d.live_count()
	_d.on_stuck(b)
	_check(not b.active and _d.live_count() == live - 1, "a stuck returning member in view is dropped")
	_check(not _d._live[h.id].members.has(b), "and leaves its horde")
	# Through the enemy itself: the failsafe calls the director's hook (the base class has none to fall back on).
	_check(a.director.has_method("on_stuck"), "enemies find the hook")
	await _stop()

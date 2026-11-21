extends SceneTree
## HordeDirector (spec 1.8 section 7) on the real world, plan and a real hero (the shared fixture, tests/overworld/horde_fixture.gd):
## hordes materialise within 800 px and not before, one per frame, never in the view while the hero walks the zone 0 route,
## the live count stays within the cap; dormant hordes dematerialise beyond 1,200 px and awake ones stay; pools reuse enemies
## and dress them with their zone's look; a kill drops XP with the horde's multiplier and the last kill of a den clears it
## (and it never materialises again, also with a reloaded journey); a road horde regrows after the hero leaves and returns;
## `reset()` clears all; `prewarm` instantiates a few per frame.
## Run: godot --headless --path . --script tests/overworld/horde_director.gd

const Plan := preload("res://scripts/overworld/horde_plan.gd")
const JourneyS := preload("res://scripts/overworld/journey.gd")

var _failed := false
var _F: GDScript
var _ctx: Dictionary
var _d
var _hero
var _seen := {}  # live horde ids at the end of the previous frame
var _max_new := 0
var _max_live := 0
var _in_view := 0
var _check_view := false
var _cleared := []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var H: GDScript = load("res://tests/overworld/horde_fixture.gd")
	_F = load("res://tests/fixture.gd")
	_ctx = await H.build(self)
	_d = _ctx.director
	_hero = _ctx.player
	_d.den_cleared.connect(func(kind: String, marker: int) -> void: _cleared.append([kind, marker]))
	await _prewarm()
	await _radii()
	await _pools_and_looks()
	await _kills_and_dens()
	await _regrow()
	await _awake_stays()
	await _cap()
	await _walk_route()
	_d.reset()
	_check(_d.live_count() == 0 and _d.live_horde_ids().is_empty(), "reset clears all")
	await H.finish(self, _ctx)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## One physics frame, tracking how many hordes appeared in it, the live count and (when asked) members in the view.
func _step(n := 1) -> void:
	for i in n:
		await physics_frame
		var ids: Array = _d.live_horde_ids()
		var fresh := 0
		for id in ids:
			if not _seen.has(id):
				fresh += 1
				if _check_view:
					var view := Rect2(_hero.global_position - Vector2(320, 180), Vector2(640, 360))
					for e in _d._live[id].members:
						if view.has_point(e.global_position):
							_in_view += 1
		_max_new = maxi(_max_new, fresh)
		_max_live = maxi(_max_live, _d.live_count())
		_seen = {}
		for id in ids:
			_seen[id] = true


func _horde(id: String):
	for h in _ctx.plan:
		if h.id == id:
			return h
	return null


## The first horde of `kind` in `zone` with at least `min_size` members.
func _find(kind: StringName, zone: int, min_size := 1, skip := 0):
	for h in _ctx.plan:
		if h.kind == kind and h.zone == zone and h.members.size() >= min_size:
			if skip == 0:
				return h
			skip -= 1
	return null


func _wait_live(id: String, frames: int) -> bool:
	for i in frames:
		await _step()
		if _d._live.has(id):
			return true
	return false


func _prewarm() -> void:
	var before: int = _ctx.enemies.get_child_count()
	_d.prewarm(2)
	var queued: int = _d.prewarm_pending()
	_check(queued == 6, "prewarm(2) queues 2 of each of 3 types (got %d)" % queued)
	await _step()
	_check(_d.prewarm_pending() == queued - 3, "prewarm makes a few per frame (left %d)" % _d.prewarm_pending())
	await _step(3)
	_check(_d.prewarm_pending() == 0, "prewarm finishes")
	_check(_ctx.enemies.get_child_count() == before + 6, "six enemies instantiated")
	_check(_d.live_count() == 0, "prewarmed enemies are not live")
	var active := 0
	for e in _ctx.enemies.get_children():
		if e.active:
			active += 1
	_check(active == 0, "prewarmed enemies are inactive")


func _radii() -> void:
	var h = _find(Plan.KIND_ROUTE, 0, 4)
	var dir := Vector2.RIGHT
	_hero.global_position = h.home + dir * 850.0
	await _step(40)
	_check(not _d._live.has(h.id), "a horde 850 px away is not materialised")
	_hero.global_position = h.home + dir * 780.0
	_check_view = false
	_check(await _wait_live(h.id, 120), "a horde 780 px away materialises")
	var live: Array = _d._live[h.id].members
	_check(live.size() == _positions(h).size(), "all members placed (%d of %d)" % [live.size(), _positions(h).size()])
	var view := Rect2(_hero.global_position - Vector2(320, 180), Vector2(640, 360))
	var inside := 0
	for e in live:
		_check(e.state == e.State.DORMANT, "materialised members are DORMANT")
		_check(e.data.id == h.members[live.find(e)], "member types follow the plan")
		if view.has_point(e.global_position):
			inside += 1
	_check(inside == 0, "no member of it is inside the view")
	_check(_d.horde_of(live[0]) == h, "horde_of maps a member to its plan entry")
	_check(_max_new <= 1, "at most one horde materialises per frame (saw %d)" % _max_new)
	# Dematerialise only beyond 1,200 px.
	_hero.global_position = h.home + dir * 1100.0
	await _step(40)
	_check(_d._live.has(h.id), "a dormant horde 1100 px away stays")
	_hero.global_position = h.home + dir * 1300.0
	await _step(5)
	_check(not _d._live.has(h.id), "a dormant horde 1300 px away dematerialises")
	_hero.global_position = Vector2(31900, 100)
	await _step(5)
	_d.reset()


func _positions(h) -> PackedVector2Array:
	return Plan.member_positions(_ctx.world, h)


func _pools_and_looks() -> void:
	for zone in [0, 1]:
		var h = _find(Plan.KIND_ROUTE_BIG, zone, 8)
		if h == null:
			h = _find(Plan.KIND_TRAIL, zone, 4)
		_check(h != null, "a horde exists in zone %d" % zone)
		if h == null:
			continue
		_hero.global_position = h.home + Vector2(700, 0)
		_hero.global_position = h.home + Vector2(700, 0)
		await _step(100)  # the same neighbourhood materialises each time
		_check(_d._live.has(h.id), "zone %d horde materialises" % zone)
		var theme = MapRegistry.by_id(StringName(_ctx.world.zones[zone].id))
		var dressed := 0
		for e in _d._live[h.id].members:
			var v = theme.variant_for(e.data.id)
			if v != null:
				_check(e.sprite.body_color == v.body_color, "zone %d %s wears the zone's look" % [zone, e.data.id])
				dressed += 1
		_check(dressed > 0, "zone %d has a variant for some member type" % zone)
		var count: int = _ctx.enemies.get_child_count()
		var live_ids: Array = _d.live_horde_ids().duplicate()
		live_ids.sort()
		_d.reset()
		_check(_d.live_count() == 0, "reset releases all")
		await _step(2)
		_hero.global_position = h.home + Vector2(700, 0)
		await _step(100)
		var again: Array = _d.live_horde_ids().duplicate()
		again.sort()
		_check(again == live_ids, "the same hordes materialise again")
		_check(_ctx.enemies.get_child_count() == count, "the second materialisation reuses pooled enemies (%d vs %d)"
			% [_ctx.enemies.get_child_count(), count])
		_d.reset()
		_hero.global_position = Vector2(31900, 100)
		await _step(3)


func _kills_and_dens() -> void:
	var h = _find(Plan.KIND_DEN, 0, 10)
	_check(h != null and h.xp_mult > 1.0, "zone 0 has a den with an xp multiplier above 1")
	_hero.global_position = h.home + Vector2(700, 0)
	_check(await _wait_live(h.id, 160), "the den materialises")
	var members: Array = _d._live[h.id].members.duplicate()
	var first = members[0]
	var want := roundi(first.data.xp_drop * h.xp_mult)
	_ctx.rewards.gems.clear()
	first.take_damage(1.0e9)
	_check(_ctx.rewards.gems.size() == 1 and _ctx.rewards.gems[0][1] == want,
		"a kill drops XP xp_drop x xp_mult (%s, wanted %d)" % [str(_ctx.rewards.gems), want])
	_check(_ctx.rewards.magnets == 1, "a kill rolls the magnet")
	_check(not _d._live[h.id].members.has(first), "the dead member leaves its horde")
	_check(_cleared.is_empty(), "a den is not cleared by one kill")
	for e in members:
		if e != first and e.active:
			e.take_damage(1.0e9)
	var marker_kind: String = _ctx.world.markers[h.marker].kind
	_check(_cleared.size() == 1 and _cleared[0] == [marker_kind, h.marker], "den_cleared fires once (%s)" % str(_cleared))
	_check(_ctx.journey.is_den_cleared(marker_kind, h.marker), "the journey marks the den cleared")
	var still := 0
	for e in members:
		if e.active:
			still += 1
	_check(still == 0, "every member of the den is back in the pool")
	await _step(40)
	_check(not _d._live.has(h.id) or _d._live[h.id].members.is_empty(), "a cleared den does not rematerialise while the hero stays")
	_hero.global_position = Vector2(31900, 100)
	await _step(5)
	_check(not _d._live.has(h.id), "the spent den entry goes when the hero is far")
	_hero.global_position = h.home + Vector2(700, 0)
	await _step(60)
	_check(not _d._live.has(h.id), "a cleared den never materialises again")
	# A journey reloaded from its saved list.
	var j2 = JourneyS.new_for(&"knight", _ctx.world)
	j2.cleared_dens = _ctx.journey.cleared_dens.duplicate()
	_d.reset()
	_d.journey = j2
	await _step(60)
	_check(not _d._live.has(h.id), "nor with the journey reloaded")
	var fresh = JourneyS.new_for(&"knight", _ctx.world)
	_d.journey = fresh
	_check(await _wait_live(h.id, 120), "with an empty journey the den is back")
	_d.reset()
	_d.journey = _ctx.journey
	_hero.global_position = Vector2(31900, 100)
	await _step(3)


func _regrow() -> void:
	var h = _find(Plan.KIND_ROUTE, 0, 4, 2)
	_hero.global_position = h.home + Vector2(700, 0)
	_check(await _wait_live(h.id, 160), "a road horde materialises")
	var n: int = _d._live[h.id].members.size()
	for e in _d._live[h.id].members.duplicate():
		e.take_damage(1.0e9)
	_check(_d._live.has(h.id) and _d._live[h.id].members.is_empty(), "a killed road horde is spent")
	await _step(40)
	_check(_d._live[h.id].members.is_empty(), "a spent road horde does not regrow while the hero stays near")
	_hero.global_position = Vector2(31900, 100)
	await _step(5)
	_check(not _d._live.has(h.id), "it is forgotten when the hero is far")
	_hero.global_position = h.home + Vector2(700, 0)
	_check(await _wait_live(h.id, 160), "it regrows when the hero returns")
	_check(_d._live[h.id].members.size() == n, "whole again (%d of %d)" % [_d._live[h.id].members.size(), n])
	_d.reset()
	_hero.global_position = Vector2(31900, 100)
	await _step(3)


## An awake member keeps its horde materialised however far the hero goes (it must get home first).
func _awake_stays() -> void:
	var h = _find(Plan.KIND_ROUTE, 0, 4, 3)
	_hero.global_position = h.home + Vector2(700, 0)
	_check(await _wait_live(h.id, 160), "a horde materialises for the awake test")
	var a = _d._live[h.id].members[0]
	a.wake()
	a.set_physics_process(false)  # it cannot walk home, so it stays awake or returning
	_hero.global_position = Vector2(31900, 100)
	await _step(60)
	_check(_d._live.has(h.id), "a horde with an awake member is kept (state %d)" % a.state)
	a.set_physics_process(true)
	await _step(60)
	_check(not _d._live.has(h.id), "it dematerialises once everyone is home and dormant")
	_d.reset()


func _cap() -> void:
	var h = _find(Plan.KIND_DEN, 0, 10)
	_d.rules.max_alive = 20
	_hero.global_position = h.home + Vector2(300, 0)
	_max_live = 0
	await _step(120)
	_check(_max_live <= 20, "the cap holds (max live %d of 20)" % _max_live)
	_check(_d.live_count() > 0, "something is live under the cap")
	_d.reset()
	_d.rules.max_alive = 120
	_hero.global_position = Vector2(31900, 100)
	await _step(3)


## Walks the whole zone 0 route at 16 px a frame.
func _walk_route() -> void:
	var path: Array = _ctx.world.main_path
	var end: int = _ctx.world.zones[0].route_end_tile
	_hero.global_position = WorldData.world_of(path[0])
	_check_view = false
	await _step(80)
	_check_view = true
	_max_new = 0
	_max_live = 0
	_in_view = 0
	var cap: int = _d.rules.max_alive
	var materialised := {}
	for i in range(0, mini(end, path.size())):
		_hero.global_position = WorldData.world_of(path[i])
		await _step()
		for id in _seen:
			materialised[id] = true
	_check_view = false
	print("walk: %d hordes materialised, max live %d, max new per frame %d, members seen in view %d" % [
		materialised.size(), _max_live, _max_new, _in_view])
	_check(materialised.size() > 20, "walking the route meets hordes (%d)" % materialised.size())
	_check(_max_live <= cap, "live count stays within the cap (%d of %d)" % [_max_live, cap])
	_check(_max_new <= 1, "at most one horde per frame while walking (%d)" % _max_new)
	_check(_in_view == 0, "no horde materialises inside the view (%d members)" % _in_view)

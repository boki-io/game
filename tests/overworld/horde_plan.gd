extends SceneTree
## The horde plan (spec 1.8 section 4 and 11), pure, on the real world data and a fake sites object (route sites sampled
## from the main path, trails faked as snapped straight lines from each far marker to the road, so the test does not need
## content/overworld/data/horde_sites.json): two builds are identical, ids are unique and well formed, every home is
## walkable and outside the safe radius, there is a den at every camp and cache and nowhere else, sizes are in their ranges
## and ordered den > trail > small route, zone 0's small road hordes are grunts and its dens hold shooters and chargers,
## the big share is near the data's chance, members are spread, on open ground, outside the safe radius, no two homes are
## closer than the gap, and the random streams are independent. The rules hold for 30 seeds.
## Run: godot --headless --path . --script tests/overworld/horde_plan.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const Plan := preload("res://scripts/overworld/horde_plan.gd")
const Rules := preload("res://scripts/overworld/horde_rules.gd")
const SEED_COUNT := 30
const SAFE_KINDS := ["start_camp", "checkpoint", "gate"]
const TRAIL_KINDS := ["camp", "cache", "cave", "dungeon", "special"]

var _failed := false
var _world
var _sites
var _safe := []
## Sums over the seeds: [count, total size] per kind and zone 0's big and small route counts.
var _sizes := {}
var _z0_route := 0
var _z0_big := 0


## What `HordePlan` reads of `HordeSites`: `routes` and `trails`.
class FakeSites extends RefCounted:
	var routes: Array[Dictionary] = []
	var trails: Array[Dictionary] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_world = WorldDataS.shared()
	for m in _world.markers:
		if m.kind in SAFE_KINDS:
			_safe.append(WorldDataS.marker_world(m))
	_sites = _fake_sites()
	var rules: Rules = load("res://content/overworld/hordes.tres")
	_check(rules != null and rules.den_weights.size() == 8, "hordes.tres loads with a row per zone")
	var plan := Plan.build(_world, _sites, rules)
	print("sites: %d route, %d trails; plan: %d hordes" % [_sites.routes.size(), _sites.trails.size(), plan.size()])
	_reproducible(rules, plan)
	_streams_independent(rules, plan)
	_rules_hold(rules, plan, true)
	_statistics(plan)
	for i in SEED_COUNT:
		var r: Rules = rules.duplicate()
		r.seed = rules.seed + i
		_rules_hold(r, Plan.build(_world, _sites, r), false)
	_aggregate()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Route sites every 8 main-path points; for each trail marker more than 20 tiles from the road, points every 40 tiles from
## 30 tiles out to the marker along the straight line, each snapped to a walkable tile within 6 tiles (else skipped).
func _fake_sites() -> FakeSites:
	var sites := FakeSites.new()
	var path: Array = _world.main_path
	for i in range(0, path.size(), 8):
		var tile: Vector2i = path[i]
		if _near_safe(WorldDataS.world_of(tile)):
			continue
		var zone: int = _world.zone_at(tile)
		var z: Dictionary = _world.zones[zone]
		var t := clampf((float(i) * 8.0 - float(z.route_start_tile)) / float(z.route_end_tile - z.route_start_tile), 0.0, 1.0)
		sites.routes.append({"x": tile.x, "y": tile.y, "zone": zone, "t": t})
	for m in _world.markers.size():
		var mk: Dictionary = _world.markers[m]
		if not (mk.kind in TRAIL_KINDS):
			continue
		var at := Vector2(float(mk.x), float(mk.y))
		var road := Vector2.ZERO
		var best := INF
		for p in path:
			var d := Vector2(p).distance_to(at)
			if d < best:
				best = d
				road = Vector2(p)
		if best <= 20.0:
			continue
		var points := []
		var d := 30.0
		while d < best - 8.0:
			var tile := _snap((road + (at - road) * (d / best)).round())
			if tile.x >= 0:
				points.append({"x": tile.x, "y": tile.y, "t": d / best})
			d += 40.0
		if not points.is_empty():
			sites.trails.append({"marker": m, "kind": mk.kind, "points": points})
	return sites


func _snap(tile: Vector2i) -> Vector2i:
	for r in 7:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and _world.is_walkable(tile + Vector2i(dx, dy)):
					return tile + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func _near_safe(p: Vector2) -> bool:
	for s in _safe:
		if s.distance_to(p) < 14.0 * 16.0:
			return true
	return false


## A line of everything a horde is, to compare two builds.
func _digest(h) -> String:
	return "%s|%s|%s|%d|%d|%d|%s|%.4f|%.4f|%d|%s" % [h.id, h.kind, h.home, h.zone, h.tier, h.size, h.members, h.hp_mult, h.xp_mult, h.seed, h.radius]


func _reproducible(rules, plan: Array) -> void:
	var again := Plan.build(_world, _sites, rules)
	_check(again.size() == plan.size(), "two builds have the same number of hordes")
	for i in mini(again.size(), plan.size()):
		if _digest(again[i]) != _digest(plan[i]):
			_check(false, "horde %s is identical across two builds" % plan[i].id)
			break
	for i in range(0, plan.size(), 9):
		_check(Plan.member_positions(_world, plan[i]) == Plan.member_positions(_world, plan[i]), "member positions of %s repeat" % plan[i].id)


## Tuning one rule moves no other: new trail sizes leave every road horde's members alone, and new road sizes leave the big
## or small choice alone.
func _streams_independent(rules, plan: Array) -> void:
	var r: Rules = rules.duplicate()
	r.trail_size = Vector2i(11, 14)
	r.route_size = Vector2i(9, 9)
	var other := Plan.build(_world, _sites, r)
	var by_id := {}
	for h in other:
		by_id[h.id] = h
	var same_members := 0
	var checked := 0
	for h in plan:
		if h.id.begins_with("route:") and by_id.has(h.id):
			_check(by_id[h.id].kind == h.kind, "%s keeps its big or small choice when sizes change" % h.id)
		if h.kind == &"route_big" and by_id.has(h.id):
			checked += 1
			if by_id[h.id].members == h.members:
				same_members += 1
		if h.kind == &"den" and by_id.has(h.id):
			_check(by_id[h.id].members == h.members and by_id[h.id].home == h.home, "%s ignores trail and road sizes" % h.id)
	_check(checked == 0 or same_members == checked, "big road hordes ignore the small road size")


## The plan rules; `deep` also checks every den's spread and a sample of the others (the other seeds sample fewer).
func _rules_hold(rules, plan: Array, deep: bool) -> void:
	var tag := "seed %d: " % rules.seed
	var ids := {}
	var dens := {}
	var gap := float(rules.min_home_gap_tiles) * 16.0
	for h in plan:
		_check(not ids.has(h.id), tag + "id %s is unique" % h.id)
		ids[h.id] = true
		_check(_id_ok(h), tag + "id %s fits its kind" % h.id)
		_check(_world.is_walkable(WorldDataS.tile_of(h.home)), tag + "%s home is walkable" % h.id)
		_check(not _near_safe(h.home), tag + "%s home is outside the safe radius" % h.id)
		_check(h.members.size() == h.size and h.size > 0, tag + "%s has its members" % h.id)
		_check(h.seed >= 0 and h.hp_mult >= 1.0 and h.xp_mult >= 1.0, tag + "%s scaling" % h.id)
		_check(h.zone == _world.zone_at(WorldDataS.tile_of(h.home)) or h.id.begins_with("arena:") or h.id.begins_with("guard:") or h.id.begins_with("den:"), tag + "%s zone matches its tile" % h.id)
		_check_size(rules, h, tag)
		if h.kind == &"den":
			dens[h.marker] = h
		var key := String(h.kind) if not h.id.begins_with("arena:") else "arena"
		var s: Array = _sizes.get([key, h.zone], [0, 0])
		_sizes[[key, h.zone]] = [s[0] + 1, s[1] + h.size]
		if h.zone == 0 and h.kind == &"route":
			for t in h.members:
				_check(t == &"grunt", tag + "%s: a small zone 0 road horde is grunts" % h.id)
		if h.zone == 0 and h.id.begins_with("route:"):
			_z0_route += 1
			if h.kind == &"route_big":
				_z0_big += 1
		if h.kind == &"den" and h.zone == 0:
			_check(h.members.has(&"ranged") and h.members.has(&"dasher"), tag + "%s holds a shooter and a charger" % h.id)
	for i in plan.size():
		for j in range(i + 1, plan.size()):
			if plan[i].home.distance_to(plan[j].home) < gap - 0.01:
				_check(false, tag + "%s and %s are closer than the gap" % [plan[i].id, plan[j].id])
	for m in _world.markers.size():
		var kind: String = _world.markers[m].kind
		_check(dens.has(m) == (kind == "camp" or kind == "cache"), tag + "a den at marker %d (%s) exactly for camps and caches" % [m, kind])
	for i in plan.size():
		var h = plan[i]
		if h.kind == &"den" or (deep and i % 6 == 0) or i % 40 == 0:
			_check_members(rules, h, tag, h.kind == &"den" and deep)


func _id_ok(h) -> bool:
	var parts: PackedStringArray = h.id.split(":")
	match h.kind:
		&"route":
			return parts.size() == 2 and parts[0] == "route"
		&"route_big":
			return parts.size() == 2 and parts[0] in ["route", "arena"]
		&"trail":
			return parts.size() == 3 and parts[0] == "trail"
		&"guard":
			return parts.size() == 2 and parts[0] == "guard"
		&"den":
			return parts.size() == 2 and parts[0] == "den"
	return false


func _check_size(rules, h, tag: String) -> void:
	var lo := 1
	var hi := 1000
	match h.kind:
		&"route":
			lo = rules.route_size.x
			hi = rules.route_size.y
		&"route_big":
			lo = rules.route_big_size.x
			hi = rules.route_big_size.y
		&"trail":
			lo = roundi(rules.trail_size.x)
			hi = roundi(rules.trail_size.y * (1.0 + rules.trail_size_ramp))
		&"guard":
			lo = rules.guard_size.x
			hi = rules.guard_size.y
		&"den":
			var camp: bool = _world.markers[h.marker].kind == "camp"
			lo = rules.den_size.x if camp else rules.cache_den_size.x
			hi = rules.den_size.y if camp else rules.cache_den_size.y
	_check(h.size >= lo and h.size <= hi, tag + "%s size %d is in %d to %d" % [h.id, h.size, lo, hi])


func _check_members(rules, h, tag: String, spread: bool) -> void:
	var pos: PackedVector2Array = Plan.member_positions(_world, h)
	_check(pos.size() <= h.members.size() and pos.size() >= (h.size * 6) / 10, tag + "%s places most members (%d of %d)" % [h.id, pos.size(), h.size])
	for p in pos:
		_check(_open(p), tag + "%s member at %s is on open ground" % [h.id, p])
		_check(not _near_safe(p), tag + "%s member is outside the safe radius" % h.id)
	var nn_total := 0.0
	var far := 0.0
	for i in pos.size():
		var nn := INF
		for j in pos.size():
			if i != j:
				nn = minf(nn, pos[i].distance_to(pos[j]))
		nn_total += nn if nn < INF else 0.0
		far = maxf(far, pos[i].distance_to(h.home))
		if nn < INF:
			_check(nn >= rules.member_spacing_px - 0.01, tag + "%s members keep their spacing" % h.id)
	if spread and pos.size() > 1:
		_check(nn_total / pos.size() >= rules.member_spacing_px, tag + "%s mean nearest-neighbour distance %.1f" % [h.id, nn_total / pos.size()])
		_check(far >= 5.0 * 16.0, tag + "%s members cover at least 5 tiles (%.0f px)" % [h.id, far])


## A walkable tile at least 2 tiles from a blocked one (a disc of 2 tiles is walkable).
func _open(p: Vector2) -> bool:
	var tile: Vector2i = WorldDataS.tile_of(p)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 4 and not _world.is_walkable(tile + Vector2i(dx, dy)):
				return false
	return true


## The shipped plan: the means order den > trail > small route, and the big share is near the data's.
func _statistics(plan: Array) -> void:
	var count := {}
	var total := {}
	var route := 0
	var big := 0
	for h in plan:
		var k := String(h.kind)
		count[k] = count.get(k, 0) + 1
		total[k] = total.get(k, 0) + h.size
		if h.id.begins_with("route:"):
			route += 1
			if h.kind == &"route_big":
				big += 1
	var line := "plan:"
	for k in count:
		line += " %s %d (mean %.1f)" % [k, count[k], float(total[k]) / count[k]]
	print(line)
	var placed := 0
	var asked := 0
	for h in plan:
		if h.kind == &"den":
			placed += Plan.member_positions(_world, h).size()
			asked += h.size
	print("den members placed: %d of %d" % [placed, asked])
	var share := float(big) / maxf(1.0, float(route))
	print("route_big share, shipped seed, whole map: %.1f%% of %d" % [share * 100.0, route])
	_check(share >= 0.08 and share <= 0.28, "the big share of the shipped plan is 8 to 28%%")
	var den_mean: float = float(total["den"]) / count["den"]
	var trail_mean: float = float(total["trail"]) / count["trail"]
	var route_mean: float = float(total["route"]) / count["route"]
	_check(den_mean > trail_mean and trail_mean > route_mean, "mean size den > trail > small route")


## The figures summed over all seeds: zone 0's big share, and the mean size order per zone where each kind exists.
func _aggregate() -> void:
	var share := float(_z0_big) / maxf(1.0, float(_z0_route))
	print("zone 0 route_big share over %d seeds: %.1f%% of %d" % [SEED_COUNT + 1, share * 100.0, _z0_route])
	_check(share >= 0.08 and share <= 0.28, "zone 0's big share over all seeds is 8 to 28%%")
	for z in 8:
		var d: Array = _sizes.get(["den", z], [0, 0])
		var t: Array = _sizes.get(["trail", z], [0, 0])
		var r: Array = _sizes.get(["route", z], [0, 0])
		if d[0] > 0 and t[0] > 0 and r[0] > 0:
			_check(float(d[1]) / d[0] > float(t[1]) / t[0] and float(t[1]) / t[0] > float(r[1]) / r[0], "zone %d: mean den > trail > small route" % z)

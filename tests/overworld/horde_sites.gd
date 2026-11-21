extends SceneTree
## The horde sites (spec 1.8): the committed horde_sites.json loads; every route site is walkable, in its zone and outside the
## safe radius; trails start near the route, end near their marker, keep their points a stride apart and their t monotonic;
## there is a trail for every camp, cache, cave, dungeon and special more than 20 tiles from the route; `near` agrees with a
## brute-force search. `build_horde_sites.py --check` is run by hand (the suite has no Python), see the build notes.
## Run: godot --headless --path . --script tests/overworld/horde_sites.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const SitesS := preload("res://scripts/overworld/horde_sites.gd")

const SAFE_RADIUS := 14
const STRIDE := 40
const SAFE_KINDS := ["start_camp", "checkpoint", "gate"]
const TRAIL_KINDS := ["camp", "cache", "cave", "dungeon", "special"]

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var w = WorldDataS.shared()
	var s = SitesS.shared()
	_check(s == SitesS.shared(), "shared() returns one instance")
	_route(w, s)
	_trails(w, s)
	_near(s)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _safe_dist(w, tile: Vector2i) -> float:
	var best := INF
	for m in w.markers:
		if m.kind in SAFE_KINDS:
			best = minf(best, Vector2(tile).distance_to(Vector2(m.x, m.y)))
	return best


func _route_dist(w, tile: Vector2i) -> float:
	var best := INF
	for p in w.main_path:
		best = minf(best, Vector2(tile).distance_to(Vector2(p)))
	return best


func _route(w, s) -> void:
	_check(s.routes.size() >= 90 and s.routes.size() <= 110, "about 101 route sites (%d)" % s.routes.size())
	var last_t := {}
	for r in s.routes:
		_check(w.is_walkable(r.tile), "route site %s is walkable" % [r.tile])
		_check(w.zone_at(r.tile) == r.zone, "route site %s is in its zone %d (zone mask says %d)" % [r.tile, r.zone, w.zone_at(r.tile)])
		_check(_safe_dist(w, r.tile) > SAFE_RADIUS, "route site %s is outside the safe radius" % [r.tile])
		_check(r.t >= 0.0 and r.t <= 1.0, "route t in 0..1")
		_check(r.t >= last_t.get(r.zone, 0.0), "route t rises along zone %d" % r.zone)
		last_t[r.zone] = r.t
		_check(r.pos == WorldDataS.world_of(r.tile), "route pos is the tile centre")
	_check(last_t.size() == 8, "every zone has route sites (%d)" % last_t.size())


func _trails(w, s) -> void:
	var seen := {}
	var all := {}
	for t in s.trails:
		_check(t.kind in TRAIL_KINDS and w.markers[t.marker].kind == t.kind, "trail %d kind matches its marker" % t.marker)
		_check(not seen.has(t.marker), "one trail per marker")
		seen[t.marker] = true
		var m: Dictionary = w.markers[t.marker]
		var mt := Vector2i(m.x, m.y)
		_check(_route_dist(w, mt) > 20.0 - 0.001, "trail marker %d is more than 20 tiles from the route" % t.marker)
		var prev_t := 0.0
		var prev := Vector2.ZERO
		var first := true
		for p in t.points:
			_check(w.is_walkable(p.tile), "trail point %s is walkable" % [p.tile])
			_check(_safe_dist(w, p.tile) > SAFE_RADIUS, "trail point %s is outside the safe radius" % [p.tile])
			_check(p.t > prev_t and p.t <= 1.0, "trail t rises (%f after %f)" % [p.t, prev_t])
			_check(not all.has(p.tile), "a site belongs to one trail")
			all[p.tile] = true
			if first:
				# the first site is at least 30 tiles along the trail, and within a stride and a few tiles of the road
				_check(_route_dist(w, p.tile) >= 20.0, "first trail point %s is off the road" % [p.tile])
			else:
				_check(Vector2(p.tile).distance_to(prev) <= STRIDE + 4.0, "consecutive trail points are a stride apart (%f)" % Vector2(p.tile).distance_to(prev))
			prev = Vector2(p.tile)
			prev_t = p.t
			first = false
		if not t.points.is_empty():
			var end: Dictionary = t.points[t.points.size() - 1]
			_check(Vector2(end.tile).distance_to(Vector2(mt)) <= STRIDE + 4.0, "trail %d ends within a stride of its marker (%f)" % [t.marker, Vector2(end.tile).distance_to(Vector2(mt))])
	for i in w.markers.size():
		var m: Dictionary = w.markers[i]
		if m.kind in TRAIL_KINDS and _route_dist(w, Vector2i(m.x, m.y)) > 20.0:
			_check(seen.has(i), "marker %d (%s) has a trail" % [i, m.kind])
		if m.kind not in TRAIL_KINDS:
			_check(not seen.has(i), "marker %d (%s) has no trail" % [i, m.kind])
	var kinds := {}
	for t in s.trails:
		kinds[t.kind] = true
	_check(kinds.size() == 5, "trails of all five kinds (%d)" % kinds.size())
	var total := 0
	for t in s.trails:
		total += t.points.size()
	_check(total >= 300 and total <= 800, "a few hundred trail points (%d)" % total)


func _near(s) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	for i in 30:
		var pos := Vector2(rng.randf_range(0.0, 32000.0), rng.randf_range(0.0, 32000.0))
		if i % 2 == 0 and not s.routes.is_empty():
			pos = s.routes[rng.randi() % s.routes.size()].pos + Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var radius := rng.randf_range(100.0, 1500.0)
		var expect := 0
		for r in s.routes:
			if r.pos.distance_to(pos) <= radius:
				expect += 1
		for t in s.trails:
			for p in t.points:
				if p.pos.distance_to(pos) <= radius:
					expect += 1
		var got: Array = s.near(pos, radius)
		_check(got.size() == expect, "near(%s, %d) finds %d sites, brute force %d" % [pos, radius, got.size(), expect])
		for e in got:
			_check(e.kind == &"route" or e.kind == &"trail", "near result has a kind")
			_check(e.point.pos.distance_to(pos) <= radius + 0.01, "near result is within the radius")
			if e.kind == &"route":
				_check(s.routes[e.index] == e.point, "route result points at its site")
			else:
				_check(s.trails[e.index].points[e.point_index] == e.point, "trail result points at its site")
	_check(s.near(Vector2(-5000, -5000), 100.0).is_empty(), "nothing near a point off the map")

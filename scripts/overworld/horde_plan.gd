class_name HordePlan
extends RefCounted
## The pure plan of the overworld's enemy hordes (spec 1.8 section 4): which horde stands where, of what and how strong.
## Static functions only, no nodes: `build` is a function of the world data, the sites and the `HordeRules`, so it is
## reproducible from `rules.seed` and testable without a scene.
##
## Every horde has an id (`route:<n>`, `trail:<marker>:<n>`, `guard:<marker>`, `den:<marker>`, `arena:<marker>`) and its own
## seed, an explicit integer mix of (rules.seed, hash of the id). Each random decision of a horde (big or small, size,
## composition, order, place) has its own `RandomNumberGenerator` seeded from the horde's seed and a stream number, so tuning
## one rule moves no other. `member_positions` turns a horde into the spots its members stand on, from the same seed.
##
## `sites` is any object with `routes: Array[Dictionary]` (each `{x, y, zone, t}`, tiles) and `trails: Array[Dictionary]`
## (each `{marker, kind, points: [{x, y, t}]}`, tiles, from the road to the end): `HordeSites` in the game, a fake in tests.

const KIND_ROUTE := &"route"
const KIND_ROUTE_BIG := &"route_big"
const KIND_TRAIL := &"trail"
const KIND_GUARD := &"guard"
const KIND_DEN := &"den"
## The marker kinds that hold a den, and those that get a guard.
const DEN_KINDS: Array[String] = ["camp", "cache"]
const GUARD_KINDS: Array[String] = ["cave", "dungeon", "special"]
## The marker kinds that are safe ground (no horde within `OverworldRules.SAFE_RADIUS_TILES`).
const SAFE_KINDS: Array[String] = ["start_camp", "checkpoint", "gate"]
## Streams of a horde's seed: one per random decision.
const S_BIG := 1
const S_SIZE := 2
const S_COMPOSE := 3
const S_ORDER := 4
const S_HOME := 5
const S_SQUAD := 6
const S_MEMBER := 7
## Members stand at least this many tiles from a blocked tile (a disc of this radius is walkable).
const CLEAR_TILES := 2
const _TILE := WorldData.TILE_PX
## Tiles of the disc of radius `CLEAR_TILES` around a tile.
const _CLEAR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
]
## Pass order of the home-gap rule: stronger kinds first.
const _RANK := {"den": 5, "guard": 4, "arena": 4, "route_big": 3, "trail": 2, "route": 1}


## One horde: pure data. `members[i]` is the type id of member i, in order; `member_positions` gives the spot of each of the
## first members (dropped members are the last ones). The squad numbers are copied from the rules so a horde can be
## materialised without them.
class Horde extends RefCounted:
	var id := ""
	## `route`, `route_big`, `trail`, `guard` or `den` (an arena's horde is a `route_big` with id `arena:<marker>`).
	var kind: StringName = &"route"
	## World px, the centre of a walkable tile.
	var home := Vector2.ZERO
	var zone := 0
	## The strength tier: the zone index plus the rules' bonus for the kind.
	var tier := 0
	## The member count asked for (`members.size()`); placing can drop some.
	var size := 0
	## Spread radius in px.
	var radius := 0.0
	var members: Array[StringName] = []
	var hp_mult := 1.0
	var xp_mult := 1.0
	var seed := 0
	## Progress along the zone's road (0 to 1) of the site, or of the road point the trail or marker is nearest.
	var route_t := 0.0
	## The marker index of a den, guard or arena horde, or of a trail's marker; -1 for a route horde.
	var marker := -1
	var squad_size := Vector2i(3, 5)
	var squad_spacing_px := 72.0
	var squad_radius_px := 28.0
	var member_spacing_px := 18.0


## Every horde of the world, in a stable order (route, trail, guard, den, arena). Hordes whose home is on a blocked tile,
## within the safe radius or within `rules.min_home_gap_tiles` of a stronger horde are left out.
static func build(world: WorldData, sites, rules: HordeRules) -> Array[Horde]:
	var safe := _safe_points(world)
	var cands: Array[Horde] = []
	for n in sites.routes.size():
		var s: Dictionary = sites.routes[n]
		var tile := Vector2i(int(s.x), int(s.y))
		var h := _new(rules, "route:%d" % n, KIND_ROUTE, WorldData.world_of(tile), int(s.zone), float(s.t), -1)
		if _big(rules, h):
			h.kind = KIND_ROUTE_BIG
		_fill(rules, h, 1.0)
		cands.append(h)
	var junction_t := {}
	for trail in sites.trails:
		var m := int(trail.marker)
		for n in trail.points.size():
			var p: Dictionary = trail.points[n]
			var tile := Vector2i(int(p.x), int(p.y))
			if not junction_t.has(m):
				junction_t[m] = _route_progress(world, Vector2i(int(trail.points[0].x), int(trail.points[0].y)), world.zone_at(tile))
			var h := _new(rules, "trail:%d:%d" % [m, n], KIND_TRAIL, WorldData.world_of(tile), world.zone_at(tile), junction_t[m], m)
			_fill(rules, h, 1.0 + rules.trail_size_ramp * float(p.t))
			cands.append(h)
	var by_marker := {}
	for trail in sites.trails:
		by_marker[int(trail.marker)] = trail
	for m in world.markers.size():
		var mk: Dictionary = world.markers[m]
		if not (mk.kind in GUARD_KINDS):
			continue
		var tile := Vector2i(int(mk.x), int(mk.y))
		var h := _new(rules, "guard:%d" % m, KIND_GUARD, Vector2.ZERO, int(mk.zone), 0.0, m)
		var home := _guard_home(world, rules, h, tile, by_marker.get(m))
		if home.x < 0.0:
			continue
		h.home = home
		h.route_t = _route_progress(world, tile, h.zone)
		_fill(rules, h, 1.0)
		cands.append(h)
	for m in world.markers.size():
		var mk: Dictionary = world.markers[m]
		if not (mk.kind in DEN_KINDS):
			continue
		var tile := Vector2i(int(mk.x), int(mk.y))
		var home := _open_tile_near(world, tile, 8)
		if home.x < 0.0:
			continue
		var h := _new(rules, "den:%d" % m, KIND_DEN, home, int(mk.zone), _route_progress(world, tile, int(mk.zone)), m)
		_fill(rules, h, 1.0, rules.den_size if mk.kind == "camp" else rules.cache_den_size)
		cands.append(h)
	for m in world.markers.size():
		var mk: Dictionary = world.markers[m]
		if mk.kind != "arena":
			continue
		var tile := Vector2i(int(mk.x), int(mk.y))
		var home := _open_tile_near(world, tile, 8)
		if home.x < 0.0:
			continue
		var h := _new(rules, "arena:%d" % m, KIND_ROUTE_BIG, home, int(mk.zone), _route_progress(world, tile, int(mk.zone)), m)
		_fill(rules, h, 1.0)
		h.radius = float(mk.get("radius", 20.0)) * float(_TILE) * rules.arena_radius_scale
		_spread(rules, h)
		cands.append(h)
	return _separate(world, cands, safe, rules.min_home_gap_tiles)


## The spots of the horde's members in world px, deterministic from `horde.seed`. Position i belongs to `members[i]`; a
## member that cannot be placed is dropped, and the dropped ones are the last, so the result may be shorter than `members`.
## Members stand in squads around squad centres spread by Poisson-disc sampling inside `radius`; every spot is on a
## walkable tile at least `CLEAR_TILES` from a blocked tile, outside the safe radius and `member_spacing_px` from the others.
static func member_positions(world: WorldData, horde) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = horde.members.size()
	if n == 0:
		return out
	var safe := _safe_points(world)
	var mean: float = (horde.squad_size.x + horde.squad_size.y) / 2.0
	var k := maxi(1, roundi(n / mean))
	k = mini(maxi(k, ceili(float(n) / maxf(1.0, horde.squad_size.y))), n)
	var rng_squad := _stream(horde.seed, S_SQUAD)
	var rng_member := _stream(horde.seed, S_MEMBER)
	var centres := PackedVector2Array()
	for i in k:
		var best := Vector2(-1.0, -1.0)
		var best_gap := -1.0
		var chosen := false
		for t in 40:
			var p: Vector2 = horde.home + _in_disc(rng_squad, horde.radius)
			if not _walkable_px(world, p) or _near(safe, p):
				continue
			var gap := INF
			for c in centres:
				gap = minf(gap, c.distance_to(p))
			if gap >= horde.squad_spacing_px:
				best = p
				chosen = true
				break
			if gap > best_gap:
				best_gap = gap
				best = p
		if chosen or best_gap >= 0.0:
			centres.append(best)
		else:
			centres.append(Vector2(-1.0, -1.0))
	for i in k:
		var count: int = n / k + (1 if i < n % k else 0)
		for j in count:
			if centres[i].x >= 0.0:
				for t in 14:
					var p: Vector2 = centres[i] + _in_disc(rng_member, horde.squad_radius_px * (1.0 + float(t) / 7.0))
					if not _spot_ok(world, p) or _near(safe, p):
						continue
					var ok := true
					for q in out:
						if q.distance_to(p) < horde.member_spacing_px:
							ok = false
							break
					if ok:
						out.append(p)
						break
	return out


## True when the world px point is on a walkable tile at least `CLEAR_TILES` from a blocked tile.
static func _spot_ok(world: WorldData, p: Vector2) -> bool:
	var tile := WorldData.tile_of(p)
	for o in _CLEAR_OFFSETS:
		if not world.is_walkable(tile + o):
			return false
	return true


static func _walkable_px(world: WorldData, p: Vector2) -> bool:
	return world.is_walkable(WorldData.tile_of(p))


## A well-mixed non-negative integer of four integers, explicit arithmetic so it is stable across engine versions (the
## style of `NatureLayout.mix`).
static func mix(a: int, b: int, c: int, d: int) -> int:
	var h := a * 2246822519 + b * 374761393 + c * 668265263 + d * 3266489917
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


## FNV-1a over the id's UTF-8 bytes (32 bits).
static func id_hash(id: String) -> int:
	var h := 2166136261
	for b in id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xffffffff
	return h


static func _stream(horde_seed: int, stream: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(horde_seed, stream, 0, 1)
	return rng


## A uniform point of the disc of `radius` around the origin.
static func _in_disc(rng: RandomNumberGenerator, radius: float) -> Vector2:
	var r := radius * sqrt(rng.randf())
	var a := rng.randf() * TAU
	return Vector2(cos(a), sin(a)) * r


static func _int_in(rng: RandomNumberGenerator, range_: Vector2i) -> int:
	return rng.randi_range(range_.x, maxi(range_.x, range_.y))


## A bare horde with its seed, tier and scaling; sizes and members come from `_fill`.
static func _new(rules: HordeRules, id: String, kind: StringName, home: Vector2, zone: int, route_t: float, marker: int) -> Horde:
	var h := Horde.new()
	h.id = id
	h.kind = kind
	h.home = home
	h.zone = zone
	h.route_t = route_t
	h.marker = marker
	h.seed = mix(rules.seed, id_hash(id), 0, 72)
	return h


static func _big(rules: HordeRules, h: Horde) -> bool:
	return _stream(h.seed, S_BIG).randf() < rules.route_big_chance


## Size, composition, tier, scaling and the spread numbers of `h` by its kind. `ramp` scales the drawn size (trails).
static func _fill(rules: HordeRules, h: Horde, ramp: float, size_range := Vector2i(-1, -1)) -> void:
	var range_ := size_range
	match h.kind:
		KIND_ROUTE:
			range_ = rules.route_size
			h.radius = rules.route_radius_px
		KIND_ROUTE_BIG:
			range_ = rules.route_big_size
			h.radius = rules.route_big_radius_px
		KIND_TRAIL:
			range_ = rules.trail_size
			h.radius = rules.trail_radius_px
		KIND_GUARD:
			range_ = rules.guard_size
			h.radius = rules.guard_radius_px
		KIND_DEN:
			h.radius = rules.den_radius_px
	h.size = maxi(1, roundi(float(_int_in(_stream(h.seed, S_SIZE), range_)) * ramp))
	h.members = _compose(rules.weights_for(h.kind, h.zone), h.size, _stream(h.seed, S_COMPOSE), _stream(h.seed, S_ORDER))
	var bonus := int(rules.kind_tier_bonus.get(String(h.kind), 0))
	h.tier = h.zone + bonus
	h.hp_mult = 1.0 + rules.hp_per_tier * float(h.tier) + rules.hp_per_route * h.route_t
	h.xp_mult = 1.0 + rules.xp_per_tier * float(h.tier)
	_spread(rules, h)


## Copies the squad numbers; the squad spacing grows with the square root of the radius over a small road horde's.
static func _spread(rules: HordeRules, h: Horde) -> void:
	h.squad_size = rules.squad_size
	h.squad_spacing_px = rules.squad_spacing_px * sqrt(maxf(1.0, h.radius / maxf(1.0, rules.route_radius_px)))
	h.squad_radius_px = rules.squad_radius_px
	h.member_spacing_px = rules.member_spacing_px


## `size` type ids by the weights: each type gets the floor of its share, the remainder is drawn by weight, and the list is
## shuffled, so a den of 18 with a quarter shooters always holds shooters.
static func _compose(weights: Dictionary, size: int, rng: RandomNumberGenerator, rng_order: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		for i in size:
			out.append(&"grunt")
		return out
	for k in weights:
		for i in floori(float(size) * float(weights[k]) / total):
			out.append(StringName(k))
	while out.size() < size:
		var r := rng.randf() * total
		var pick = null
		for k in weights:
			pick = k
			r -= float(weights[k])
			if r < 0.0:
				break
		out.append(StringName(pick))
	for i in range(out.size() - 1, 0, -1):
		var j := rng_order.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out


## The home of a guard: 8 to 14 tiles from the marker, on the trail side (towards the previous trail point, or the road when
## the marker has no trail), on open ground outside the safe radius. (-1, -1) when none is found.
static func _guard_home(world: WorldData, rules: HordeRules, h: Horde, tile: Vector2i, trail) -> Vector2:
	var rng := _stream(h.seed, S_HOME)
	var toward := Vector2.ZERO
	if trail != null:
		for i in range(trail.points.size() - 1, -1, -1):
			var p: Dictionary = trail.points[i]
			var d := Vector2(float(p.x) - tile.x, float(p.y) - tile.y)
			if d.length() > float(rules.guard_distance_tiles.y):
				toward = d
				break
	if toward == Vector2.ZERO:
		toward = Vector2(_nearest_route_tile(world, tile) - tile)
	var base := toward.angle()
	var safe := _safe_points(world)
	for t in 32:
		var a := base + rng.randf_range(-1.3, 1.3) if t < 20 else rng.randf() * TAU
		var dist := rng.randf_range(float(rules.guard_distance_tiles.x), float(rules.guard_distance_tiles.y))
		var cand := tile + Vector2i((Vector2(cos(a), sin(a)) * dist).round())
		var at := WorldData.world_of(cand)
		if _spot_ok(world, at) and not _near(safe, at):
			return at
	return Vector2(-1.0, -1.0)


## The centre of the open tile nearest `tile` within `reach` tiles (the tile itself first), or (-1, -1).
static func _open_tile_near(world: WorldData, tile: Vector2i, reach: int) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_d := INF
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var d := float(dx * dx + dy * dy)
			if d < best_d and d <= float(reach * reach):
				var at := WorldData.world_of(tile + Vector2i(dx, dy))
				if _spot_ok(world, at):
					best_d = d
					best = at
	return best


static func _nearest_route_index(world: WorldData, tile: Vector2i) -> int:
	var best := 0
	var best_d := INF
	for i in world.main_path.size():
		var d := float((world.main_path[i] - tile).length_squared())
		if d < best_d:
			best_d = d
			best = i
	return best


static func _nearest_route_tile(world: WorldData, tile: Vector2i) -> Vector2i:
	return world.main_path[_nearest_route_index(world, tile)] if not world.main_path.is_empty() else tile


## 0 to 1 along the zone's stretch of the road of the road point nearest `tile` (the route's points are 8 tiles apart).
static func _route_progress(world: WorldData, tile: Vector2i, zone: int) -> float:
	if world.main_path.is_empty() or zone >= world.zones.size():
		return 0.0
	var z: Dictionary = world.zones[zone]
	var span := float(z.route_end_tile - z.route_start_tile)
	if span <= 0.0:
		return 0.0
	return clampf((float(_nearest_route_index(world, tile)) * 8.0 - float(z.route_start_tile)) / span, 0.0, 1.0)


## The safe markers' positions in world px.
static func _safe_points(world: WorldData) -> PackedVector2Array:
	var out := PackedVector2Array()
	for m in world.markers:
		if m.kind in SAFE_KINDS:
			out.append(WorldData.marker_world(m))
	return out


## True when `p` is within the safe radius of any safe point.
static func _near(safe: PackedVector2Array, p: Vector2) -> bool:
	var r := float(OverworldRules.SAFE_RADIUS_TILES * _TILE)
	for s in safe:
		if s.distance_squared_to(p) < r * r:
			return true
	return false


static func _rank(h: Horde) -> int:
	return int(_RANK["arena" if h.id.begins_with("arena:") else String(h.kind)])


## Drops the candidates whose home is blocked or in the safe radius, then keeps the stronger of two homes closer than the gap
## (the order is by kind rank, then by id, so it does not depend on sizes). The rest keep their input order.
static func _separate(world: WorldData, cands: Array[Horde], safe: PackedVector2Array, gap_tiles: int) -> Array[Horde]:
	var order: Array[Horde] = []
	for h in cands:
		if _walkable_px(world, h.home) and not _near(safe, h.home):
			order.append(h)
	order.sort_custom(func(a: Horde, b: Horde) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		if ra != rb:
			return ra > rb
		return a.id < b.id)
	var cell := float(maxi(1, gap_tiles) * _TILE)
	var grid := {}
	var keep := {}
	for h in order:
		var c := Vector2i(floori(h.home.x / cell), floori(h.home.y / cell))
		var clear := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for o in grid.get(c + Vector2i(dx, dy), []):
					if o.home.distance_to(h.home) < cell:
						clear = false
		if clear:
			if not grid.has(c):
				grid[c] = []
			grid[c].append(h)
			keep[h.id] = true
	var out: Array[Horde] = []
	for h in cands:
		if keep.has(h.id):
			out.append(h)
	return out

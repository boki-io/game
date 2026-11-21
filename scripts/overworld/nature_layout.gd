class_name NatureLayout
extends RefCounted
## The pure layout of the overworld's nature props (spec 1.7 section 3): which tree, rock or shrub stands where. Static
## functions only, no nodes: `props_for_chunk` is a function of the world data, the `NatureRules` and the sprite catalog, so
## it is reproducible from `rules.seed` and testable without a scene.
##
## The world is cut into cells the size of a chunk. A cell builds (1) its woods, (2) its loner trees, then (3) its rock piles,
## loner rocks and shrub patches; each cell and each rule has its own `RandomNumberGenerator`, seeded with an explicit integer
## mix of (seed, cell, rule), so a rule never moves another rule's props. The layers depend one way: loner trees keep clear of
## the woods around them, and shrubs and rocks keep clear of the tree trunks around them; woods depend on nothing but the map.
## Every layer of every cell is kept in the caller's `cache` (a plain Dictionary), because a chunk reads 3 x 3 cells whose
## finals read the loners of 3 x 3 cells, which read the woods of 3 x 3 cells.
##
## `sprites` is any object with `count(kind) -> int`, `indices_with_tag(kind, tag) -> Array` and
## `size_px(kind, i) -> Vector2` (the drawn size after pre-scaling), `kind` being one of the `KIND_*` names below.
## Tags used: trees `green` `fir` `autumn` `tall` `short`; rocks `pebbles` `small` `big` `pile_pebbles`; shrubs `green`
## `yellowish` `yellow`.

const KIND_TREE := &"tree"
const KIND_ROCK := &"rock"
const KIND_SHRUB := &"shrub"
## Which rule placed a prop (`Placement.rule`).
const RULE_WOOD := 1
const RULE_LONER_TREE := 2
const RULE_PILE := 3
const RULE_LONER_ROCK := 4
const RULE_PATCH := 5
const RULE_PATH_PATCH := 6
## Layers of the cache: the key is Vector3i(cell.x, cell.y, layer).
const _L_OPEN := 0
const _L_WOOD := 1
const _L_LONER := 2
const _L_FINAL := 3
const _SIZE := WorldData.SIZE
const _TILE := WorldData.TILE_PX
const _LONER_TRIES := 8
const _MARKER_BIG: Array[String] = ["start_camp", "checkpoint", "gate", "camp"]


## One prop: its kind, the sprite index into that kind's list, the base (the foot) in world px, whether it is mirrored in x,
## the collider radius (0 when it can be walked through) and the rule that placed it.
class Placement extends RefCounted:
	var kind: StringName
	var sprite := 0
	var base := Vector2.ZERO
	var flip := false
	var solid_radius := 0.0
	var rule := 0


## What a build reads, bundled so the static helpers take one argument: the masks (shared arrays, not copies), the rules, the
## sprites, the marker clearings near the cell being built (x, y, radius squared) and the sprite pools by tag set.
class Ctx extends RefCounted:
	var rules: NatureRules
	var sprites
	var collision: PackedByteArray
	var zone_values: PackedByteArray
	var path_mask: PackedByteArray
	var zone := 0
	var clearings := PackedFloat32Array()
	var near := PackedFloat32Array()
	var pools := {}

	func _init(world: WorldData, nature_rules: NatureRules, sprite_catalog) -> void:
		rules = nature_rules
		sprites = sprite_catalog
		collision = world.collision
		zone_values = world.zone_values
		path_mask = world.path_mask
		zone = rules.zone
		for m in world.markers:
			var tiles := rules.marker_clear_tiles if m.kind in NatureLayout._MARKER_BIG else rules.marker_clear_minor_tiles
			var at := WorldData.marker_world(m)
			clearings.append(at.x)
			clearings.append(at.y)
			clearings.append(float(tiles * WorldData.TILE_PX) * float(tiles * WorldData.TILE_PX))

	## Keeps the clearings that can touch the cell (its rectangle widened by the widest clearing and the widest clump).
	func set_near(cell: Vector2i) -> void:
		near.clear()
		var side := float(rules.cell_tiles * WorldData.TILE_PX)
		var lo := Vector2(cell) * side
		var hi := lo + Vector2(side, side)
		var k := 0
		while k < clearings.size():
			var reach := sqrt(clearings[k + 2]) + 14.0 * WorldData.TILE_PX
			if clearings[k] > lo.x - reach and clearings[k] < hi.x + reach and clearings[k + 1] > lo.y - reach and clearings[k + 1] < hi.y + reach:
				near.append(clearings[k])
				near.append(clearings[k + 1])
				near.append(clearings[k + 2])
			k += 3

	## The sorted indices of the sprites of `kind` that have any of `tags` (cached).
	func pool(kind: StringName, tags: Array) -> Array:
		var key := String(kind) + str(tags)
		if pools.has(key):
			return pools[key]
		var seen := {}
		var out := []
		for t in tags:
			for i in sprites.indices_with_tag(kind, t):
				if not seen.has(i):
					seen[i] = true
					out.append(i)
		out.sort()
		pools[key] = out
		return out


## Every placement whose base is inside `chunk` (32 x 32 tiles), in a stable order, at most `rules.max_props_per_chunk`.
## `cache` is optional: pass the same Dictionary on later calls to reuse the cells (see `evict`); the result does not depend on it.
static func props_for_chunk(world: WorldData, rules: NatureRules, sprites, chunk: Vector2i, cache: Dictionary = {}) -> Array[Placement]:
	var c := Ctx.new(world, rules, sprites)
	var chunk_px := float(rules.cell_tiles * _TILE)
	var out: Array[Placement] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for p in _final(c, cache, chunk + Vector2i(dx, dy)):
				if Vector2i(floori(p.base.x / chunk_px), floori(p.base.y / chunk_px)) == chunk:
					out.append(p)
	if out.size() > rules.max_props_per_chunk:
		out.resize(rules.max_props_per_chunk)
	return out


## Drops the cached cells farther than `radius` chunks (Chebyshev) from `centre`.
static func evict(cache: Dictionary, centre: Vector2i, radius: int) -> void:
	for key in cache.keys():
		if maxi(absi(key.x - centre.x), absi(key.y - centre.y)) > radius:
			cache.erase(key)


## The open-ground factor of a cell: its walkable tiles of the rules' zone divided by `cell_tiles` squared.
static func open_factor(world: WorldData, rules: NatureRules, cell: Vector2i, cache: Dictionary = {}) -> float:
	return _open(Ctx.new(world, rules, null), cache, cell)


## A well-mixed non-negative integer of (seed, cell, rule), in the style of `WorldTerrain.tile_hash`. Explicit arithmetic, so
## it is stable across engine versions.
static func mix(seed_value: int, x: int, y: int, rule: int) -> int:
	var h := seed_value * 2246822519 + x * 374761393 + y * 668265263 + rule * 3266489917
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _rng(c: Ctx, cell: Vector2i, rule: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(c.rules.seed, cell.x, cell.y, rule)
	return rng


static func _open(c: Ctx, cache: Dictionary, cell: Vector2i) -> float:
	var key := Vector3i(cell.x, cell.y, _L_OPEN)
	if cache.has(key):
		return cache[key]
	var ct := c.rules.cell_tiles
	var count := 0
	var x0 := maxi(cell.x * ct, 0)
	var x1 := mini((cell.x + 1) * ct, _SIZE)
	for ty in range(maxi(cell.y * ct, 0), mini((cell.y + 1) * ct, _SIZE)):
		var row := ty * _SIZE
		for tx in range(x0, x1):
			if c.collision[row + tx] > 127 and c.zone_values[row + tx] / 30 == c.zone:
				count += 1
	var open := float(count) / float(ct * ct)
	cache[key] = open
	return open


## A walkable tile of the zone, off the dirt path; `wall` tiles clear of blocked ones and `path_clear` clear of path ones.
static func _tile_ok(c: Ctx, tx: int, ty: int, wall: int, path_clear: int) -> bool:
	if tx < 0 or ty < 0 or tx >= _SIZE or ty >= _SIZE:
		return false
	var i := ty * _SIZE + tx
	if c.collision[i] <= 127 or c.zone_values[i] / 30 != c.zone or c.path_mask[i] > 127:
		return false
	if wall > 0:
		if tx < wall or ty < wall or tx >= _SIZE - wall or ty >= _SIZE - wall:
			return false
		for dy in range(-wall, wall + 1):
			var row := i + dy * _SIZE
			for dx in range(-wall, wall + 1):
				if c.collision[row + dx] <= 127:
					return false
	if path_clear > 0 and _path_near(c, tx, ty, path_clear):
		return false
	return true


static func _path_near(c: Ctx, tx: int, ty: int, reach: int) -> bool:
	for y in range(maxi(ty - reach, 0), mini(ty + reach + 1, _SIZE)):
		var row := y * _SIZE
		for x in range(maxi(tx - reach, 0), mini(tx + reach + 1, _SIZE)):
			if c.path_mask[row + x] > 127:
				return true
	return false


## Whether a position passes the terrain rules and stands outside every marker's clearing.
static func _ok(c: Ctx, pos: Vector2, wall: int, path_clear: int) -> bool:
	if not _tile_ok(c, floori(pos.x / _TILE), floori(pos.y / _TILE), wall, path_clear):
		return false
	var k := 0
	while k < c.near.size():
		var dx := pos.x - c.near[k]
		var dy := pos.y - c.near[k + 1]
		if dx * dx + dy * dy < c.near[k + 2]:
			return false
		k += 3
	return true


## The terrain rule for a shrub, a small rock or a pebble.
static func _small_ok(c: Ctx, pos: Vector2) -> bool:
	return _ok(c, pos, c.rules.wall_clear_small_tiles, 0)


## The terrain rule for a tree or a big rock.
static func _large_ok(c: Ctx, pos: Vector2) -> bool:
	return _ok(c, pos, c.rules.wall_clear_tiles, c.rules.path_clear_tiles)


static func _random_tile(c: Ctx, rng: RandomNumberGenerator, cell: Vector2i, margin: int = 0) -> Vector2:
	var ct := c.rules.cell_tiles
	var tx := cell.x * ct + rng.randi_range(margin, ct - 1 - margin)
	var ty := cell.y * ct + rng.randi_range(margin, ct - 1 - margin)
	return Vector2(tx * _TILE + rng.randf() * _TILE, ty * _TILE + rng.randf() * _TILE)


## A uniform draw in the range scaled by the open factor, rounded up or down by chance (1.4 is 1 or 2).
static func _count(rng: RandomNumberGenerator, range_: Vector2i, open: float) -> int:
	var v := rng.randf_range(float(range_.x), float(range_.y)) * open
	var n := floori(v)
	if rng.randf() < v - n:
		n += 1
	return n


static func _int_in(rng: RandomNumberGenerator, range_: Vector2i) -> int:
	return rng.randi_range(range_.x, maxi(range_.x, range_.y))


## A key of `entries` (a Dictionary of key to weight) drawn by weight.
static func _weighted_key(rng: RandomNumberGenerator, entries: Dictionary):
	var total := 0.0
	for k in entries:
		total += float(entries[k])
	var r := rng.randf() * total
	var last = null
	for k in entries:
		last = k
		r -= float(entries[k])
		if r < 0.0:
			return k
	return last


## A group (`{"weight", "tags"}`) of `groups` drawn by weight, or an empty Dictionary.
static func _weighted_group(rng: RandomNumberGenerator, groups: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for g in groups:
		total += float(g.get("weight", 1.0))
	var r := rng.randf() * total
	var last := {}
	for g in groups:
		last = g
		r -= float(g.get("weight", 1.0))
		if r < 0.0:
			return g
	return last


static func _inter(a: Array, b: Array) -> Array:
	var out := []
	for v in a:
		if b.has(v):
			out.append(v)
	return out


## One entry of `pool` by the stream, or -1 when it is empty.
static func _pick(rng: RandomNumberGenerator, pool: Array) -> int:
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else -1


static func _make(kind: StringName, sprite: int, base: Vector2, flip: bool, rule: int, solid: float = 0.0) -> Placement:
	var p := Placement.new()
	p.kind = kind
	p.sprite = sprite
	p.base = base
	p.flip = flip
	p.rule = rule
	p.solid_radius = solid
	return p


static func _tree(c: Ctx, rng: RandomNumberGenerator, group: Dictionary, prefer: Array, base: Vector2, rule: int) -> Placement:
	var tags: Array = group.get("tags", [])
	var pool := c.pool(KIND_TREE, tags)
	var autumn := rng.randf() < c.rules.autumn_weight and tags.has("green")
	if autumn:
		var a := c.pool(KIND_TREE, ["autumn"])
		if not a.is_empty():
			pool = a
	if not prefer.is_empty():
		var chosen := _inter(pool, prefer)
		if not chosen.is_empty():
			pool = chosen
	var sprite := _pick(rng, pool)
	var flip := rng.randf() < 0.5
	if sprite < 0:
		return null
	return _make(KIND_TREE, sprite, base, flip, rule, c.rules.trunk_radius_px)


static func _shrub(c: Ctx, rng: RandomNumberGenerator, colour: String, base: Vector2, rule: int) -> Placement:
	var sprite := _pick(rng, c.pool(KIND_SHRUB, [colour]))
	var flip := rng.randf() < 0.5
	if sprite < 0:
		return null
	return _make(KIND_SHRUB, sprite, base, flip, rule)


static func _small_rock(c: Ctx, rng: RandomNumberGenerator, pool: Array, base: Vector2, rule: int) -> Placement:
	var sprite := _pick(rng, pool)
	var flip := rng.randf() < 0.5
	if sprite < 0:
		return null
	return _make(KIND_ROCK, sprite, base, flip, rule)


## A point of the disc around `centre`, uniform in area.
static func _in_disc(rng: RandomNumberGenerator, centre: Vector2, radius: float, min_radius: float = 0.0) -> Vector2:
	var r := lerpf(min_radius, radius, sqrt(rng.randf()))
	var a := rng.randf() * TAU
	return centre + Vector2(cos(a), sin(a)) * r


## The woods of a cell (layer 1): the trees of its wood, then its rim shrubs and its small rocks. Depends on the map only.
static func _wood(c: Ctx, cache: Dictionary, cell: Vector2i) -> Array:
	var key := Vector3i(cell.x, cell.y, _L_WOOD)
	if cache.has(key):
		return cache[key]
	var out := []
	var open := _open(c, cache, cell)
	if open > 0.0:
		var rng := _rng(c, cell, RULE_WOOD)
		if rng.randf() < c.rules.wood_chance * open:
			c.set_near(cell)
			_build_wood(c, rng, cell, out)
	cache[key] = out
	return out


static func _build_wood(c: Ctx, rng: RandomNumberGenerator, cell: Vector2i, out: Array) -> void:
	var r := c.rules
	var centre := Vector2.ZERO
	var found := false
	for t in r.centre_tries:
		var p := _random_tile(c, rng, cell)
		if not found and _large_ok(c, p):
			centre = p
			found = true
	if not found:
		return
	var n := _int_in(rng, r.wood_trees)
	var radius := float(_int_in(rng, r.wood_radius_tiles)) * _TILE
	var group := _weighted_group(rng, r.wood_groups)
	var points: Array[Vector2] = []
	var throws := n * r.wood_throws_per_tree
	while points.size() < n and throws > 0:
		throws -= 1
		var u := rng.randf()
		var a := rng.randf() * TAU
		var p := centre + Vector2(cos(a), sin(a)) * radius * pow(u, 0.5 * r.centre_bias)
		if not _large_ok(c, p):
			continue
		var apart := true
		for q in points:
			if q.distance_squared_to(p) < r.tree_spacing_px * r.tree_spacing_px:
				apart = false
				break
		if apart:
			points.append(p)
	if points.size() < r.wood_trees.x:
		return
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := a.distance_squared_to(centre)
		var db := b.distance_squared_to(centre)
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var tall := c.pool(KIND_TREE, ["tall"])
	var short := c.pool(KIND_TREE, ["short"])
	var inner := ceili(points.size() / 3.0)
	for i in points.size():
		var tree := _tree(c, rng, group, tall if i < inner else short, points[i], RULE_WOOD)
		if tree != null:
			out.append(tree)
	for i in _int_in(rng, r.wood_shrubs):
		var a := rng.randf() * TAU
		var p := centre + Vector2(cos(a), sin(a)) * (radius + rng.randf() * 12.0)
		var colour := String(_weighted_key(rng, r.shrub_colours))
		if _small_ok(c, p):
			var s := _shrub(c, rng, colour, p, RULE_WOOD)
			if s != null:
				out.append(s)
	var rocks := c.pool(KIND_ROCK, ["small", "pebbles"])
	for i in _int_in(rng, r.wood_rocks):
		var p := _in_disc(rng, centre, radius)
		if _small_ok(c, p):
			var s := _small_rock(c, rng, rocks, p, RULE_WOOD)
			if s != null:
				out.append(s)


## The tree bases of the woods and the loners of the 3 x 3 cells around `cell`.
static func _tree_bases(c: Ctx, cache: Dictionary, cell: Vector2i, with_loners: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var at := cell + Vector2i(dx, dy)
			for p in _wood(c, cache, at):
				if p.kind == KIND_TREE:
					out.append(p.base)
			if with_loners:
				for p in _loners(c, cache, at):
					out.append(p.base)
	return out


## The loner trees of a cell (layer 2): kept clear of every wood tree around and of each other.
static func _loners(c: Ctx, cache: Dictionary, cell: Vector2i) -> Array:
	var key := Vector3i(cell.x, cell.y, _L_LONER)
	if cache.has(key):
		return cache[key]
	var out := []
	var open := _open(c, cache, cell)
	if open > 0.0:
		var r := c.rules
		var taken := _tree_bases(c, cache, cell, false)
		c.set_near(cell)
		var rng := _rng(c, cell, RULE_LONER_TREE)
		var clear_px := float(r.loner_clear_tiles * _TILE)
		var margin := ceili(r.loner_clear_tiles / 2.0)
		for k in _count(rng, r.loner_trees, open):
			for t in _LONER_TRIES:
				var p := _random_tile(c, rng, cell, margin)
				if not _large_ok(c, p) or not _far_from(taken, p, clear_px):
					continue
				var tree := _tree(c, rng, _weighted_group(rng, r.loner_groups), [], p, RULE_LONER_TREE)
				if tree != null:
					out.append(tree)
					taken.append(p)
				break
	cache[key] = out
	return out


static func _far_from(points: PackedVector2Array, p: Vector2, distance: float) -> bool:
	var limit := distance * distance
	for q in points:
		if q.distance_squared_to(p) < limit:
			return false
	return true


## Everything a cell places (layer 3): the woods, the loners, then the rock piles, loner rocks and shrub patches, with every
## rock and shrub kept off the trunks around it.
static func _final(c: Ctx, cache: Dictionary, cell: Vector2i) -> Array:
	var key := Vector3i(cell.x, cell.y, _L_FINAL)
	if cache.has(key):
		return cache[key]
	var out := []
	var open := _open(c, cache, cell)
	if open > 0.0:
		var trees := _tree_bases(c, cache, cell, true)
		var wood := _wood(c, cache, cell)
		var loners := _loners(c, cache, cell)
		c.set_near(cell)
		var gap := c.rules.trunk_clear_px
		for p in wood:
			if p.kind == KIND_TREE or _far_from(trees, p.base, gap):
				out.append(p)
		out.append_array(loners)
		_piles(c, cell, open, trees, out)
		_loner_rocks(c, cell, open, trees, out)
		_patches(c, cell, open, trees, out)
		_path_patches(c, cell, open, trees, out)
	cache[key] = out
	return out


static func _piles(c: Ctx, cell: Vector2i, open: float, trees: PackedVector2Array, out: Array) -> void:
	var r := c.rules
	var rng := _rng(c, cell, RULE_PILE)
	if rng.randf() >= r.rock_pile_chance * open:
		return
	var centre := Vector2.ZERO
	var found := false
	for t in r.centre_tries:
		var p := _random_tile(c, rng, cell)
		if not found and _ok(c, p, r.pile_edge_tiles, r.path_clear_tiles):
			centre = p
			found = true
	if not found:
		return
	var bigs := c.pool(KIND_ROCK, ["big"])
	var radius := float(r.pile_radius_tiles * _TILE)
	var companions := c.pool(KIND_ROCK, ["small", "pile_pebbles"])
	var first := _pick(rng, bigs)
	var flip := rng.randf() < 0.5
	var big_radius := 0.0
	if first >= 0:
		var on_trunk := not _far_from(trees, centre, r.trunk_clear_px)
		big_radius = c.sprites.size_px(KIND_ROCK, first).x * 0.5
		if not on_trunk:
			out.append(_make(KIND_ROCK, first, centre, flip, RULE_PILE, r.big_rock_radius_factor * big_radius))
	for i in _int_in(rng, r.pile_rocks):
		var p := _in_disc(rng, centre, radius, big_radius + 3.0)
		var s := _small_rock(c, rng, companions, p, RULE_PILE)
		if s != null and _small_ok(c, p) and _far_from(trees, p, r.trunk_clear_px):
			out.append(s)


static func _loner_rocks(c: Ctx, cell: Vector2i, open: float, trees: PackedVector2Array, out: Array) -> void:
	var r := c.rules
	var rng := _rng(c, cell, RULE_LONER_ROCK)
	var rocks := c.pool(KIND_ROCK, ["small", "pebbles"])
	for k in _count(rng, r.loner_rocks, open):
		var p := _random_tile(c, rng, cell)
		var s := _small_rock(c, rng, rocks, p, RULE_LONER_ROCK)
		if s != null and _small_ok(c, p) and _far_from(trees, p, r.trunk_clear_px):
			out.append(s)


static func _patches(c: Ctx, cell: Vector2i, open: float, trees: PackedVector2Array, out: Array) -> void:
	var r := c.rules
	var rng := _rng(c, cell, RULE_PATCH)
	for k in _count(rng, r.shrub_patches, open):
		var centre := Vector2.ZERO
		var found := false
		for t in r.centre_tries:
			var p := _random_tile(c, rng, cell)
			if not found and _small_ok(c, p):
				centre = p
				found = true
		if found:
			_patch(c, rng, centre, RULE_PATCH, trees, out)


static func _path_patches(c: Ctx, cell: Vector2i, open: float, trees: PackedVector2Array, out: Array) -> void:
	var r := c.rules
	var rng := _rng(c, cell, RULE_PATH_PATCH)
	if rng.randf() >= r.path_shrub_chance * open:
		return
	for t in 24:
		var p := _random_tile(c, rng, cell)
		if _small_ok(c, p) and _path_near(c, floori(p.x / _TILE), floori(p.y / _TILE), r.path_shrub_reach_tiles):
			_patch(c, rng, p, RULE_PATH_PATCH, trees, out)
			return


static func _patch(c: Ctx, rng: RandomNumberGenerator, centre: Vector2, rule: int, trees: PackedVector2Array, out: Array) -> void:
	var r := c.rules
	var colour := String(_weighted_key(rng, r.shrub_colours))
	var radius := float(r.patch_radius_tiles * _TILE)
	for i in _int_in(rng, r.patch_shrubs):
		var p := _in_disc(rng, centre, radius)
		var s := _shrub(c, rng, colour, p, rule)
		if s != null and _small_ok(c, p) and _far_from(trees, p, r.trunk_clear_px):
			out.append(s)

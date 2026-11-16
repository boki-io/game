class_name MapLayout
extends RefCounted
## Where a map's walls, pillars, decor and torches go (spec 0.6 section 6). Pure logic: no scene, no autoload, one
## RandomNumberGenerator seeded with the map seed, so a seed reproduces the map. A theme with `legacy_layout`
## (the default theme) calls the existing layout code and fixed seeds instead, which reproduces today's arena.

const WallScript := preload("res://scripts/cave/cave_wall.gd")
const DecorScript := preload("res://scripts/cave/cave_decor.gd")

const BAND := 16.0  # the rock band's thickness (main.gd WALL_BAND)
const START_CLEARING := 110.0  # half-size of the free square around the arena centre
const WALL_CLEARING := 24.0  # walls stay this far outside the start square
const MARGIN := 56.0  # wall to rock band, and wall to wall in SCATTER (CaveWall.MARGIN)
const GAP_MIN := 40.0  # the least gap between two obstacles in any style
const LANE_GAP := 64.0  # the least gap between two segments of one lane
const MAX_OBSTACLES := 16
const WALL_TRIES := 1500
const PILLAR_TRIES := 1500
const PILLAR_RADIUS := 6.0
## A pillar's collider centre is this far from its base position (prop.gd).
const PILLAR_OFFSET := Vector2(0.0, -6.0)
const PILLAR_CENTRE_MIN := 60.0  # pillar to arena centre
const PILLAR_EDGE := 24.0  # pillar to rock band (on top of BAND)
const CLUSTER_APART := 280.0
const CLUSTER_GAP_MIN := 40.0
const CLUSTER_GAP_MAX := 56.0
const CLUSTER_PILLAR_REACH := 90.0
const LANE_JITTER := 24.0
const DECOR_EDGE := 10.0  # decor to rock band (at least 8)
const DECOR_CLEARANCE := 24.0  # decor to the start square
const DECOR_WALL_CLEARANCE := 8.0
const DECOR_TRIES := 4000
const TORCH_CORNER := 40.0
const LEGACY_PILLAR_SEED := 1  # main.gd _spawn_props
const LEGACY_PILLAR_MARGIN := 48.0


## The layout of `theme` for `map_seed` in a room of `size`.
static func generate(theme: MapTheme, map_seed: int, size: Vector2) -> MapLayoutData:
	var data := MapLayoutData.new()
	var start := start_rect(size)
	if theme.legacy_layout:
		_legacy(theme, size, start, data)
		return data
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var lengths: Array[float] = theme.wall_lengths
	if lengths.is_empty():
		lengths = []
		for length: float in WallScript.LENGTHS:
			lengths.append(length)
	var anchors: Array[Vector2] = []
	match theme.style:
		MapTheme.Style.LANES:
			_lane_walls(theme, rng, size, start, lengths, data.walls)
		MapTheme.Style.CLUSTERS:
			_cluster_walls(theme, rng, size, start, lengths, data.walls, anchors)
		_:
			_scatter_walls(theme, rng, size, start, lengths, data.walls, theme.wall_count, -1)
	_place_pillars(theme, rng, size, start, data, anchors)
	_place_torches(theme, rng, size, data.torches)
	_place_decor(theme, rng, size, start, data)
	return data


## The free square around the arena centre.
static func start_rect(size: Vector2) -> Rect2:
	var centre := size / 2.0
	return Rect2(centre - Vector2(START_CLEARING, START_CLEARING), Vector2(START_CLEARING, START_CLEARING) * 2.0)


## Today's arena: CaveWall.layout, main.gd's pillar loop, CaveDecor.layout and main.gd's hand-placed torches.
static func _legacy(theme: MapTheme, size: Vector2, start: Rect2, data: MapLayoutData) -> void:
	data.walls = WallScript.layout(size, BAND, [start])
	var rng := RandomNumberGenerator.new()
	rng.seed = LEGACY_PILLAR_SEED
	var centre := size / 2.0
	for i in theme.pillar_count:
		var pos := Vector2(
			rng.randf_range(LEGACY_PILLAR_MARGIN, size.x - LEGACY_PILLAR_MARGIN),
			rng.randf_range(LEGACY_PILLAR_MARGIN, size.y - LEGACY_PILLAR_MARGIN))
		if pos.distance_to(centre) < 60.0:
			continue
		var blocked := false
		for rect in data.walls:
			if rect.grow(16.0).has_point(pos):
				blocked = true
		if blocked:
			continue
		data.pillars.append(pos)
	var reserved: Array[Rect2] = [start]
	reserved.append_array(data.walls)
	data.decor = DecorScript.layout(size, BAND, reserved, theme.decor_count)
	for x in [200.0, 600.0, 1000.0, 1400.0]:
		data.torches.append(Vector2(x, 9.0))
		data.torches.append(Vector2(x + 100.0, size.y - BAND + 1.0))
	for y in [220.0, 670.0]:
		data.torches.append(Vector2(BAND - 3.0, y))
		data.torches.append(Vector2(size.x - BAND + 3.0, y))


# --- Walls ---------------------------------------------------------------------------------------------------------

## Whether a wall rectangle is legal: inside the rock band margin, off the start square, `gap` from every other wall.
static func wall_ok(rect: Rect2, walls: Array[Rect2], start: Rect2, size: Vector2, gap: float) -> bool:
	var edge := BAND + MARGIN
	if not Rect2(edge, edge, size.x - 2.0 * edge, size.y - 2.0 * edge).encloses(rect):
		return false
	if rect.intersects(start.grow(WALL_CLEARING)):
		return false
	for other in walls:
		if rect.intersects(other.grow(gap)):
			return false
	return true


static func _pick_length(rng: RandomNumberGenerator, lengths: Array[float]) -> float:
	return lengths[rng.randi_range(0, lengths.size() - 1)]


## SCATTER (and the cross pieces of LANES): random length, orientation and position, rejected on the rules.
## `force_horizontal` is 1 (left-right), 0 (up-down) or -1 (by horizontal_bias).
static func _scatter_walls(theme: MapTheme, rng: RandomNumberGenerator, size: Vector2, start: Rect2,
		lengths: Array[float], walls: Array[Rect2], count: int, force_horizontal: int) -> void:
	var edge := BAND + MARGIN
	var target := walls.size() + count
	var tries := 0
	while walls.size() < target and tries < WALL_TRIES:
		tries += 1
		var length := _pick_length(rng, lengths)
		var horizontal := rng.randf() < theme.horizontal_bias if force_horizontal < 0 else force_horizontal == 1
		var dims := Vector2(length, WallScript.THICKNESS) if horizontal else Vector2(WallScript.THICKNESS, length)
		var lo := Vector2(edge, edge)
		var hi := size - Vector2(edge, edge) - dims
		if hi.x < lo.x or hi.y < lo.y:
			continue
		var pos := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y)).round()
		var rect := Rect2(pos, dims)
		if wall_ok(rect, walls, start, size, MARGIN):
			walls.append(rect)


## LANES: lines across the arena with broken rows of walls on them (gaps of at least LANE_GAP), and the other
## orientation's share as scattered cross pieces.
static func _lane_walls(theme: MapTheme, rng: RandomNumberGenerator, size: Vector2, start: Rect2,
		lengths: Array[float], walls: Array[Rect2]) -> void:
	var edge := BAND + MARGIN
	var horizontal := theme.horizontal_bias >= 0.5
	var share := theme.horizontal_bias if horizontal else 1.0 - theme.horizontal_bias
	var on_lanes := clampi(roundi(theme.wall_count * share), 0, theme.wall_count)
	var lane_count := 3 if theme.wall_count <= 6 else 4
	# A lane is the coordinate across the walls' direction: y for left-right walls, x for up-down ones.
	var across_size := size.y if horizontal else size.x
	var along_size := size.x if horizontal else size.y
	var lo := edge
	var hi := across_size - edge - WallScript.THICKNESS
	var lanes: Array[float] = []
	for i in lane_count:
		var line := lo + (hi - lo) * float(i + 1) / float(lane_count + 1)
		lanes.append(clampf(line + rng.randf_range(-LANE_JITTER, LANE_JITTER), lo, hi))
	for k in on_lanes:
		var lane := lanes[k % lane_count]
		for attempt in 300:
			var length := _pick_length(rng, lengths)
			var hi_along := along_size - edge - length
			if hi_along < edge:
				continue
			var along := rng.randf_range(edge, hi_along)
			var pos := Vector2(along, lane) if horizontal else Vector2(lane, along)
			var dims := Vector2(length, WallScript.THICKNESS) if horizontal else Vector2(WallScript.THICKNESS, length)
			var rect := Rect2(pos.round(), dims)
			if wall_ok(rect, walls, start, size, LANE_GAP):
				walls.append(rect)
				break
	_scatter_walls(theme, rng, size, start, lengths, walls, theme.wall_count - on_lanes, 0 if horizontal else 1)


## CLUSTERS: anchors at least CLUSTER_APART apart, two walls at each (parallel or an L), 40 to 56 px between them.
static func _cluster_walls(theme: MapTheme, rng: RandomNumberGenerator, size: Vector2, start: Rect2,
		lengths: Array[float], walls: Array[Rect2], anchors: Array[Vector2]) -> void:
	var edge := BAND + MARGIN
	var tries := 0
	while walls.size() < theme.wall_count and tries < WALL_TRIES:
		tries += 1
		var anchor := Vector2(rng.randf_range(edge + 40.0, size.x - edge - 40.0),
			rng.randf_range(edge + 40.0, size.y - edge - 40.0)).round()
		var near := false
		for other in anchors:
			if other.distance_to(anchor) < CLUSTER_APART:
				near = true
		if near:
			continue
		var pair := _cluster_pair(theme, rng, anchor, lengths, mini(2, theme.wall_count - walls.size()))
		var ok := true
		for rect in pair:
			if not wall_ok(rect, walls, start, size, MARGIN):
				ok = false
		if ok:
			walls.append_array(pair)
			anchors.append(anchor)


## One island: `need` (1 or 2) walls around `anchor`, parallel or an L, the second 40..56 px from the first.
static func _cluster_pair(theme: MapTheme, rng: RandomNumberGenerator, anchor: Vector2, lengths: Array[float],
		need: int) -> Array[Rect2]:
	var t := WallScript.THICKNESS
	var horizontal := rng.randf() < theme.horizontal_bias
	var l1 := _pick_length(rng, lengths)
	var l2 := _pick_length(rng, lengths)
	var gap := float(rng.randi_range(int(CLUSTER_GAP_MIN), int(CLUSTER_GAP_MAX)))
	var as_l := rng.randf() < 0.5
	var flip := rng.randf() < 0.5
	var shift := roundf(rng.randf_range(-0.25, 0.25) * minf(l1, l2))
	var out: Array[Rect2] = []
	if horizontal:
		var first := Rect2(Vector2(roundf(anchor.x - l1 / 2.0), anchor.y - t), Vector2(l1, t))
		out.append(first)
		if need > 1:
			if as_l:  # a wall hanging below one end
				var x := first.position.x if flip else first.end.x - t
				out.append(Rect2(Vector2(x, anchor.y + gap), Vector2(t, l2)))
			else:
				out.append(Rect2(Vector2(roundf(anchor.x - l2 / 2.0 + shift), anchor.y + gap), Vector2(l2, t)))
	else:
		var first := Rect2(Vector2(anchor.x - t, roundf(anchor.y - l1 / 2.0)), Vector2(t, l1))
		out.append(first)
		if need > 1:
			if as_l:  # a wall running right from one end
				var y := first.position.y if flip else first.end.y - t
				out.append(Rect2(Vector2(anchor.x + gap, y), Vector2(l2, t)))
			else:
				out.append(Rect2(Vector2(anchor.x + gap, roundf(anchor.y - l2 / 2.0 + shift)), Vector2(t, l2)))
	return out


# --- Pillars -------------------------------------------------------------------------------------------------------

## Distance from a point to a rectangle (0 inside).
static func point_rect_distance(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return Vector2(dx, dy).length()


## Whether a pillar whose collider centre is `c` is legal (spec 6.2): 60 px from the arena centre and off the start
## square, `band + 24` from the rock band, and 40 px (edge to edge) from every wall and every other pillar.
static func pillar_ok(c: Vector2, walls: Array[Rect2], centres: Array[Vector2], start: Rect2, size: Vector2) -> bool:
	var edge := BAND + PILLAR_EDGE
	if c.x < edge or c.y < edge or c.x > size.x - edge or c.y > size.y - edge:
		return false
	if c.distance_to(size / 2.0) < PILLAR_CENTRE_MIN or point_rect_distance(c, start) <= PILLAR_RADIUS:
		return false
	for rect in walls:
		if point_rect_distance(c, rect) - PILLAR_RADIUS < GAP_MIN:
			return false
	for other in centres:
		if c.distance_to(other) - 2.0 * PILLAR_RADIUS < GAP_MIN:
			return false
	return true


static func _place_pillars(theme: MapTheme, rng: RandomNumberGenerator, size: Vector2, start: Rect2,
		data: MapLayoutData, anchors: Array[Vector2]) -> void:
	var centres: Array[Vector2] = []
	var edge := BAND + PILLAR_EDGE
	var near_anchors := (theme.pillar_count + 1) / 2 if not anchors.is_empty() else 0
	for i in theme.pillar_count:
		var placed := false
		if i < near_anchors:  # CLUSTERS: first the pillars next to an island
			var anchor := anchors[i % anchors.size()]
			for attempt in 60:
				var c := (anchor + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, CLUSTER_PILLAR_REACH)).round()
				if pillar_ok(c, data.walls, centres, start, size):
					centres.append(c)
					placed = true
					break
		var tries := 0
		while not placed and tries < PILLAR_TRIES / maxi(theme.pillar_count, 1):
			tries += 1
			var c := Vector2(rng.randf_range(edge, size.x - edge), rng.randf_range(edge, size.y - edge)).round()
			if pillar_ok(c, data.walls, centres, start, size):
				centres.append(c)
				placed = true
	for c in centres:
		data.pillars.append(c - PILLAR_OFFSET)


# --- Torches -------------------------------------------------------------------------------------------------------

## `torch_count` torches spread over the four sides by length, evenly spaced with a little jitter, never within
## TORCH_CORNER of a corner. Positions sit on the rock band, as the hand-placed ones do.
static func _place_torches(theme: MapTheme, rng: RandomNumberGenerator, size: Vector2, out: Array[Vector2]) -> void:
	var lengths := [size.x, size.x, size.y, size.y]
	var total: float = lengths[0] + lengths[1] + lengths[2] + lengths[3]
	var counts := [0, 0, 0, 0]
	var remainders := []
	var used := 0
	for s in 4:
		var exact: float = theme.torch_count * lengths[s] / total
		counts[s] = int(exact)
		used += counts[s]
		remainders.append(exact - counts[s])
	while used < theme.torch_count:  # hand out the rest by largest remainder
		var best := 0
		for s in 4:
			if remainders[s] > remainders[best]:
				best = s
		counts[best] += 1
		remainders[best] = -1.0
		used += 1
	for s in 4:
		var span: float = lengths[s] - 2.0 * TORCH_CORNER
		var step: float = span / maxi(counts[s], 1)
		for k in counts[s]:
			var along: float = TORCH_CORNER + (k + 0.5) * step + rng.randf_range(-step * 0.2, step * 0.2)
			match s:
				0: out.append(Vector2(along, 9.0))
				1: out.append(Vector2(along, size.y - BAND + 1.0))
				2: out.append(Vector2(BAND - 3.0, along))
				_: out.append(Vector2(size.x - BAND + 3.0, along))


# --- Decor ---------------------------------------------------------------------------------------------------------

## As CaveDecor.layout: about a third along the rock band, the rest across the floor, but the kind comes from the
## theme's weights. Off the start square, the walls and the pillars.
static func _place_decor(theme: MapTheme, rng: RandomNumberGenerator, size: Vector2, start: Rect2,
		data: MapLayoutData) -> void:
	var kinds: Array = theme.decor_weights.keys()
	kinds.sort()
	var total := 0.0
	for kind in kinds:
		total += float(theme.decor_weights[kind])
	if kinds.is_empty() or total <= 0.0:
		return
	var keep_start := start.grow(DECOR_CLEARANCE)
	var inset := BAND + DECOR_EDGE
	var tries := 0
	while data.decor.size() < theme.decor_count and tries < DECOR_TRIES:
		tries += 1
		var roll := rng.randf() * total
		var kind: int = kinds[kinds.size() - 1]
		for k in kinds:
			roll -= float(theme.decor_weights[k])
			if roll < 0.0:
				kind = k
				break
		var pos: Vector2
		if rng.randf() < 0.35:
			pos = _near_band(rng, size, inset)
		else:
			pos = Vector2(rng.randf_range(inset, size.x - inset), rng.randf_range(inset + 12.0, size.y - inset))
		pos = pos.round()
		if keep_start.has_point(pos):
			continue
		var blocked := false
		for rect in data.walls:
			if rect.grow(DECOR_WALL_CLEARANCE).has_point(pos):
				blocked = true
				break
		if not blocked:
			for base in data.pillars:
				if pos.distance_to(base + PILLAR_OFFSET) < PILLAR_RADIUS + DECOR_WALL_CLEARANCE:
					blocked = true
					break
		if not blocked:
			data.decor.append({kind = kind, pos = pos, variant = rng.randi_range(0, 2)})


static func _near_band(rng: RandomNumberGenerator, size: Vector2, inset: float) -> Vector2:
	var depth := inset + rng.randf_range(0.0, 14.0)
	match rng.randi_range(0, 3):
		0:
			return Vector2(rng.randf_range(depth, size.x - depth), depth + 10.0)
		1:
			return Vector2(rng.randf_range(depth, size.x - depth), size.y - depth)
		2:
			return Vector2(depth, rng.randf_range(depth + 10.0, size.y - depth))
		_:
			return Vector2(size.x - depth, rng.randf_range(depth + 10.0, size.y - depth))

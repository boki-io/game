extends SceneTree
## Props never seal the green zone (spec 1.7 section 9): the zone's box is rasterised at one tile; obstacles are the blocked
## tiles (so also the wall colliders of depth 1 and 2) and the discs of the solid props; a window of 2 x 2 tiles with no
## obstacle is a gap the hero's 5 px circle fits through, and a 4-connected fill over such windows must, from the start camp,
## reach every zone-0 marker and at least 98 % of what the same fill reaches without props.
## Run: godot --headless --path . --script tests/overworld/nature_reach.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const Layout := preload("res://scripts/overworld/nature_layout.gd")
const Rules := preload("res://scripts/overworld/nature_rules.gd")
const FakeSprites := preload("res://tests/overworld/fake_nature_sprites.gd")
## The raster: the zone's box (x 0 to 1003, y 1539 to 1988) with a margin, so the gate's far side is in.
const X0 := 0
const X1 := 1040
const Y0 := 1500
const Y1 := 2000

var _failed := false
var _world


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_world = WorldDataS.shared()
	var rules: Rules = load("res://content/overworld/nature/mossy_hollow.tres")
	var sprites = FakeSprites.new()
	var cache := {}
	var solid := []
	for cy in range(Y0 / 32, Y1 / 32 + 1):
		for cx in range(X0 / 32, X1 / 32 + 1):
			for p in Layout.props_for_chunk(_world, rules, sprites, Vector2i(cx, cy), cache):
				if p.solid_radius > 0.0:
					solid.append(p)
	var bare := _grid()
	var with := _grid()
	for p in solid:
		_stamp(with, p.base, p.solid_radius)
	var start: Dictionary = _world.start_marker()
	var from_bare := _fill(bare, start)
	var from_with := _fill(with, start)
	var bare_count := _count(from_bare)
	var with_count := _count(from_with)
	# The windows a prop covers are not reachable by definition; the share is of the windows props leave open.
	var left_open := 0
	for y in Y1 - Y0 - 1:
		for x in X1 - X0 - 1:
			if from_bare[y * (X1 - X0) + x] == 1 and _window_open(with, x, y):
				left_open += 1
	var share := float(with_count) / maxi(left_open, 1)
	print("solid props %d, reach without props %d windows, props cover %d, with props %d reached of %d left open (%.1f %%)" % [solid.size(), bare_count, bare_count - left_open, with_count, left_open, share * 100.0])
	_check(bare_count > 20_000, "the fill without props covers the zone (%d)" % bare_count)
	_check(share >= 0.98, "props seal off at most 2 %% of the ground they leave open (%.1f %%)" % (share * 100.0))
	var zone0 := 0
	for m in _world.markers:
		if int(m.zone) != 0:
			continue
		zone0 += 1
		var bare_ok := _reached(from_bare, m)
		_check(_reached(from_with, m), "marker %s (%s) is reachable from the start camp with props%s" % [m.name, m.kind, "" if bare_ok else " (and not even without them)"])
	_check(zone0 >= 10, "zone 0 has markers (%d)" % zone0)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## One byte per tile of the raster: 1 for a blocked tile.
func _grid() -> PackedByteArray:
	var w := X1 - X0
	var g := PackedByteArray()
	g.resize(w * (Y1 - Y0))
	for ty in range(Y0, Y1):
		var row := ty * WorldDataS.SIZE
		for tx in range(X0, mini(X1, WorldDataS.SIZE)):
			if _world.collision[row + tx] <= 127:
				g[(ty - Y0) * w + tx - X0] = 1
	return g


## Marks the tiles the disc touches.
func _stamp(g: PackedByteArray, at: Vector2, radius: float) -> void:
	var w := X1 - X0
	for ty in range(floori((at.y - radius) / 16.0), floori((at.y + radius) / 16.0) + 1):
		for tx in range(floori((at.x - radius) / 16.0), floori((at.x + radius) / 16.0) + 1):
			if tx < X0 or tx >= X1 or ty < Y0 or ty >= Y1:
				continue
			var nx := clampf(at.x, tx * 16.0, tx * 16.0 + 16.0)
			var ny := clampf(at.y, ty * 16.0, ty * 16.0 + 16.0)
			if Vector2(nx, ny).distance_to(at) < radius:
				g[(ty - Y0) * w + tx - X0] = 1


func _window_open(g: PackedByteArray, x: int, y: int) -> bool:
	var w := X1 - X0
	if x < 0 or y < 0 or x >= w - 1 or y >= Y1 - Y0 - 1:
		return false
	var i := y * w + x
	return g[i] == 0 and g[i + 1] == 0 and g[i + w] == 0 and g[i + w + 1] == 0


## The windows reachable from the marker (a window is named by its top-left tile): 1 where reached.
func _fill(g: PackedByteArray, from: Dictionary) -> PackedByteArray:
	var w := X1 - X0
	var h := Y1 - Y0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue := PackedInt32Array()
	queue.resize(w * h)
	var head := 0
	var tail := 0
	var tx := int(from.x) - X0
	var ty := int(from.y) - Y0
	for d in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		if tail == 0 and _window_open(g, tx + d.x, ty + d.y):
			queue[0] = (ty + d.y) * w + tx + d.x
			seen[queue[0]] = 1
			tail = 1
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		for n in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
			if n.x >= 0 and n.y >= 0 and n.x < w - 1 and n.y < h - 1:
				var j: int = n.y * w + n.x
				if seen[j] == 0 and _window_open(g, n.x, n.y):
					seen[j] = 1
					queue[tail] = j
					tail += 1
	return seen


func _count(seen: PackedByteArray) -> int:
	var n := 0
	for v in seen:
		n += v
	return n


## Whether a window covering the marker's tile was reached.
func _reached(seen: PackedByteArray, m: Dictionary) -> bool:
	var w := X1 - X0
	var tx := int(m.x) - X0
	var ty := int(m.y) - Y0
	for d in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var x: int = tx + d.x
		var y: int = ty + d.y
		if x >= 0 and y >= 0 and x < w and y < Y1 - Y0 and seen[y * w + x] == 1:
			return true
	return false

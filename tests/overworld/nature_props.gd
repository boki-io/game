extends SceneTree
## The nature props as nodes (spec 1.7 section 5): `WorldProps` builds a chunk's sprites and trunk colliders when the terrain
## builds the chunk and frees them with it, solid props (trunks, big rocks) have circle colliders on layer 1 and the others
## none, a flipped placement is mirrored, the nodes are set up to y-sort with the players (checked structurally: Godot gives no
## sorted-order API and the dummy renderer draws nothing), and building a chunk's props is fast.
## Run: godot --headless --path . --script tests/overworld/nature_props.gd

const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const TerrainS := preload("res://scripts/overworld/world_terrain.gd")
const PropsS := preload("res://scripts/overworld/world_props.gd")
const LayoutS := preload("res://scripts/overworld/nature_layout.gd")
const SpritesS := preload("res://scripts/overworld/nature_sprites.gd")
const MS_BOUND := 30.0

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _initialize() -> void:
	var world = WorldDataS.shared()
	var rules = load("res://content/overworld/nature/mossy_hollow.tres")
	var holder := Node2D.new()
	holder.y_sort_enabled = true
	root.add_child(holder)
	var terrain = TerrainS.new()
	holder.add_child(terrain)
	terrain.setup(world)
	var props = PropsS.new()
	props.y_sort_enabled = true
	holder.add_child(props)
	props.setup(world, rules, terrain)

	_check(props.y_sort_enabled and holder.y_sort_enabled, "World/Props and its parent are y-sorted")

	# the chunks around the start camp: row 48..62, columns 0..31
	var busiest := Vector2i(-1, -1)
	var most := 0
	var cache := {}
	for cy in range(48, 63):
		for cx in range(0, 32):
			var n: int = LayoutS.props_for_chunk(world, rules, SpritesS, Vector2i(cx, cy), cache).size()
			if n > most:
				most = n
				busiest = Vector2i(cx, cy)
	_check(most > 20, "a chunk of the green zone holds props (busiest has %d)" % most)

	terrain.build_chunk_now(busiest)
	var placements: Array = LayoutS.props_for_chunk(world, rules, SpritesS, busiest)
	var nodes: Array = props.chunk_nodes(busiest)
	var sprites := 0
	var bodies := 0
	for n in nodes:
		if n is Sprite2D:
			sprites += 1
		elif n is StaticBody2D:
			bodies += 1
	_check(sprites == placements.size(), "one Sprite2D per placement (%d vs %d)" % [sprites, placements.size()])
	var solid := 0
	for p in placements:
		if p.solid_radius > 0.0:
			solid += 1
	_check(solid > 0, "the busiest chunk has solid props")
	_check(bodies == (1 if solid > 0 else 0), "one props body for the chunk")
	var circles := 0
	for n in nodes:
		if n is StaticBody2D:
			_check(n.collision_layer == 1 and n.collision_mask == 0, "props body is on the wall layer")
			for cs in n.get_children():
				if cs is CollisionShape2D and cs.shape is CircleShape2D:
					circles += 1
	_check(circles == solid, "a circle per solid prop (%d vs %d)" % [circles, solid])

	var i := 0
	for p in placements:
		var s: Sprite2D = nodes[i]
		i += 1
		if i > placements.size():
			break
		_check(s.global_position.is_equal_approx(p.base), "sprite %d stands at its base" % i)
		_check((s.scale.x < 0.0) == p.flip, "sprite %d is mirrored iff flipped" % i)
		_check(s.z_index == 0 and s.region_enabled, "sprite %d: z 0, region on" % i)

	# frees with the chunk
	terrain.free_chunk_now(busiest)
	await process_frame
	await process_frame
	_check(props.chunk_nodes(busiest).is_empty(), "the chunk's props are dropped from the node list")
	var left := 0
	for n in nodes:
		if is_instance_valid(n):
			left += 1
	_check(left == 0, "freeing the chunk frees every prop node (%d left)" % left)
	_check(props.get_child_count() == 0, "World/Props has no children left")

	# speed: mean over 20 zone chunks, cold cache
	var chunks: Array[Vector2i] = []
	for cy in range(50, 60, 2):
		for cx in range(2, 30, 6):
			chunks.append(Vector2i(cx, cy))
	var t0 := Time.get_ticks_usec()
	for c in chunks:
		props.free_chunk(c)
		props._cache.clear()
		props.build_chunk(c)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / chunks.size()
	print("props build: %.2f ms per chunk over %d chunks" % [ms, chunks.size()])
	_check(ms < MS_BOUND, "building a chunk's props takes %.1f ms (bound %.0f)" % [ms, MS_BOUND])

	# a chunk outside the zone has none, and without rules nothing is built
	var empty = PropsS.new()
	holder.add_child(empty)
	empty.build_chunk(busiest)
	_check(empty.get_child_count() == 0, "a node without rules builds nothing")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

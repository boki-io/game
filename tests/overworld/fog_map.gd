extends SceneTree
## Fog of war, the minimap and the world map (spec 1.6): the reveal disc and its cell count, a repeated reveal reporting no
## change, the 62,500-byte array shared with the journey, the texture rebuilt only on change, the world edge, a wrong-sized input;
## the minimap's source square, marker dots on revealed cells only and the zone name; the world map opening with M (pausing) and
## closing with M or Esc.
## Run: godot --headless --path . --script tests/overworld/fog_map.gd

const FogMapS := preload("res://scripts/overworld/fog_map.gd")
const JourneyS := preload("res://scripts/overworld/journey.gd")
const WorldDataS := preload("res://scripts/overworld/world_data.gd")
const MinimapS := preload("res://scripts/ui/minimap.gd")
const WorldMapS := preload("res://scripts/ui/world_map.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	_reveal()
	_texture()
	_input_sizes()
	await _minimap()
	await _world_map()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Cells whose centre is within `radius` tiles of the cell centre (cx, cy), counted by brute force over the whole grid.
func _expected(cx: int, cy: int, radius: float) -> int:
	var n := 0
	for y in 250:
		for x in 250:
			if Vector2(x - cx, y - cy).length() * 8.0 <= radius:
				n += 1
	return n


func _reveal() -> void:
	var fog = FogMapS.new()
	var centre := Vector2(125 * 8 + 4, 125 * 8 + 4) * 16.0  # the centre of cell (125, 125), in world px
	_check(fog.reveal(centre, 30.0), "the first reveal changes cells")
	var want := _expected(125, 125, 30.0)
	_check(fog.revealed_count() == want and want > 30, "a 30 tile disc reveals %d cells (got %d)" % [want, fog.revealed_count()])
	_check(fog.is_revealed_tile(Vector2i(125 * 8 + 4, 125 * 8 + 4)), "the centre cell is revealed")
	_check(not fog.is_revealed_tile(Vector2i(125 * 8 + 4 + 40, 125 * 8 + 4)), "a cell 40 tiles away is not")
	_check(fog.is_revealed_world(centre) and not fog.is_revealed_world(centre + Vector2(40 * 16, 0)), "is_revealed_world agrees")
	_check(not fog.reveal(centre, 30.0), "an identical second reveal reports no change")
	_check(fog.reveal(centre + Vector2(8 * 16, 0), 30.0), "a shifted reveal changes cells")
	# The disc uses the cell centres: a radius of 7.9 tiles around a cell centre reveals only that cell.
	var fog2 = FogMapS.new()
	fog2.reveal(centre, 7.9)
	_check(fog2.revealed_count() == 1, "a radius under one cell reveals one cell (%d)" % fog2.revealed_count())
	# The world edge is safe, including positions outside the map.
	var edge = FogMapS.new()
	_check(edge.reveal(Vector2.ZERO) and edge.is_revealed_tile(Vector2i(0, 0)), "reveal at the top left corner")
	_check(edge.reveal(Vector2(31999, 31999)) and edge.is_revealed_tile(Vector2i(1999, 1999)), "reveal at the bottom right corner")
	edge.reveal(Vector2(-500, 40000))
	_check(edge.revealed_count() > 0, "reveal off the map does not crash")
	_check(not edge.is_revealed_tile(Vector2i(-1, 5)) and not edge.is_revealed_tile(Vector2i(5, 2000)), "tiles outside are never revealed")


func _texture() -> void:
	var fog = FogMapS.new()
	var t1 = fog.texture()
	var count: int = fog.rebuild_count
	_check(t1.get_width() == 250 and t1.get_height() == 250, "the texture is 250 x 250")
	_check(fog.image().get_pixel(10, 10).a == 1.0, "unrevealed is opaque black")
	fog.texture()
	_check(fog.rebuild_count == count, "no rebuild without a change")
	var pos := Vector2(100 * 8 * 16, 100 * 8 * 16)
	fog.reveal(pos)
	fog.texture()
	_check(fog.rebuild_count == count + 1, "one rebuild after a reveal")
	_check(fog.image().get_pixel(100, 100).a == 0.0 and fog.image().get_pixel(10, 10).a == 1.0, "revealed is transparent, the rest opaque")
	fog.reveal(pos)
	fog.texture()
	_check(fog.rebuild_count == count + 1, "a reveal that changed nothing does not rebuild")


func _input_sizes() -> void:
	var j = JourneyS.new()
	j.fog.resize(JourneyS.FOG_BYTES)
	var fog = FogMapS.new(j.fog)
	_check(fog.bytes().size() == 62500 and JourneyS.FOG_BYTES == 62500, "the serialised array is 62,500 bytes")
	fog.reveal(Vector2(16000, 16000))
	var in_journey := 0
	for b in j.fog:
		if b != 0:
			in_journey += 1
	_check(in_journey == fog.revealed_count() and in_journey > 0, "the journey's own array holds the reveal (%d)" % in_journey)
	var bad := PackedByteArray([1, 2, 3])
	var fixed = FogMapS.new(bad)
	_check(fixed.bytes().size() == 62500 and fixed.revealed_count() == 0, "a wrong-sized array is reset to zeroes")
	_check(bad.size() == 62500, "and it is the caller's array that was resized")


func _minimap() -> void:
	var world = WorldDataS.shared()
	var fog = FogMapS.new()
	var player := Node2D.new()
	var mini = MinimapS.new()
	root.add_child(player)
	root.add_child(mini)
	mini.bind(world, fog, player)
	await process_frame
	_check(mini.size.x == 96.0 and mini.mouse_filter == Control.MOUSE_FILTER_IGNORE, "96 px wide, ignores the mouse")
	# The source square: 192 tiles around the player, clamped inside the map.
	player.global_position = WorldDataS.world_of(Vector2i(1000, 1000))
	var r: Rect2 = mini.source_region()
	_check(r == Rect2(904, 904, 192, 192), "square centred on the player %s" % [r])
	for tile in [Vector2i(0, 0), Vector2i(1999, 1999), Vector2i(10, 1990), Vector2i(1990, 10)]:
		player.global_position = WorldDataS.world_of(tile)
		r = mini.source_region()
		_check(r.size == Vector2(192, 192) and r.position.x >= 0 and r.position.y >= 0 and r.end.x <= 2000 and r.end.y <= 2000, "clamped at %s: %s" % [tile, r])
	# Marker dots only on revealed cells and inside the square.
	var cp: Dictionary = {}
	for m in world.markers:
		if m.kind == "checkpoint":
			cp = m
			break
	var cp_pos: Vector2 = WorldDataS.marker_world(cp)
	player.global_position = cp_pos
	_check(mini.visible_marker_dots().is_empty(), "no dots while everything is fogged")
	fog.reveal(cp_pos, 4.0)
	var dots: Array = mini.visible_marker_dots()
	var kinds := []
	for d in dots:
		kinds.append(d.kind)
	_check(kinds.has(&"checkpoint"), "the revealed checkpoint shows")
	for d in dots:
		_check(d.pos.x >= 0 and d.pos.x <= 96 and d.pos.y >= 0 and d.pos.y <= 96, "dot inside the square")
		_check(d.kind != &"camp" and d.kind != &"cache" and d.kind != &"arena" and d.kind != &"start_camp", "camps, caches and arenas are not shown")
	var cp_dot: Dictionary = {}
	for d in dots:
		if d.kind == &"checkpoint":
			cp_dot = d
	_check(not cp_dot.is_empty() and cp_dot.color == Color("ffd866"), "checkpoints are yellow")
	# A marker in a revealed cell but outside the square is not drawn; one inside the square but fogged is not either.
	var far: Dictionary = {}
	for m in world.markers:
		if m.kind == "checkpoint" and WorldDataS.marker_world(m).distance_to(cp_pos) > 200 * 16:
			far = m
			break
	fog.reveal(WorldDataS.marker_world(far), 4.0)
	_check(mini.visible_marker_dots().size() == dots.size(), "a revealed marker outside the square is not drawn")
	var fresh = FogMapS.new()
	mini.bind(world, fresh, player)
	_check(mini.visible_marker_dots().is_empty(), "a new fog hides them again")
	# The zone name of the player's tile.
	for z in [0, 3, 7]:
		var route: Vector2i = world.main_path[int(world.zones[z].route_start_tile) / 8 + 2]
		player.global_position = WorldDataS.world_of(route)
		var want: String = str(world.zones[world.zone_at(route)].name)
		_check(mini.zone_name() == want and want != "", "zone name %s" % want)
	mini.queue_free()
	player.queue_free()


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _world_map() -> void:
	var world = WorldDataS.shared()
	var fog = FogMapS.new()
	var player := Node2D.new()
	var wm = WorldMapS.new()
	root.add_child(player)
	root.add_child(wm)
	wm.bind(world, fog, player)
	await process_frame
	_check(InputMap.has_action(&"world_map"), "the world_map action exists")
	_check(not wm.is_open and not paused, "closed at first")
	_press(&"world_map")
	await process_frame
	_check(wm.is_open and paused and wm.visible, "M opens the map and pauses")
	_press(&"world_map")
	await process_frame
	_check(not wm.is_open and not paused, "M closes it and unpauses")
	_press(&"world_map")
	await process_frame
	_press(&"ui_cancel")
	await process_frame
	_check(not wm.is_open and not paused, "Esc (ui_cancel) closes it")
	wm.open()
	_press(&"pause")
	await process_frame
	_check(not wm.is_open and not paused, "the pause action closes it too")
	_check(absf(wm.map_scale() - 0.18) < 0.001, "scale about 0.18 (%f)" % wm.map_scale())
	wm.queue_free()
	player.queue_free()
	paused = false

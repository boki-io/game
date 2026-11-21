class_name WorldMap
extends Control
## The world map screen (spec 1.6): the whole world map scaled to fit the 640 x 360 view, the fog over it, the markers on
## revealed cells, the player's blinking dot and the names of the lit checkpoints. Opened by the `world_map` action (M), closed
## by M or Esc; pauses the tree while open. View only (no fast travel).

const WORLD_MAP := "res://content/overworld/data/world_map.png"
const VIEW := Vector2(640, 360)
const BLINK := 0.5
const FRAME := Color("6b4a2b")

var world: WorldData
var fog: FogMap
var player: Node2D
## The names of the activated checkpoints (set by the owner); a lit checkpoint on a revealed cell is labelled.
var lit_checkpoints: Array[String] = []
var is_open := false
var _map: Texture2D
var _time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # the downscale only
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = VIEW
	visible = false
	_map = load(WORLD_MAP)


func bind(world_data: WorldData, fog_map: FogMap, player_node: Node2D) -> void:
	world = world_data
	fog = fog_map
	player = player_node


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_time = 0.0
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false


## Scale of the map on screen (fits the shorter side).
func map_scale() -> float:
	return minf(VIEW.x, VIEW.y) / float(WorldData.SIZE)


## Top left of the map on screen (centred).
func map_origin() -> Vector2:
	return (VIEW - Vector2.ONE * WorldData.SIZE * map_scale()) / 2.0


func _to_screen(world_pos: Vector2) -> Vector2:
	return map_origin() + world_pos / float(WorldData.TILE_PX) * map_scale()


func _process(delta: float) -> void:
	if is_open:
		_time += delta
		queue_redraw()


## M and Esc close the screen; M opens it. Read in _input so the PauseMenu never sees the Esc that closes it.
func _input(event: InputEvent) -> void:
	if is_open:
		if event.is_action_pressed(&"world_map") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"world_map") and not get_tree().paused and world != null:
		open()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not is_open or world == null or fog == null:
		return
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0a0a10"))  # opaque, so the minimap and the HUD underneath do not show through
	var side := WorldData.SIZE * map_scale()
	var rect := Rect2(map_origin(), Vector2(side, side))
	draw_texture_rect(_map, rect, false)
	draw_texture_rect(fog.texture(), rect, false)
	draw_rect(rect, FRAME, false, 1.0)
	var font := ThemeDB.fallback_font
	for m in world.markers:
		var kind := StringName(m.kind)
		if not Minimap.DOT_COLORS.has(kind):
			continue
		var wp := WorldData.marker_world(m)
		if not fog.is_revealed_world(wp):
			continue
		var p := _to_screen(wp)
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Minimap.DOT_COLORS[kind])
		if kind == &"checkpoint" and lit_checkpoints.has(str(m.name)):
			draw_string(font, p + Vector2(4, 3), str(m.name), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 8, Color("ffd866"))
	if is_instance_valid(player) and fmod(_time, BLINK * 2.0) < BLINK:
		var me := _to_screen(player.global_position)
		draw_rect(Rect2(me - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
	draw_string(font, Vector2(8, 14), "World map   (M or Esc to close)", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)

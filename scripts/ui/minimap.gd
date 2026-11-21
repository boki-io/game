class_name Minimap
extends Control
## The overworld minimap (spec 1.6): 96 x 96 px at the top left under the mana bar, showing a 192-tile square of the world map
## around the player (2 tiles per pixel) with the fog over it, the player as a white dot, and the markers as small coloured
## dots on revealed cells only. The square is clamped inside the map, so near an edge the player's dot leaves the centre.
## Under the frame: the display name of the player's zone. Redrawn about 10 times a second.

const WORLD_MAP := "res://content/overworld/data/world_map.png"
const SIZE := 96.0
const REGION_TILES := 192
const REDRAW_INTERVAL := 0.1
const FRAME := Color("6b4a2b")
## Marker kind -> dot colour; kinds not listed (camps, caches, arenas, the start camp) are not shown.
const DOT_COLORS := {
	&"checkpoint": Color("ffd866"),
	&"cave": Color("e04040"),
	&"dungeon": Color("e04040"),
	&"final_dungeon": Color("e04040"),
	&"gate": Color("4a90e8"),
	&"special": Color("58c85a"),
}

var world: WorldData
var fog: FogMap
var player: Node2D
var _map: Texture2D
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(6, 26)
	size = Vector2(SIZE, SIZE + 12.0)
	_map = load(WORLD_MAP)


func bind(world_data: WorldData, fog_map: FogMap, player_node: Node2D) -> void:
	world = world_data
	fog = fog_map
	player = player_node
	queue_redraw()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REDRAW_INTERVAL:
		_timer = 0.0
		queue_redraw()


## The square of the world map shown, in tiles (= map pixels): REGION_TILES wide, centred on the player and clamped inside the map.
func source_region() -> Rect2:
	var tile := Vector2i.ZERO
	if is_instance_valid(player):
		tile = WorldData.tile_of(player.global_position)
	var origin := Vector2i(
		clampi(tile.x - REGION_TILES / 2, 0, WorldData.SIZE - REGION_TILES),
		clampi(tile.y - REGION_TILES / 2, 0, WorldData.SIZE - REGION_TILES))
	return Rect2(Vector2(origin), Vector2(REGION_TILES, REGION_TILES))


## Where a world position falls in the minimap (px), or null outside the square.
func _to_map(world_pos: Vector2, region: Rect2) -> Variant:
	var tiles := world_pos / float(WorldData.TILE_PX)
	var p := (tiles - region.position) * (SIZE / REGION_TILES)
	if p.x < 1.0 or p.y < 1.0 or p.x > SIZE - 1.0 or p.y > SIZE - 1.0:
		return null
	return p


## The marker dots drawn: `pos` (minimap px), `color` and the marker `kind`, only inside the square and on revealed cells.
func visible_marker_dots() -> Array[Dictionary]:
	var dots: Array[Dictionary] = []
	if world == null or fog == null:
		return dots
	var region := source_region()
	for m in world.markers:
		var kind := StringName(m.kind)
		if not DOT_COLORS.has(kind):
			continue
		var wp := WorldData.marker_world(m)
		if not fog.is_revealed_world(wp):
			continue
		var p: Variant = _to_map(wp, region)
		if p != null:
			dots.append({"pos": p, "color": DOT_COLORS[kind], "kind": kind})
	return dots


## The display name of the zone of the player's tile.
func zone_name() -> String:
	if world == null or not is_instance_valid(player):
		return ""
	var z := world.zone_at(WorldData.tile_of(player.global_position))
	return str(world.zones[z].name)


func _draw() -> void:
	if world == null or fog == null or not is_instance_valid(player):
		return
	var region := source_region()
	var rect := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_texture_rect_region(_map, rect, region)
	var cells := float(OverworldRules.FOG_CELL_TILES)
	draw_texture_rect_region(fog.texture(), rect, Rect2(region.position / cells, region.size / cells))
	for d in visible_marker_dots():
		draw_rect(Rect2(d.pos - Vector2(1.5, 1.5), Vector2(3, 3)), d.color)
	var me: Variant = _to_map(player.global_position, region)
	if me != null:
		draw_rect(Rect2(me - Vector2(1.5, 1.5), Vector2(3, 3)), Color.WHITE)
	draw_rect(rect, FRAME, false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, SIZE + 9.0), zone_name(), HORIZONTAL_ALIGNMENT_LEFT, SIZE + 40.0, 8, Color.WHITE)

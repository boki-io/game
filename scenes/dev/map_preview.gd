extends Node2D
## The map workbench (spec 0.6, 3.6): builds one arena with MapBuilder, the same code main.gd uses, with a row of the
## three monster looks near the centre. Run it with F6 or `godot --path . scenes/dev/map_preview.tscn`.
## Keys: Tab next map, R new seed, L reload the map files from disk, O overlay (obstacle footprints and flow field),
## Z whole-arena zoom, arrow keys pan. With `walk` on, a Player (WASD) walks the map and the flow field starts at it.
## Reads and writes nothing in GameSession; excluded from exported builds.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_PATHS := ["res://content/enemies/grunt.tres", "res://content/enemies/ranged.tres", "res://content/enemies/dasher.tres"]
const MONSTER_SPACING := 40.0
const PAN_SPEED := 300.0

## The map to show (a map.tres); empty shows the first map of the registry.
@export var map: MapTheme
## The map seed (the layout and the floor).
@export var seed := 1
## Put a Player in the map to test blocking and flow.
@export var walk := false

var overlay_on := false
var zoomed_out := false
## False hides the key help (the screenshot tool).
var show_info := true

var _targets: MapBuilder.Targets
var _layout: MapLayoutData
var _player: Node2D
var _flow: FlowField
var _flow_cell := Vector2i(-1, -1)

@onready var _camera: Camera2D = $Camera
@onready var _overlay: Node2D = $Overlay
@onready var _info: Label = $UI/Info


func _ready() -> void:
	_overlay.draw.connect(_draw_overlay)
	_camera.position = Vector2(Arena.world_size) / 2.0
	rebuild()


## Shows `theme` with `new_seed` (the shot tool calls this).
func show_map(theme: MapTheme, new_seed: int) -> void:
	map = theme
	seed = new_seed
	rebuild()


## Rebuilds the arena from `map` and `seed`.
func rebuild() -> void:
	if map == null:
		map = MapRegistry.all()[0]
	for node in [$World/Props, $World/Decor, $World/Enemies, $World/Players]:
		for child in node.get_children():
			node.remove_child(child)
			child.queue_free()
	if _targets != null and _targets.obstacles != null:
		remove_child(_targets.obstacles)
		_targets.obstacles.queue_free()
	_player = null
	_targets = MapBuilder.Targets.new()
	_targets.ground = $World/Ground
	_targets.cave = $Cave
	_targets.props = $World/Props
	_targets.decor = $World/Decor
	_targets.ambient_parent = self
	_targets.ambience_parent = $World
	_targets.vignette = $UI/Vignette
	_targets.obstacles_parent = self
	_layout = MapBuilder.build(map, seed, Vector2(Arena.world_size), _targets)
	_spawn_monsters()
	if walk:
		_spawn_player()
	_flow_cell = Vector2i(-1, -1)
	_update_flow()
	_update_camera()
	_update_info()
	_overlay.queue_redraw()


## Loads the map's files again from disk (the map and the monster looks it names) and rebuilds.
func reload_from_disk() -> void:
	var path := map.resource_path
	if path != "":
		var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as MapTheme
		if fresh != null:
			map = fresh
	rebuild()


func next_map() -> void:
	var all := MapRegistry.all()
	var at := 0
	for i in all.size():
		if all[i].id == map.id:
			at = (i + 1) % all.size()
			break
	map = all[at]
	rebuild()


## Where the monster row stands (its middle).
func monster_centre() -> Vector2:
	return Vector2(Arena.world_size) / 2.0 + Vector2(0.0, 40.0)


func _spawn_monsters() -> void:
	for i in ENEMY_PATHS.size():
		var data: EnemyData = load(ENEMY_PATHS[i])
		var enemy = ENEMY_SCENE.instantiate()  # untyped: Enemy uses autoloads, and the shot tool compiles before they exist
		enemy.data = data
		enemy.position = monster_centre() + Vector2((i - 1) * MONSTER_SPACING, 0.0)
		$World/Enemies.add_child(enemy)
		enemy.apply_variant(map.variant_for(data.id))
		enemy.process_mode = Node.PROCESS_MODE_DISABLED  # a still sample, not an enemy in play


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.character = CharacterRegistry.all()[0]
	_player.position = Vector2(Arena.world_size) / 2.0 - Vector2(0.0, 40.0)
	$World/Players.add_child(_player)


func _update_camera() -> void:
	var view := get_viewport().get_visible_rect().size
	var world := Vector2(Arena.world_size)
	var fit := minf(view.x / world.x, view.y / world.y)
	_camera.zoom = Vector2.ONE * (fit if zoomed_out else 1.0)
	if zoomed_out:
		_camera.position = world / 2.0


func _update_info() -> void:
	_info.visible = show_info
	_info.text = "%s  seed %d  %s%s\nTab map  R seed  L reload  O overlay  Z zoom  arrows pan" % [
		map.display_name, seed, "overlay " if overlay_on else "", "walk" if walk else ""]


## The flow field the enemies would use, for the overlay: from the Player, or from the arena centre.
func _update_flow() -> void:
	if not overlay_on or _targets == null or _targets.obstacles == null:
		return
	var source := _player.position if _player != null else Vector2(Arena.world_size) / 2.0
	var cell := FlowField.cell_of(source)
	if cell == _flow_cell and _flow != null:
		return
	_flow_cell = cell
	_flow = FlowField.new()
	_flow.setup(_targets.obstacles)
	_flow.begin([source] as Array[Vector2])
	_flow.step(1000000)
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if _player != null:
		_camera.position = _player.position.clamp(Vector2(_viewport_half()), Vector2(Arena.world_size) - Vector2(_viewport_half()))
		_update_flow()
	elif not zoomed_out:
		var pan := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
		_camera.position += pan * PAN_SPEED * delta
		_camera.position = _camera.position.clamp(Vector2(_viewport_half()), Vector2(Arena.world_size) - Vector2(_viewport_half()))


func _viewport_half() -> Vector2i:
	return Vector2i(get_viewport().get_visible_rect().size / 2.0)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			next_map()
		KEY_R:
			seed = randi() % 100000  # a dev tool: the shown seed is printed in the label, so a look can be repeated
			rebuild()
		KEY_L:
			reload_from_disk()
		KEY_O:
			overlay_on = not overlay_on
			_flow_cell = Vector2i(-1, -1)
			_update_flow()
			_update_info()
			_overlay.queue_redraw()
		KEY_Z:
			zoomed_out = not zoomed_out
			_update_camera()
	get_viewport().set_input_as_handled()


## Obstacle footprints (walls as rects, pillars as circles, in yellow) and the flow field: blocked cells red, the
## walking distance as a blue-to-green wash, unreached free cells magenta, and a small arrow every third cell.
func _draw_overlay() -> void:
	if not overlay_on or _targets == null or _targets.obstacles == null:
		return
	if _flow != null:
		var far := 1
		for y in _flow.height:
			for x in _flow.width:
				far = maxi(far, _flow.distance(Vector2i(x, y)))
		for y in _flow.height:
			for x in _flow.width:
				var cell := Vector2i(x, y)
				var rect := Rect2(Vector2(cell) * FlowField.CELL, Vector2.ONE * FlowField.CELL)
				if _flow.is_blocked(cell):
					_overlay.draw_rect(rect, Color(1.0, 0.1, 0.1, 0.28))
					continue
				var d := _flow.distance(cell)
				if d < 0:
					_overlay.draw_rect(rect, Color(1.0, 0.1, 1.0, 0.35))
					continue
				_overlay.draw_rect(rect, Color(0.2, 0.4, 1.0, 0.0).lerp(Color(0.3, 1.0, 0.4, 0.22), float(d) / far))
				if x % 3 == 0 and y % 3 == 0:
					var from := rect.get_center()
					var dir := _flow.direction_at(from)
					if dir != Vector2.ZERO:
						_overlay.draw_line(from, from + dir * 9.0, Color(1, 1, 1, 0.55), 1.0)
	for rect in _targets.obstacles.wall_rects():
		_overlay.draw_rect(rect, Color(1.0, 0.9, 0.2, 0.9), false, 1.0)
	for centre in _targets.obstacles.pillar_centers():
		_overlay.draw_arc(centre, ObstacleMap.PILLAR_RADIUS, 0.0, TAU, 16, Color(1.0, 0.9, 0.2, 0.9), 1.0)

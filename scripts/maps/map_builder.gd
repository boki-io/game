class_name MapBuilder
extends RefCounted
## Turns a MapTheme and a seed into an arena (spec 0.6 section 9): MapLayout.generate, then the ground, rock band,
## walls, pillars, decor, torches, ambient tint, vignette and the ObstacleMap, built into the nodes of `Targets`.
## `main.gd` and the map preview scene call the same function. No autoload is named, so a test can preload it.

## Enemies stay this far inside the rock band (Enemy.ARENA_PADDING; map_build.gd checks they are equal).
const ENEMY_PADDING := 6.0
const GroundScript := preload("res://scripts/systems/ground.gd")


## The nodes the arena is built into. Only `props`, `decor` and `cave` are required; null skips a part.
class Targets extends RefCounted:
	## The TileMapLayer with ground.gd (rebuilt with the theme's floor). Untyped: ground.gd has no class_name.
	var ground
	## The CaveWalls (rock band and torches).
	var cave: CaveWalls
	## Walls and pillars go here (y-sorted).
	var props: Node2D
	## Decor goes here.
	var decor: Node2D
	## The world's canvas, where the ambient CanvasModulate goes (not the UI layer).
	var ambient_parent: Node
	## The world node the Ambience (drifting motes) goes in; not the root, so the motes are in the world's canvas under the UI.
	var ambience_parent: Node
	## The vignette TextureRect (its darkness is set from the theme).
	var vignette: TextureRect
	## The ObstacleMap is added here, and also set in `obstacles` when it exists.
	var obstacles_parent: Node
	var obstacles: ObstacleMap


## The region enemies can stand in: inside the rock band plus their padding.
static func playable_rect(size: Vector2, band: float) -> Rect2:
	var pad := Vector2(band + ENEMY_PADDING, band + ENEMY_PADDING)
	return Rect2(pad, size - pad * 2.0)


## Builds the arena of `theme` for `map_seed` in a room of `size` into `targets` and returns the layout.
## The default theme (legacy layout) keeps today's floor seed; every other theme seeds the floor with the map seed.
static func build(theme: MapTheme, map_seed: int, size: Vector2, targets: Targets) -> MapLayoutData:
	var layout := MapLayout.generate(theme, map_seed, size)
	if targets.ground != null:
		targets.ground.setup(theme, GroundScript.DIRT_SEED if theme.legacy_layout else map_seed)
	if targets.cave != null:
		targets.cave.wall_band = MapLayout.BAND
		targets.cave.torches = layout.torches.slice(0, theme.torch_count)
		targets.cave.set_theme(theme)
	for rect in layout.walls:
		var wall := CaveWall.new()
		targets.props.add_child(wall)
		wall.setup(rect, theme)
	for pos in layout.pillars:
		var prop := Prop.new()
		prop.theme = theme
		prop.position = pos
		targets.props.add_child(prop)
	for item in layout.decor:
		var decor := CaveDecor.new()
		decor.theme = theme
		decor.kind = item.kind
		decor.variant = item.variant
		decor.position = item.pos
		targets.decor.add_child(decor)
	if targets.ambient_parent != null:
		MapLook.apply_ambient(targets.ambient_parent, theme)
	if targets.ambience_parent != null:
		MapLook.apply_ambience(targets.ambience_parent, theme, map_seed)
	if targets.vignette != null:
		MapLook.apply_vignette(targets.vignette, theme)
	if targets.obstacles_parent != null:
		var obstacles := ObstacleMap.new()
		obstacles.setup(layout.walls, layout.pillars, size, playable_rect(size, MapLayout.BAND))
		targets.obstacles_parent.add_child(obstacles)
		targets.obstacles = obstacles
	return layout

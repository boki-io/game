extends SceneTree
## MapBuilder in the real run scene (spec 0.6 sections 9 and 12): for each of the eight maps (and with no stage, the
## default cave) main.tscn is built with a StageData of that theme and the builder's work is checked: wall, pillar, decor
## and torch counts equal the layout, the theme's colours reached the rock band, the floor, the ambient tint and the
## vignette, the Player and an enemy still move and collide with the walls, and MapBuilder called on its own (as the
## preview scene does) gives the same layout as the run for the same theme and seed. Pixels are not read.
## Run: godot --headless --path . --script tests/maps/map_build.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const Layout := preload("res://scripts/maps/map_layout.gd")
const Builder := preload("res://scripts/maps/map_builder.gd")
const WallScript := preload("res://scripts/cave/cave_wall.gd")
const PropScript := preload("res://scripts/systems/prop.gd")
const DecorScript := preload("res://scripts/cave/cave_decor.gd")
const StageScript := preload("res://scripts/stages/stage_data.gd")

const SIZE := Vector2(1600, 896)

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _count(parent: Node, script: GDScript) -> int:
	var n := 0
	for c in parent.get_children():
		if c.get_script() == script:
			n += 1
	return n


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


## Pixels of tile `v` of the floor's atlas that have colour `c`.
func _tile_pixels(ground: TileMapLayer, v: int, c: Color) -> int:
	var img: Image = (ground.tile_set.get_source(0) as TileSetAtlasSource).texture.get_image()
	var q := Color8(c.r8, c.g8, c.b8)  # the image is 8 bits per channel
	var n := 0
	for x in 16:
		for y in 16:
			if _near(img.get_pixel(v * 16 + x, y), q):
				n += 1
	return n


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var session = root.get_node("GameSession")
	# PlayerInput ignores input while the boot iris is still opening (SceneFader.busy), so the first map's walk would lose frames.
	for i in 120:
		if not root.get_node("SceneFader").busy:
			break
		await physics_frame
	_check(Builder.ENEMY_PADDING == load("res://scripts/enemy/enemy.gd").ARENA_PADDING, "the builder's enemy padding equals Enemy.ARENA_PADDING")
	var themes: Array = Registry.all()
	themes.append(null)  # no stage: the default cave
	for i in themes.size():
		var theme = themes[i]
		var tag := "[%s] " % (theme.id if theme else "default")
		session.current_stage = null
		if theme:
			var stage = StageScript.new()
			stage.theme = theme
			session.current_stage = stage
			session.path_seed = 1000 + i
		else:
			session.path_seed = 0
		var map_theme = theme if theme else Registry.default()
		var map_seed: int = session.map_seed()
		var expected = Layout.generate(map_theme, map_seed, SIZE)
		var main: Node = F.start_run(self, &"knight")
		await F.frames(self, 3)

		# The drifting motes of the theme (the default cave for no theme), in the world node.
		var ambience: Node = main.get_node_or_null("World/Ambience")
		_check(ambience != null and ambience.kind == map_theme.ambience_kind and ambience.motes().size() == map_theme.ambience_count, tag + "the run has the theme's Ambience")

		# The same layout as the generator, in the nodes.
		var props: Node = main.get_node("World/Props")
		_check(_count(props, WallScript) == expected.walls.size(), tag + "wall count equals the layout")
		_check(_count(props, PropScript) == expected.pillars.size(), tag + "pillar count equals the layout")
		_check(main.get_node("World/Decor").get_child_count() == expected.decor.size(), tag + "decor count equals the layout")
		_check(main.rock_walls == expected.walls, tag + "main.rock_walls is the layout's walls")
		_check(main.prop_positions == expected.pillars, tag + "main.prop_positions is the layout's pillars")
		var cave = main.get_node("Cave")
		_check(cave.torches.size() == map_theme.torch_count and cave.torches == expected.torches.slice(0, map_theme.torch_count), tag + "torches equal the layout, trimmed to torch_count")
		var obstacles: ObstacleMap = main.spawn_director.obstacles
		_check(obstacles != null and obstacles.get_parent() == main, tag + "the director has an ObstacleMap")

		# The theme reached the look.
		var ground: TileMapLayer = main.get_node("World/Ground")
		_check(cave.theme == map_theme, tag + "CaveWalls has the theme")
		_check(ground.theme == map_theme, tag + "Ground has the theme")
		_check(_tile_pixels(ground, 4, map_theme.floor_dark) >= 150, tag + "the floor's dark tile is the theme's floor_dark")
		_check(ground.floor_seed == (4242 if map_theme.legacy_layout else map_seed), tag + "floor seed")
		var ambient := main.get_node_or_null("Ambient") as CanvasModulate
		_check(ambient != null and ambient.color.is_equal_approx(map_theme.ambient), tag + "ambient tint is the theme's")
		var vignette := main.get_node("UI/Vignette") as TextureRect
		var grad: Gradient = (vignette.texture as GradientTexture2D).gradient
		_check(is_equal_approx(grad.get_color(grad.get_point_count() - 1).a, map_theme.vignette), tag + "vignette darkness is the theme's")

		# MapBuilder on its own (the preview scene) gives the same layout.
		var holder := Node2D.new()
		var props2 := Node2D.new()
		var decor2 := Node2D.new()
		root.add_child(holder)
		holder.add_child(props2)
		holder.add_child(decor2)
		var targets = Builder.Targets.new()
		targets.props = props2
		targets.decor = decor2
		targets.obstacles_parent = holder
		var standalone = Builder.build(map_theme, map_seed, SIZE, targets)
		_check(standalone.equals(expected), tag + "MapBuilder alone gives the generator's layout")
		_check(standalone.walls == main.rock_walls and standalone.pillars == main.prop_positions, tag + "the same walls and pillars as the run")
		_check(props2.get_child_count() == props.get_child_count(), tag + "the same number of nodes as the run")
		holder.free()

		# The Player moves and stops at a wall; an enemy beyond it does not end inside it.
		var p = F.player()
		p.hurtbox.invulnerable = true
		p.caster.set_physics_process(false)
		var start: Vector2 = p.global_position
		Input.action_press(&"move_up")
		await F.frames(self, 12)
		Input.action_release(&"move_up")
		_check(p.global_position.y < start.y - 3.0, tag + "the Player moves")
		if not expected.walls.is_empty():
			var wall: Rect2 = expected.walls[0]
			var mid := wall.get_center()
			# Left of the wall (a vertical wall) or above it (a horizontal one): walk into it.
			var vertical := wall.size.y > wall.size.x
			var dir := Vector2.RIGHT if vertical else Vector2.DOWN
			var offset := (wall.size.x if vertical else wall.size.y) / 2.0 + 30.0
			p.global_position = mid - dir * offset
			Input.action_press(&"move_right" if vertical else &"move_down")
			await F.frames(self, 60)
			Input.action_release(&"move_right" if vertical else &"move_down")
			var along: float = p.global_position.x if vertical else p.global_position.y
			var edge: float = wall.position.x if vertical else wall.position.y
			_check(along <= edge, tag + "the Player does not walk into wall 0 (%.1f vs %.1f)" % [along, edge])
			# A grunt on the far side moves and never ends inside the wall.
			p.global_position = mid - dir * offset
			var e = F.spawn_enemy(main, "grunt", mid + dir * offset, 1000.0)
			await F.frames(self, 60)
			_check(e.global_position.distance_to(mid + dir * offset) > 8.0, tag + "the enemy moves")
			_check(not wall.grow(5.0).has_point(e.global_position), tag + "the enemy is not inside wall 0")
		main.queue_free()
		await F.frames(self, 3)
	session.current_stage = null
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

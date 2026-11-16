extends SceneTree
## The look classes take their colours from a MapTheme (spec 0.6 section 8): the theme's colours reach Ground, CaveWalls
## (and its torches), CaveWall, Prop, CaveDecor and the vignette/ambient helper, and a null theme gives today's values.
## (The default theme's colours are stored with 8 digits, so they are compared with is_equal_approx.)
## No pixels of the screen are read (headless has a dummy renderer); the floor is checked in its tile image.
## Run: godot --headless --path . --script tests/maps/theme_look.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const GroundScript := preload("res://scripts/systems/ground.gd")
const PropScript := preload("res://scripts/systems/prop.gd")
const WallsScript := preload("res://scripts/cave/cave_walls.gd")
const WallScript := preload("res://scripts/cave/cave_wall.gd")
const DecorScript := preload("res://scripts/cave/cave_decor.gd")
const LookScript := preload("res://scripts/maps/map_look.gd")
const ThemeScript := preload("res://scripts/maps/map_theme.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## A theme whose every colour is distinct and unlike today's.
func _theme() -> MapTheme:
	var t: MapTheme = ThemeScript.new()
	t.floor_plain = [Color("102030"), Color("112131"), Color("122232"), Color("132333")]
	t.floor_dark = Color("0a141e")
	t.floor_light = Color("304050")
	t.floor_flecks = 0.3
	t.rock = Color("203040")
	t.rock_dark = Color("050a0f")
	t.rock_light = Color("405060")
	t.wall_top = Color("336699")
	t.wall_top_light = Color("4477aa")
	t.wall_side = Color("112244")
	t.wall_outline = Color("001122")
	t.pillar = Color("778899")
	t.torch_color = Color("22ff44")
	t.glow_color = Color("ff22aa")
	t.ambient = Color("e0f0ff")
	t.vignette = 0.45
	return t


## How many pixels of tile `v` in the floor's atlas have exactly colour `c`.
func _tile_pixels(ground: TileMapLayer, v: int, c: Color) -> int:
	var source: TileSetAtlasSource = ground.tile_set.get_source(0)
	var img: Image = source.texture.get_image()
	var n := 0
	for x in 16:
		for y in 16:
			if img.get_pixel(v * 16 + x, y).is_equal_approx(c):
				n += 1
	return n


func _ground(theme: MapTheme, seed_value: int = 4242) -> TileMapLayer:
	var g := TileMapLayer.new()
	g.set_script(GroundScript)
	g.look = 1  # DIRT
	g.setup(theme, seed_value)
	root.add_child(g)
	return g


func _cells(g: TileMapLayer) -> Array:
	var out := []
	for c in g.get_used_cells():
		out.append(g.get_cell_atlas_coords(c))
	return out


func _init() -> void:
	await process_frame
	await process_frame
	var theme := _theme()
	var default: MapTheme = Registry.default()

	# Floor: the theme's tile shades, dark and light patches, and the seed.
	var g_theme := _ground(theme)
	for v in 4:
		_check(_tile_pixels(g_theme, v, theme.floor_plain[v]) > 100, "floor tile %d is the theme's shade" % v)
	_check(_tile_pixels(g_theme, 4, theme.floor_dark) > 100, "dark patch tile is floor_dark")
	_check(_tile_pixels(g_theme, 5, theme.floor_light) > 100, "worn tile is floor_light")
	var g_null := _ground(null)
	var g_default := _ground(default)
	for v in 4:
		_check(_tile_pixels(g_null, v, GroundScript.DIRT_PLAIN[v]) > 100, "null theme: floor tile %d is today's constant" % v)
	_check(_tile_pixels(g_null, 4, GroundScript.DIRT_DARK) > 100, "null theme: dark tile is DIRT_DARK")
	_check(_tile_pixels(g_null, 5, GroundScript.DIRT_LIGHT) > 100, "null theme: light tile is DIRT_LIGHT")
	_check(_cells(g_null) == _cells(g_default), "the default theme lays the same floor as no theme")
	_check(_cells(_ground(theme, 1)) != _cells(_ground(theme, 2)), "a different floor seed gives a different floor")
	_check(_cells(_ground(theme, 5)) == _cells(_ground(theme, 5)), "the floor is seeded")
	var flecks := func(g: TileMapLayer) -> int:
		var n := 0
		for c in _cells(g):
			if c.x >= 6:
				n += 1
		return n
	_check(flecks.call(g_theme) > flecks.call(g_null), "floor_flecks 0.3 gives more pebbled and cracked tiles than today's 0.12")

	# Rock band and torches.
	var walls: Node2D = WallsScript.new()
	walls.theme = theme
	root.add_child(walls)
	_check(walls._rock == theme.rock and walls._rock_dark == theme.rock_dark and walls._rock_light == theme.rock_light,
		"CaveWalls rock colours come from the theme")
	_check(walls.halo_color() == theme.glow_color, "torch halo is glow_color")
	_check(walls.flame_color() == theme.torch_color, "torch flame is torch_color")
	var plain_walls: Node2D = WallsScript.new()
	root.add_child(plain_walls)
	_check(plain_walls._rock == WallsScript.ROCK and plain_walls._rock_dark == WallsScript.ROCK_DARK
		and plain_walls._rock_light == WallsScript.ROCK_LIGHT, "null theme: rock band is today's")
	_check(plain_walls.halo_color() == Color(1.0, 0.55, 0.2) and plain_walls.flame_color() == Color(1.0, 0.65, 0.2),
		"null theme: torches are today's oranges")
	var def_walls: Node2D = WallsScript.new()
	def_walls.theme = default
	root.add_child(def_walls)
	_check(def_walls._rock.is_equal_approx(plain_walls._rock) and def_walls._rock_dark.is_equal_approx(plain_walls._rock_dark)
		and def_walls._rock_light.is_equal_approx(plain_walls._rock_light), "the default theme's rock equals today's")
	_check(def_walls.halo_color().is_equal_approx(plain_walls.halo_color())
		and def_walls.flame_color().is_equal_approx(plain_walls.flame_color()),
		"the default theme's torches equal today's")

	# Freestanding wall.
	var rect := Rect2(100, 100, 96, 16)
	var wall: StaticBody2D = WallScript.new()
	root.add_child(wall)
	wall.setup(rect, theme)
	_check(wall._top == theme.wall_top and wall._top_light == theme.wall_top_light and wall._side == theme.wall_side
		and wall._outline == theme.wall_outline, "CaveWall colours come from the theme")
	var plain_wall: StaticBody2D = WallScript.new()
	root.add_child(plain_wall)
	plain_wall.setup(rect)
	_check(plain_wall._top == WallScript.TOP and plain_wall._top_light == WallScript.TOP_LIGHT
		and plain_wall._side == WallScript.SIDE and plain_wall._outline == WallScript.OUTLINE, "null theme: wall colours are today's")
	var def_wall: StaticBody2D = WallScript.new()
	root.add_child(def_wall)
	def_wall.setup(rect, default)
	_check(def_wall._top.is_equal_approx(plain_wall._top) and def_wall._top_light.is_equal_approx(plain_wall._top_light)
		and def_wall._side.is_equal_approx(plain_wall._side) and def_wall._outline.is_equal_approx(plain_wall._outline),
		"the default theme's wall colours equal today's")

	# Pillar.
	var prop: StaticBody2D = PropScript.new()
	prop.theme = theme
	_check(prop.stone() == theme.pillar, "Prop uses the theme's pillar colour")
	prop.theme = null
	_check(prop.stone() == Color("5c5248"), "null theme: the pillar is today's 5c5248")
	prop.theme = default
	_check(prop.stone().is_equal_approx(Color("5c5248")), "the default theme's pillar equals today's")
	prop.free()

	# Decor: new kinds are appended, the glow comes from the theme.
	_check(DecorScript.Kind.STALAGMITE == 0 and DecorScript.Kind.ROCK == 1 and DecorScript.Kind.PEBBLES == 2
		and DecorScript.Kind.BONES == 3 and DecorScript.Kind.MUSHROOM == 4, "the old decor kinds keep their numbers")
	var new_kinds := ["MOSS", "CRYSTAL", "ICICLE", "FROST", "BIG_FUNGUS", "PUDDLE", "VENT", "CRACK"]
	for i in new_kinds.size():
		_check(DecorScript.Kind[new_kinds[i]] == 5 + i, "decor kind %s is %d" % [new_kinds[i], 5 + i])
	for k in DecorScript.Kind.values():
		for variant in 3:
			var d: Node2D = DecorScript.new()
			d.kind = k
			d.variant = variant
			root.add_child(d)
			_check(d.glow_color() == DecorScript.GLOW, "null theme: decor glow is today's cyan")
			d.theme = theme
			_check(d.glow_color() == theme.glow_color, "decor glow is the theme's glow_color")
			d.queue_redraw()
	await process_frame  # every kind draws without a script error

	# Vignette and ambient.
	_check(LookScript.vignette_alpha(null) == 0.62, "null theme: vignette is 0.62")
	_check(LookScript.vignette_alpha(default) == 0.62, "the default theme's vignette is 0.62")
	_check(LookScript.vignette_alpha(theme) == 0.45, "vignette comes from the theme")
	var rect_node := TextureRect.new()
	var tex := GradientTexture2D.new()
	tex.gradient = Gradient.new()
	tex.gradient.offsets = PackedFloat32Array([0.5, 1.0])
	tex.gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.62)])
	rect_node.texture = tex
	_check(LookScript.apply_vignette(rect_node, theme), "apply_vignette finds the gradient")
	_check(is_equal_approx(rect_node.texture.gradient.get_color(1).a, 0.45), "the vignette's outer alpha is the theme's")
	_check(is_equal_approx(tex.gradient.get_color(1).a, 0.62), "the shared gradient resource is not changed")
	_check(LookScript.ambient_color(null) == Color.WHITE, "null theme: ambient is white")
	var holder := Node2D.new()
	root.add_child(holder)
	var mod: CanvasModulate = LookScript.apply_ambient(holder, theme)
	_check(mod.color == theme.ambient and mod.get_parent() == holder, "a CanvasModulate carries the theme's ambient")
	_check(LookScript.apply_ambient(holder, null) == mod and mod.color == Color.WHITE and holder.get_child_count() == 1,
		"apply_ambient updates the same node")

	# Ambience: created, updated in place and removed by apply_ambience.
	theme.ambience_kind = 2
	theme.ambience_count = 12
	var amb = LookScript.apply_ambience(holder, theme, 4)
	_check(amb != null and amb.kind == 2 and amb.motes().size() == 12 and amb.get_parent() == holder, "apply_ambience builds the theme's motes")
	theme.ambience_count = 0
	_check(LookScript.apply_ambience(holder, theme, 4) == null and holder.get_node_or_null("Ambience") == null, "a count of 0 removes the Ambience")
	var dust = LookScript.apply_ambience(holder, null, 4)
	_check(dust != null and dust.kind == 1 and dust.motes().size() == 40, "a null theme gives today's cave dust")

	# Every registered theme reaches the classes (not only the synthetic one).
	for t in Registry.all():
		var w: StaticBody2D = WallScript.new()
		root.add_child(w)
		w.setup(rect, t)
		_check(w._top == t.wall_top, "%s: wall colour from its theme" % t.id)

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

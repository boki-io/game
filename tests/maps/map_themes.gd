extends SceneTree
## Map themes (spec 0.6 sections 4, 7.4, 10, 12): ids, ranges of every field, ambient near white, the eight differ
## from each other, monsters read against the floor, and each thumbnail's colour is close to its theme.
## Run: godot --headless --path . --script tests/maps/map_themes.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const ThemeScript := preload("res://scripts/maps/map_theme.gd")
const WallScript := preload("res://scripts/cave/cave_wall.gd")
const DecorScript := preload("res://scripts/cave/cave_decor.gd")

const COLOR_FIELDS := [
	"floor_dark", "floor_light", "rock", "rock_dark", "rock_light", "wall_top", "wall_top_light", "wall_side",
	"wall_outline", "pillar", "torch_color", "glow_color", "ambient",
]
const MIN_THEME_DISTANCE := 0.05   # OKLab, between any two maps' rock distance plus floor distance
const MIN_FLOOR_DISTANCE := 0.12   # a monster body against each floor colour of its own map
const MIN_TYPE_DISTANCE := 0.08    # between the three monster types of one map
## Measured with the signature thumbnails (spec 14 step 9): 0.017 (frost) to 0.064 (bone warren, pale bones on a dark
## rock; the template is a copy of mossy_hollow's). 0.07 keeps the margin small, so a changed colour or a thumbnail that was not
## regenerated fails; the old 0.12 let a wrong-hued thumbnail pass.
const MIN_WALL_DISTANCE := 0.10    # a wall's top and a pillar against the plain floor (they were nearly invisible at 0.02)
const MIN_MARK_DISTANCE := 0.30    # a monster's mark against its own body
const THUMB_TOLERANCE := 0.07      # OKLab, thumbnail average against the rock/floor blend

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 20:
			print("FAIL: ", what)


## OKLab (L, a, b) of a colour.
func _oklab(c: Color) -> Vector3:
	var r := c.srgb_to_linear()
	var l := cbrt(0.4122214708 * r.r + 0.5363325363 * r.g + 0.0514459929 * r.b)
	var m := cbrt(0.2119034982 * r.r + 0.6806995451 * r.g + 0.1073969566 * r.b)
	var s := cbrt(0.0883024619 * r.r + 0.2817188376 * r.g + 0.6299787005 * r.b)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


func cbrt(x: float) -> float:
	return pow(x, 1.0 / 3.0)


func _distance(a: Color, b: Color) -> float:
	return _oklab(a).distance_to(_oklab(b))


func _in_unit(c: Color) -> bool:
	return c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0 and c.a == 1.0


func _average(image: Image) -> Color:
	var sum := Vector3.ZERO
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	sum /= float(image.get_width() * image.get_height())
	return Color(sum.x, sum.y, sum.z)


func _check_theme(theme, id: String, is_default: bool) -> void:
	var tag := id + ": "
	_check(String(theme.id) == id, tag + "id equals the folder")
	for field: String in COLOR_FIELDS:
		_check(_in_unit(theme.get(field)), tag + "%s is a valid opaque colour" % field)
	_check(theme.floor_plain.size() == 4, tag + "four plain floor colours")
	for c: Color in theme.floor_plain:
		_check(_in_unit(c), tag + "floor_plain colour valid")
	_check(theme.floor_flecks >= 0.0 and theme.floor_flecks <= 1.0, tag + "floor_flecks in 0..1")
	_check(theme.ambient.r >= 0.8 and theme.ambient.g >= 0.8 and theme.ambient.b >= 0.8, tag + "ambient channels at least 0.8")
	_check(theme.torch_count >= 4 and theme.torch_count <= 12, tag + "torch_count 4..12")
	_check(theme.vignette >= 0.4 and theme.vignette <= 0.8, tag + "vignette 0.4..0.8")
	_check(theme.ambience_kind >= 0 and theme.ambience_kind <= 5, tag + "ambience_kind is one of the six kinds")
	_check(theme.ambience_count >= 0 and theme.ambience_count <= 80, tag + "ambience_count 0..80")
	_check(theme.horizontal_bias >= 0.0 and theme.horizontal_bias <= 1.0, tag + "horizontal_bias 0..1")
	_check(theme.wall_count >= 0 and theme.pillar_count >= 0, tag + "counts are not negative")
	_check(theme.wall_count + theme.pillar_count <= 16, tag + "walls + pillars <= 16 (%d)" % (theme.wall_count + theme.pillar_count))
	_check(theme.decor_count >= 0 and theme.decor_count <= 140, tag + "decor_count <= 140")
	_check(theme.style >= 0 and theme.style <= ThemeScript.Style.CLUSTERS, tag + "style is a known style")
	_check(not theme.wall_lengths.is_empty() or theme.wall_count == 0, tag + "has wall lengths")
	for length: float in theme.wall_lengths:
		_check(WallScript.LENGTHS.has(length), tag + "wall length %s is one of CaveWall.LENGTHS" % length)
	var kinds: int = DecorScript.Kind.size()
	var total := 0.0
	for kind in theme.decor_weights:
		_check(typeof(kind) == TYPE_INT and kind >= 0 and kind < kinds, tag + "decor kind %s exists" % str(kind))
		_check(theme.decor_weights[kind] > 0.0, tag + "decor weight of %s is positive" % str(kind))
		total += float(theme.decor_weights[kind])
	_check(total > 0.0 or theme.decor_count == 0, tag + "decor weights are not empty")
	if is_default:
		return

	# Monsters read against the floor and against each other (7.4).
	var floors: Array[Color] = []
	floors.append_array(theme.floor_plain)
	floors.append(theme.floor_dark)
	floors.append(theme.floor_light)
	for variant in theme.monsters:
		_check(_in_unit(variant.body_color) and _in_unit(variant.outline_color) and _in_unit(variant.eye_color)
			and _in_unit(variant.mark_color), tag + "%s variant colours valid" % variant.enemy_id)
		for fl in floors:
			_check(_distance(variant.body_color, fl) >= MIN_FLOOR_DISTANCE,
				tag + "%s body is too close to a floor colour (%.3f)" % [variant.enemy_id, _distance(variant.body_color, fl)])
	for variant in theme.monsters:
		_check(_distance(variant.mark_color, variant.body_color) >= MIN_MARK_DISTANCE or variant.mark == 0,
			tag + "%s mark is too close to its body (%.3f)" % [variant.enemy_id, _distance(variant.mark_color, variant.body_color)])
	_check(_distance(theme.wall_top, theme.floor_plain[0]) >= MIN_WALL_DISTANCE, tag + "wall top is too close to the floor (%.3f)" % _distance(theme.wall_top, theme.floor_plain[0]))
	_check(_distance(theme.pillar, theme.floor_plain[0]) >= MIN_WALL_DISTANCE, tag + "pillar is too close to the floor (%.3f)" % _distance(theme.pillar, theme.floor_plain[0]))
	for a in theme.monsters.size():
		for b in range(a + 1, theme.monsters.size()):
			var d := _distance(theme.monsters[a].body_color, theme.monsters[b].body_color)
			_check(d >= MIN_TYPE_DISTANCE, tag + "%s and %s look too alike (%.3f)" % [theme.monsters[a].enemy_id, theme.monsters[b].enemy_id, d])

	# The thumbnail's average colour against the rock/floor blend (section 10).
	var avg := _average(theme.thumbnail.get_image())
	var blend: Color = theme.rock.lerp(theme.floor_plain[0], 0.5)
	var d := _distance(avg, blend)
	_check(d <= THUMB_TOLERANCE, tag + "thumbnail average is far from the theme (%.3f)" % d)


func _init() -> void:
	await process_frame
	var themes: Array = Registry.all()
	var ids := {}
	var names := {}
	for theme in themes:
		_check_theme(theme, String(theme.id), false)
		_check(not ids.has(theme.id), "id %s is unique" % theme.id)
		_check(not names.has(theme.display_name), "name %s is unique" % theme.display_name)
		ids[theme.id] = true
		names[theme.display_name] = true
	_check_theme(Registry.default(), "_default", true)
	_check(Registry.by_id(&"_template") == null, "the template is not playable")
	_check_theme(load("res://content/maps/_template/map.tres"), "_template", false)

	# The eight differ from each other: rock, floor, and (style, wall_count) or decor weights.
	for a in themes.size():
		for b in range(a + 1, themes.size()):
			var x = themes[a]
			var y = themes[b]
			var pair := "%s / %s: " % [x.id, y.id]
			# The rock and floor colours are the thumbnails' (spec 10), and some thumbnails share a dark rock, so the
			# two distances count together (see AGENT_DECISION_LOG.md).
			var palette := _distance(x.rock, y.rock) + _distance(x.floor_plain[0], y.floor_plain[0])
			_check(palette >= MIN_THEME_DISTANCE, pair + "rock and floor colours too close (%.3f)" % palette)
			_check(x.style != y.style or x.wall_count != y.wall_count or x.decor_weights != y.decor_weights,
				pair + "same (style, wall_count) and decor weights")

	# The default theme is today's cave (values from the old consts).
	var d = Registry.default()
	_check(d.floor_plain[0].is_equal_approx(Color("5b4632")) and d.rock.is_equal_approx(Color("3a322b"))
		and d.pillar.is_equal_approx(Color("5c5248")) and d.floor_dark.is_equal_approx(Color("4a3828")), "default keeps today's colours")
	_check(d.wall_count == 6 and d.pillar_count == 8 and d.decor_count == 110 and d.torch_count == 12, "default keeps today's counts")
	_check(is_equal_approx(d.vignette, 0.62) and d.ambient == Color.WHITE, "default keeps today's vignette and ambient")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## The drawn grunt slimes: every map's grunt variant carries SpriteFrames (bounce 4 frames looping, hit 4 and death 5,
## one shots, with the durations drawn in Aseprite), the other types stay procedural, and an Enemy with frames
## shows an AnimatedSprite2D that bounces on activation, plays hit when damaged and then bounces again, faces
## its target, and dies as an independent Effects animation while the pooled node deactivates at once. A variant
## without frames behaves as before. Also checks that tools/slimes/build_slimes.py reproduces the committed sheets.
## Run: godot --headless --path . --script tests/maps/slime_sprites.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const VariantScript := preload("res://scripts/maps/monster_variant.gd")
const ROOT := "res://content/maps/"
const FRAME_MS := {&"bounce": [120, 120, 120, 120], &"hit": [70, 90, 110, 200], &"death": [120, 120, 140, 160, 600]}
const LOOPS := {&"bounce": true, &"hit": false, &"death": false}

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 20:
			print("FAIL: ", what)


func _run_with(theme: Variant) -> Node:
	var stage := StageData.new()
	stage.theme = theme
	root.get_node("GameSession").current_stage = stage
	var F: GDScript = load("res://tests/fixture.gd")
	return F.start_run(self, &"knight")


func _end_run(main: Node) -> void:
	main.queue_free()
	root.get_node("GameSession").current_stage = null
	paused = false
	await process_frame


## The live corpse animations of the run's Effects node.
func _corpses(fx: Node) -> Array:
	return fx.get_children().filter(func(c: Node) -> bool:
		return c is AnimatedSprite2D and c.visible and c.animation == &"death")


func _check_frames(tag: String, frames: SpriteFrames, folder: String) -> void:
	_check(frames != null, tag + "has sprite_frames")
	if frames == null:
		return
	var names := Array(frames.get_animation_names())
	names.sort()
	_check(names == ["bounce", "death", "hit"], tag + "animations %s" % [names])
	for anim: StringName in FRAME_MS:
		var ms: Array = FRAME_MS[anim]
		_check(frames.get_frame_count(anim) == ms.size(), tag + "%s has %d frames" % [anim, ms.size()])
		_check(frames.get_animation_loop(anim) == LOOPS[anim], tag + "%s loop is %s" % [anim, LOOPS[anim]])
		for i in frames.get_frame_count(anim):
			var real_ms := frames.get_frame_duration(anim, i) / frames.get_animation_speed(anim) * 1000.0
			_check(absf(real_ms - float(ms[i])) < 0.5, tag + "%s frame %d lasts %.0f ms, expected %d" % [anim, i, real_ms, ms[i]])
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			_check(tex != null and tex.region.size == Vector2(32, 32), tag + "%s frame %d is a 32x32 atlas region" % [anim, i])
			if tex != null:
				_check(tex.atlas.resource_path == folder + "monsters/grunt_sheet.png", tag + "frames use the map's own sheet")
				_check(Vector2i(tex.atlas.get_size()) == Vector2i(416, 32), tag + "sheet is 13 frames of 32x32")
	# The feet stand on row 29 in every frame but 2, the leap of the bounce (rows 5 to 24, in the air).
	var sheet := (frames.get_frame_texture(&"bounce", 0) as AtlasTexture).atlas.get_image()
	for f in 13:
		var bottom := -1
		for y in 32:
			for x in 32:
				if sheet.get_pixel(f * 32 + x, y).a > 0.0:
					bottom = maxi(bottom, y)
		_check(bottom == (24 if f == 2 else 29), tag + "frame %d ends on row %d" % [f, bottom])


func _init() -> void:
	await process_frame
	await process_frame
	var grunt: EnemyData = load("res://content/enemies/grunt.tres")
	var ranged: EnemyData = load("res://content/enemies/ranged.tres")
	var dasher: EnemyData = load("res://content/enemies/dasher.tres")

	# --- Resources: every map, and the default cave ---
	var themes: Array = Registry.all()
	themes.append(Registry.default())
	for theme in themes:
		var folder := ROOT + String(theme.id) + "/"
		var tag := "%s: " % theme.id
		var v = theme.variant_for(&"grunt")
		_check(v != null, tag + "grunt variant")
		if v != null:
			_check_frames(tag, v.sprite_frames, folder)
		for other in [&"ranged", &"dasher"]:
			var ov = theme.variant_for(other)
			_check(ov == null or ov.sprite_frames == null, tag + "%s stays procedural" % other)
	var template = load(ROOT + "_template/monsters/grunt.tres")
	_check(template.sprite_frames == null, "_template: no frames, a new map starts with the drawn grunt")

	# --- An enemy with frames (the default cave dresses it when no stage is set) ---
	var main := await _run_with(null)
	var fx: Node = main.get_tree().get_first_node_in_group(&"effects")
	var e: Node = main.spawn_director._acquire(grunt)
	var anim: AnimatedSprite2D = e._anim
	_check(anim != null, "a grunt with frames has an AnimatedSprite2D")
	_check(anim.get_parent() == e.sprite and e.sprite.get_child_count() == 1, "it is the placeholder's only child")
	_check(not e.sprite.body_visible, "the placeholder body is hidden (the shadow stays)")
	_check(anim.centered == false and anim.offset == Vector2(-16, -30), "feet at the origin: bottom centre of the frame")
	e.apply_variant(Registry.default().variant_for(&"grunt"))
	_check(e.sprite.get_child_count() == 1 and e._anim == anim, "applying a variant again reuses the sprite")
	e.facing = Vector2.LEFT
	e.activate(Vector2(400, 300), 1.0)
	_check(anim.animation == &"bounce" and anim.is_playing(), "activate plays bounce")
	_check(not anim.flip_h, "facing left shows the art as drawn")
	e.facing = Vector2.RIGHT
	e.activate(Vector2(400, 300), 1.0)
	_check(anim.flip_h, "facing right flips it")
	_check(e.hitbox.get_child(0).shape.radius == grunt.hitbox_radius, "the hitbox is the type's")

	e.take_damage(1.0)
	_check(anim.animation == &"hit" and anim.is_playing(), "damage plays hit")
	_check(not e.sprite.flash and e._flash_left == 0.0, "the white flash is replaced by the hit animation")
	await create_timer(0.9).timeout  # the hit lasts 470 ms
	_check(anim.animation == &"bounce" and anim.is_playing(), "after the hit it bounces again")
	e.take_damage(1.0)
	_check(anim.animation == &"hit", "hit again")
	e.activate(Vector2(400, 300), 1.0)  # recycled in mid-hit
	_check(anim.animation == &"bounce" and anim.is_playing(), "activate resets a half-played hit")
	_check(e.health.current == grunt.max_health, "activate refills the health")

	# Death: an independent effect at the death position; the pooled node is off at once.
	var pos := Vector2(420, 310)
	e.global_position = pos
	e.facing = Vector2.RIGHT
	e.apply_variant(Registry.default().variant_for(&"grunt"))
	fx._fx.clear()
	_check(_corpses(fx).is_empty(), "no corpse before")
	e.health.take_damage(1.0e9)
	_check(not e.active and not e.visible, "the enemy is deactivated at once")
	var corpses := _corpses(fx)
	_check(corpses.size() == 1, "one death animation is playing")
	if corpses.size() == 1:
		var c: AnimatedSprite2D = corpses[0]
		_check(c.position == pos and c.offset == Vector2(-16, -30) and not c.centered, "it stands where the enemy died, feet on the spot")
		_check(c.flip_h == anim.flip_h, "it keeps the enemy's facing")
		_check(c.get_parent() == fx and c.get_parent() != e, "it belongs to Effects, not to the pooled enemy")
		_check(fx._fx.filter(func(f: Dictionary) -> bool: return f.kind == &"puff").is_empty(), "no colour puff beside it")
	_check(anim.animation == &"bounce" or anim.animation == &"hit", "the enemy's own sprite does not play death")
	await create_timer(1.7).timeout  # 1140 ms of frames
	_check(_corpses(fx).is_empty(), "the puddle is recycled when it ends")
	var pooled := fx.get_child_count()
	# Reuse: a recycled enemy starts clean and killing it again reuses the pooled sprite.
	var e2: Node = main.spawn_director._acquire(grunt)
	_check(e2 == e, "the pool hands the enemy back")
	e2.activate(Vector2(300, 300), 1.0)
	_check(e2.active and e2._anim.animation == &"bounce", "reused enemy bounces")
	e2.health.take_damage(1.0e9)
	_check(_corpses(fx).size() == 1 and fx.get_child_count() == pooled, "a second death reuses the pooled sprite")
	await create_timer(1.7).timeout

	# Many deaths at once are capped.
	var crowd: Array = []
	for i in 80:
		var g: Node = main.spawn_director._acquire(grunt)
		g.activate(Vector2(200 + i * 4, 200), 1.0)
		crowd.append(g)
	for g in crowd:
		g.health.take_damage(1.0e9)
	_check(_corpses(fx).size() == fx.MAX_CORPSES, "at most %d death animations at once (%d)" % [fx.MAX_CORPSES, _corpses(fx).size()])
	await create_timer(1.7).timeout
	_check(_corpses(fx).is_empty(), "all recycled afterwards")
	for g in crowd:
		_check(not g.active, "crowd member deactivated")

	# The other types are untouched by the cave.
	var r: Node = main.spawn_director._acquire(ranged)
	var d: Node = main.spawn_director._acquire(dasher)
	_check(d._anim != null and not d.sprite.body_visible, "the dasher shows its own art (tests/enemy_charger.gd)")
	_check(r._anim != null and not r.sprite.body_visible, "the ranged enemy shows its own art (tests/enemy_demon_head.gd)")
	await _end_run(main)

	# --- A variant without frames: exactly today's behaviour ---
	var bare_variant: Resource = VariantScript.new()
	bare_variant.enemy_id = &"grunt"
	bare_variant.body_color = Color(0.1, 0.8, 0.3)
	var bare: MapTheme = Registry.all()[0].duplicate()
	bare.monsters = Array([bare_variant], TYPE_OBJECT, &"Resource", VariantScript)
	main = await _run_with(bare)
	fx = main.get_tree().get_first_node_in_group(&"effects")
	var p: Node = main.spawn_director._acquire(grunt)
	_check(p._anim == null and p.sprite.body_visible and p.sprite.get_child_count() == 0, "no frames: the drawn body")
	_check(p.sprite.body_color == bare_variant.body_color, "no frames: the variant's colour")
	p.activate(Vector2(400, 300), 1.0)
	p.take_damage(1.0)
	_check(p.sprite.flash and p._flash_left > 0.0, "no frames: the white flash")
	fx._fx.clear()
	p.health.take_damage(1.0e9)
	_check(fx._fx.filter(func(f: Dictionary) -> bool: return f.kind == &"puff").size() == 1 and _corpses(fx).is_empty(),
		"no frames: the colour puff")
	# Frames can be removed again (a reloaded map in the preview): the body comes back.
	var q: Node = main.spawn_director._acquire(grunt)
	q.apply_variant(Registry.default().variant_for(&"grunt"))
	_check(q._anim != null and not q.sprite.body_visible, "frames applied")
	q.apply_variant(bare_variant)
	await process_frame
	_check(q._anim == null and q.sprite.body_visible, "a variant without frames brings the drawn body back")
	await _end_run(main)

	# --- The tools script regenerates the committed sheets and frames ---
	var out: Array = []
	var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/slimes/build_slimes.py"), "--check"], out, true)
	if code == -1:
		print("note: python3 not found, build_slimes.py --check skipped")
	else:
		_check(code == 0, "build_slimes.py --check: committed sheets and frames match the sources (%s)" % [out])

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

extends SceneTree
## The Ranged enemy's drawn art, the demon head (content/enemies/ranged/): the SpriteFrames from the Aseprite export
## (five animations, 64x64 regions, the drawn durations, loops), the EnemyData art fields, and the Enemy playing it:
## idle when it stands, walk when the brain moves it, attack from the wind-up of a shot (and ending when the wind-up is
## cancelled), hurt on damage, a scaled death corpse, flipping towards the target, and a map variant without frames
## keeping the type's art.
## Run: godot --headless --path . --script tests/enemy_demon_head.gd

const FRAMES := "res://content/enemies/ranged/frames.tres"
const SHEET := "res://content/enemies/ranged/demon_head_sheet.png"
## animation -> [frame count, first frame on the sheet, loops, drawn frame times in ms]
const ANIMS := {
	&"walk": [8, 0, true, [120, 120, 120, 120, 120, 120, 120, 120]],
	&"attack": [7, 8, false, [100, 90, 90, 110, 80, 90, 120]],
	&"idle": [6, 15, true, [180, 180, 180, 180, 180, 180]],
	&"hurt": [4, 21, false, [60, 80, 100, 120]],
	&"death": [6, 25, false, [70, 90, 100, 110, 130, 600]],
}

var _failed := false
var _F: GDScript


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	_F = load("res://tests/fixture.gd")
	_resources()
	await _behaviour()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _resources() -> void:
	var frames: SpriteFrames = load(FRAMES)
	var names := Array(frames.get_animation_names())
	names.sort()
	_check(names == ["attack", "death", "hurt", "idle", "walk"], "animations %s" % [names])
	var sheet: Texture2D = load(SHEET)
	_check(sheet.get_width() == 31 * 64 and sheet.get_height() == 64, "the sheet is 31 frames of 64x64")
	for anim in ANIMS:
		var spec: Array = ANIMS[anim]
		_check(frames.get_frame_count(anim) == spec[0], "%s has %d frames" % [anim, spec[0]])
		_check(frames.get_animation_loop(anim) == spec[2], "%s loop flag" % anim)
		_check(is_equal_approx(frames.get_animation_speed(anim), 10.0), "%s runs at 10 fps" % anim)
		for i in spec[0]:
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			_check(tex != null and tex.atlas.resource_path == SHEET and tex.region == Rect2((spec[1] + i) * 64, 0, 64, 64),
				"%s frame %d is sheet frame %d" % [anim, i, spec[1] + i])
			_check(is_equal_approx(frames.get_frame_duration(anim, i), spec[3][i] / 100.0), "%s frame %d lasts %d ms" % [anim, i, spec[3][i]])
	var ranged: EnemyData = load("res://content/enemies/ranged.tres")
	_check(ranged.sprite_frames == frames, "ranged.tres names the frames")
	_check(is_equal_approx(ranged.art_scale, 0.55) and ranged.art_offset == Vector2(-30, -66) and not ranged.art_faces_left, "ranged art scale, offset, facing")
	for id in ["grunt", "dasher", "training_dummy"]:
		_check((load("res://content/enemies/%s.tres" % id) as EnemyData).sprite_frames == null, "%s has no art of its own" % id)
	_check(ranged.windup_time == 0.4, "the 0.4 s wind-up still lands on the attack's glow (frame 4 starts at 0.39 s)")


func _behaviour() -> void:
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	var p = _F.player()
	p.caster.set_physics_process(false)
	var fx: Node = main.get_tree().get_first_node_in_group(&"effects")

	# A far enemy walks, a near one stands and idles.
	var far = _F.spawn_enemy(main, "ranged", p.global_position + Vector2(400, 0), 1.0, false)
	await _F.frames(self, 3)
	_check(far._anim != null and not far.sprite.body_visible, "the ranged enemy shows the art, not the drawn body")
	_check(far._anim.offset == Vector2(-30, -66) and far._anim.scale == Vector2(0.55, 0.55) and not far._anim.centered, "offset, scale, top-left origin")
	_check(far._anim.animation == &"walk", "it walks while the brain approaches (%s)" % far._anim.animation)
	_check(far.sprite.get_child_count() == 1, "the art is the placeholder's only child")
	far.deactivate()

	var e = _F.spawn_enemy(main, "ranged", p.global_position + Vector2(100, 0), 1.0, false)
	e.facing = Vector2.LEFT
	await _F.seconds(self, 0.3)
	_check(e.brain._state == 1 and e._anim.animation == &"idle", "within range it holds and idles (%s)" % e._anim.animation)
	_check(e._anim.flip_h == (e.facing.x < 0.0), "flip follows facing (art looks right): flip %s facing %s" % [e._anim.flip_h, e.facing])

	# The wind-up of a shot plays the attack; it ends back in the idle loop.
	e.brain._shot_cd = 0.0
	e.brain._windup_left = -1.0
	await _F.frames(self, 2)
	_check(e.brain._windup_left >= 0.0 and e._anim.animation == &"attack" and e._one_shot, "wind-up plays attack (%s)" % e._anim.animation)
	await _F.seconds(self, 0.45)
	_check(e._anim.animation == &"attack" and e._anim.frame >= 3, "the shot leaves while the attack is at its glow (frame %d)" % e._anim.frame)
	await _F.seconds(self, 0.6)
	_check(e._anim.animation == &"idle" and not e._one_shot, "after the attack it idles again (%s)" % e._anim.animation)

	# A stun during the wind-up ends the attack animation.
	e.brain._shot_cd = 0.0
	await _F.frames(self, 2)
	_check(e._anim.animation == &"attack", "a second attack starts")
	e.stun(0.2)
	_check(e._anim.animation == &"idle" and not e._one_shot, "stun cancels the attack animation")
	await _F.seconds(self, 0.3)

	# Damage plays hurt, then back to the loop.
	e.take_damage(1.0)
	_check(e._anim.animation == &"hurt" and e._one_shot, "a hit plays hurt")
	await _F.seconds(self, 0.5)
	_check(e._anim.animation != &"hurt" and not e._one_shot, "hurt hands back to the loop (%s)" % e._anim.animation)

	# A map variant without frames keeps the type's art.
	var variant = load("res://content/maps/bone_warren/monsters/ranged.tres")
	e.apply_variant(variant)
	_check(variant.sprite_frames == null and e._anim != null and not e.sprite.body_visible, "a variant without frames keeps the demon head")

	# Death: a scaled corpse of its own (the director deactivates the node; the fixture has none).
	var count_before: int = fx._corpses
	var pos: Vector2 = e.global_position
	e.take_damage(1e9)
	_check(fx._corpses == count_before + 1, "death starts one corpse animation (%d -> %d)" % [count_before, fx._corpses])
	var corpse: AnimatedSprite2D = null
	for c in fx.get_children():
		if c is AnimatedSprite2D and c.has_meta(&"corpse") and c.visible:
			corpse = c
	_check(corpse != null and corpse.animation == &"death" and corpse.scale == Vector2(0.55, 0.55) and corpse.offset == Vector2(-30, -66)
		and corpse.position == pos, "the corpse plays death at the demon's scale and place")
	await _F.seconds(self, 2.0)
	_check(fx._corpses == count_before, "the corpse is recycled afterwards")

	# Activating a reused enemy starts clean.
	var again = _F.spawn_enemy(main, "ranged", p.global_position + Vector2(400, 0), 1.0, true)
	await _F.frames(self, 2)
	_check(again._anim.animation == &"idle" and not again._one_shot, "a fresh enemy idles")
	main.queue_free()
	paused = false

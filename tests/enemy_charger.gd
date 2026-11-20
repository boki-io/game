extends SceneTree
## The Dasher's drawn art, the charger (content/enemies/charger/): the SpriteFrames from the Aseprite export (idle, walk,
## windup, dash, hurt, death; 64x64 regions, the drawn durations, loops), the EnemyData art fields, and the Enemy playing
## it: idle and walk with its movement, the windup pose fitted to aim plus lock and held, the dash fitted to its travel
## time, recovery and stun ending them, hurt on damage, a scaled death corpse, and flipping towards the target.
## Run: godot --headless --path . --script tests/enemy_charger.gd

const FRAMES := "res://content/enemies/charger/frames.tres"
const SHEET := "res://content/enemies/charger/charger_sheet.png"
## animation -> [frame count, first frame on the sheet, loops, drawn frame times in ms]
const ANIMS := {
	&"idle": [4, 0, true, [250, 250, 250, 250]],
	&"walk": [6, 4, true, [250, 250, 250, 250, 250, 250]],
	&"windup": [6, 10, false, [200, 350, 200, 300, 250, 300]],
	&"dash": [7, 16, false, [120, 80, 100, 80, 200, 150, 150]],
	&"hurt": [4, 23, false, [80, 80, 80, 120]],
	&"death": [7, 27, false, [100, 120, 150, 180, 200, 250, 600]],
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
	_check(names == ["dash", "death", "hurt", "idle", "walk", "windup"], "animations %s" % [names])
	var sheet: Texture2D = load(SHEET)
	_check(sheet.get_width() == 34 * 64 and sheet.get_height() == 64, "the sheet is 34 frames of 64x64")
	for anim in ANIMS:
		var spec: Array = ANIMS[anim]
		_check(frames.get_frame_count(anim) == spec[0], "%s has %d frames" % [anim, spec[0]])
		_check(frames.get_animation_loop(anim) == spec[2], "%s loop flag" % anim)
		for i in spec[0]:
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			_check(tex != null and tex.atlas.resource_path == SHEET and tex.region == Rect2((spec[1] + i) * 64, 0, 64, 64),
				"%s frame %d is sheet frame %d" % [anim, i, spec[1] + i])
			_check(is_equal_approx(frames.get_frame_duration(anim, i), spec[3][i] / 100.0), "%s frame %d lasts %d ms" % [anim, i, spec[3][i]])
	var dasher: EnemyData = load("res://content/enemies/dasher.tres")
	_check(dasher.sprite_frames == frames, "dasher.tres names the frames")
	_check(is_equal_approx(dasher.art_scale, 0.91) and dasher.art_offset == Vector2(-32, -62) and not dasher.art_faces_left, "dasher art scale, offset, facing")


func _length(a: AnimatedSprite2D, anim: StringName) -> float:
	var t := 0.0
	for i in a.sprite_frames.get_frame_count(anim):
		t += a.sprite_frames.get_frame_duration(anim, i)
	return t / a.sprite_frames.get_animation_speed(anim)


func _behaviour() -> void:
	var main: Node = _F.start_run(self, &"knight")
	await _F.frames(self, 2)
	var p = _F.player()
	p.caster.set_physics_process(false)
	var fx: Node = main.get_tree().get_first_node_in_group(&"effects")

	var far = _F.spawn_enemy(main, "dasher", p.global_position + Vector2(500, 0), 1.0, false)
	await _F.frames(self, 3)
	_check(far._anim != null and not far.sprite.body_visible, "the dasher shows the art, not the drawn body")
	_check(far._anim.animation == &"walk" and far._anim.scale == Vector2(0.91, 0.91), "it walks towards the player (%s)" % far._anim.animation)
	far.deactivate()

	# Within trigger range with a clear line: the windup pose, fitted to aim + lock and held on its last frame.
	var e = _F.spawn_enemy(main, "dasher", p.global_position + Vector2(90, 0), 1.0, false)
	await _F.frames(self, 3)
	var d: DasherData = e.data
	_check(e.brain._state == 1 and e._anim.animation == &"windup" and e._held, "aiming plays the windup (%s)" % e._anim.animation)
	_check(is_equal_approx(_length(e._anim, &"windup") / e._anim.speed_scale, d.aim_time + d.lock_time), "the windup is fitted to aim + lock")
	_check(e._anim.flip_h == (e.facing.x < 0.0), "flip follows facing (the art looks right)")
	await _F.seconds(self, d.aim_time + d.lock_time - 0.15)
	_check(e.brain._state == 2 and e._anim.animation == &"windup" and e._anim.frame >= 4, "in the lock it is still in the windup (frame %d)" % e._anim.frame)

	# The dash: the lunge fitted to its travel time.
	await _F.seconds(self, 0.25)
	_check(e.brain._state == 3 and e._anim.animation == &"dash", "dashing plays the dash (%s, state %d)" % [e._anim.animation, e.brain._state])
	_check(is_equal_approx(_length(e._anim, &"dash") / e._anim.speed_scale, d.dash_distance / d.dash_speed), "the dash animation is fitted to its travel time (%.2f s)" % (_length(e._anim, &"dash") / e._anim.speed_scale))
	await _F.seconds(self, 0.7)
	_check(e.brain._state == 4 and e._anim.animation != &"dash" and not e._one_shot and is_equal_approx(e._anim.speed_scale, 1.0), "recovery ends the attack animation (%s)" % e._anim.animation)

	# A stun during the aim ends it.
	await _F.seconds(self, d.recovery_time)
	await _F.seconds(self, 0.2)
	if e.brain._state == 1:
		e.stun(0.2)
		_check(e._anim.animation != &"windup" and not e._one_shot, "stun cancels the windup")
	await _F.seconds(self, 0.3)

	# Damage plays hurt, then back to the loop.
	e.take_damage(1.0)
	_check(e._anim.animation == &"hurt" and e._one_shot, "a hit plays hurt")
	await _F.seconds(self, 0.6)
	_check(e._anim.animation != &"hurt" and not e._one_shot, "hurt hands back to the loop (%s)" % e._anim.animation)

	# Death: a scaled corpse of its own.
	var count_before: int = fx._corpses
	var pos: Vector2 = e.global_position
	e.take_damage(1e9)
	_check(fx._corpses == count_before + 1, "death starts one corpse animation (%d -> %d)" % [count_before, fx._corpses])
	var corpse: AnimatedSprite2D = null
	for c in fx.get_children():
		if c is AnimatedSprite2D and c.has_meta(&"corpse") and c.visible:
			corpse = c
	_check(corpse != null and corpse.animation == &"death" and corpse.scale == Vector2(0.91, 0.91) and corpse.offset == Vector2(-32, -62)
		and corpse.position == pos, "the corpse plays death at the charger's scale and place")
	await _F.seconds(self, 2.5)
	_check(fx._corpses == count_before, "the corpse is recycled afterwards")
	main.queue_free()
	paused = false

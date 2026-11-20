extends SceneTree
## The Wizard's drawn animations: the SpriteFrames carry all nine (frame counts, the durations drawn in Aseprite,
## loops), and the Player plays the right one: Arcane Bolt alternates attack1 and attack2, Chain Lightning and
## Meteor Strike play their own, Phase Shift plays nothing on the cast but loops "phase" while the ghost runs,
## a hit plays hurt, and a killing hit plays death (hurt must not replace it).
## Run: godot --headless --path . --script tests/wizard_animations.gd

const FRAME_MS := {
	&"idle": [220, 220, 220, 220],
	&"walk": [140, 140, 140, 140],
	&"attack1": [160, 60, 90, 100, 120],
	&"attack2": [160, 60, 90, 100, 120],
	&"lightning": [160, 60, 90, 100, 120],
	&"meteor": [160, 60, 90, 100, 120],
	&"phase": [100, 100, 100, 100],
	&"hurt": [60, 80, 100, 120],
	&"death": [70, 90, 100, 110, 130, 600],
}
const LOOPS := [&"idle", &"walk", &"phase"]

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")

	# The data: the character carries its frames, every animation is there with the drawn timing.
	var frames: SpriteFrames = load("res://content/characters/wizard/frames.tres")
	var names := Array(frames.get_animation_names()).map(func(n: Variant) -> String: return String(n))
	names.sort()
	var expected := FRAME_MS.keys().map(func(n: Variant) -> String: return String(n))
	expected.sort()
	_check(names == expected, "animations %s, expected %s" % [names, expected])
	for anim: StringName in FRAME_MS:
		var ms: Array = FRAME_MS[anim]
		_check(frames.get_frame_count(anim) == ms.size(), "%s has %d frames" % [anim, ms.size()])
		_check(frames.get_animation_loop(anim) == LOOPS.has(anim), "%s loop flag in the resource" % anim)
		for i in frames.get_frame_count(anim):
			var real_ms := frames.get_frame_duration(anim, i) / frames.get_animation_speed(anim) * 1000.0
			_check(absf(real_ms - float(ms[i])) < 0.5, "%s frame %d lasts %.0f ms, expected %d" % [anim, i, real_ms, ms[i]])
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			_check(tex != null and tex.region.size == Vector2(64, 64), "%s frame %d is a 64x64 atlas region" % [anim, i])
			if tex != null:
				_check(Vector2i(tex.atlas.get_size()) == Vector2i(64 * ms.size(), 64), "%s strip is %d frames of 64x64" % [anim, ms.size()])
	var wizard: CharacterData = load("res://content/characters/wizard/character.tres")
	_check(wizard.sprite_frames == frames, "the Wizard uses wizard_frames.tres")

	# In a run.
	var main: Node = F.start_run(self, &"wizard")
	await F.frames(self, 3)
	var p = F.player()
	_check(p._anim != null, "the Player shows an AnimatedSprite2D")
	if p._anim == null:
		print("FAIL")
		quit(1)
		return
	_check(p._anim.animation == &"idle", "idle at the start, got %s" % p._anim.animation)
	for anim: StringName in FRAME_MS:
		_check(p._anim.sprite_frames.get_animation_loop(anim) == LOOPS.has(anim), "%s loops: %s" % [anim, LOOPS.has(anim)])

	# Arcane Bolt fires by itself at an enemy in range: attack1 and attack2 alternate.
	var seen: Array = []
	p.caster.cast_started.connect(func(_slot: StringName, data: Variant) -> void:
		if data.id == &"bolt":
			seen.append(p._anim.animation))
	var target = F.spawn_enemy(main, "grunt", p.global_position + Vector2(80, 0), 100.0, true)
	await F.seconds(self, 3.2)
	_check(seen.size() >= 3, "the bolt fired %d times in 3.2 s" % seen.size())
	for i in seen.size():
		_check(seen[i] == (&"attack1" if i % 2 == 0 else &"attack2"), "bolt cast %d played %s" % [i, seen[i]])
	target.queue_free()
	await F.frames(self, 2)
	await F.seconds(self, 0.5)  # any attack animation has finished

	# Chain Lightning and Meteor Strike play their own animations, then the Player goes back to idle.
	var victim = F.spawn_enemy(main, "grunt", p.global_position + Vector2(60, 0), 100.0, true)
	await F.frames(self, 2)  # the enemy grid is rebuilt once per physics frame
	F.cast(p, &"e")
	await F.frames(self, 2)
	_check(p._anim.animation == &"lightning" and p._anim_busy, "Chain Lightning plays lightning, got %s" % p._anim.animation)
	await F.seconds(self, 0.5)
	_check(not p._anim_busy and p._anim.animation == &"idle", "back to idle after lightning, got %s" % p._anim.animation)
	victim.queue_free()
	await F.frames(self, 2)
	F.cast(p, &"r")
	await F.frames(self, 2)
	_check(p._anim.animation == &"meteor" and p._anim_busy, "Meteor Strike plays meteor, got %s" % p._anim.animation)
	await F.seconds(self, 0.5)
	_check(not p._anim_busy, "meteor finished")

	# Phase Shift: nothing on the cast, the phase loop while moving through the ghost state, back to walk after.
	await F.seconds(self, 1.0)
	F.cast(p, &"q")
	await F.frames(self, 3)
	_check(p.phase_left > 0.0, "phased")
	_check(not p._anim_busy and p._anim.animation == &"idle", "Phase Shift plays no cast animation, got %s" % p._anim.animation)
	p.player_input.set_physics_process(false)  # it would reset move_vector to the (empty) device input every frame
	p.player_input.move_vector = Vector2.RIGHT
	await F.frames(self, 3)
	_check(p._anim.animation == &"phase" and p._anim.is_playing(), "phase loops while moving phased, got %s" % p._anim.animation)
	await F.seconds(self, p.caster.ability_q.duration + 0.3)
	_check(p.phase_left <= 0.0, "phase wore off")
	_check(p._anim.animation == &"walk", "walk again after the phase, got %s" % p._anim.animation)
	p.player_input.move_vector = Vector2.ZERO
	await F.seconds(self, 2.5)  # the grace period and the orb belt are over

	# A hit plays hurt and the Player recovers.
	p.hurtbox.receive_hit(5.0)
	await F.frames(self, 2)
	_check(p._anim.animation == &"hurt" and p._anim_busy, "a hit plays hurt, got %s" % p._anim.animation)
	await F.seconds(self, 0.4)
	_check(not p._anim_busy, "hurt finished")
	await F.seconds(self, 2.0)  # grace over

	# A killing hit plays death, not hurt, and stays on its last frame.
	p.hurtbox.receive_hit(9999.0)
	await F.frames(self, 3)
	_check(p.dead, "dead")
	_check(p._anim.animation == &"death", "a killing hit plays death, got %s" % p._anim.animation)
	await F.seconds(self, 1.0)
	_check(p._anim.animation == &"death" and p._anim.frame == 5, "stays on the last death frame, got %s frame %d" % [p._anim.animation, p._anim.frame])

	main.queue_free()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

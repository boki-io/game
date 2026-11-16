extends SceneTree
## The player glow (spec v0.9 section 2): one additive Glow per Player with the character's colour, radius and alpha, behind the
## sprite, dimmed with the sprite's alpha, hidden on death, off at radius 0 and absent without a character; the hub's Player has one.
## Run: godot --headless --path . --script tests/player_glow.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _action(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
		await physics_frame


func _init() -> void:
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	for id in [&"knight", &"wizard"]:
		var main: Node = F.start_run(self, id)
		await F.frames(self, 3)
		var p = F.player()
		var glow = p.get_node_or_null("Glow")
		_check(glow != null, "%s has a Glow" % id)
		if glow == null:
			continue
		var c = p.character
		_check(glow.color == c.glow_color and glow.radius == c.glow_radius and glow.alpha == c.glow_alpha, "%s: the glow uses the character's data" % id)
		_check(glow.show_behind_parent, "%s: the glow draws behind the sprite" % id)
		_check(glow.material is CanvasItemMaterial and glow.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "%s: the glow is additive" % id)
		var circles: Array = glow.circles()
		var radii_ok := circles.size() == 5
		for i in circles.size():
			radii_ok = radii_ok and is_equal_approx(circles[i].x, c.glow_radius * (1.0 - 0.2 * i)) and is_equal_approx(circles[i].y, c.glow_alpha * 0.3)
		_check(radii_ok, "%s: five circles at r, 0.8r, 0.6r, 0.4r and 0.2r" % id)
		_check(p.get_children().filter(func(n): return n.name == &"Glow").size() == 1, "%s: one Glow" % id)
		# It dims with the sprite (the post-dash blink and the Phase ghost) and is back at full strength with it.
		p.sprite.modulate.a = 0.5
		for i in 3:
			await process_frame  # the glow reads the alpha in _process
		_check(is_equal_approx(glow._scale, 0.5), "%s: the glow follows the sprite's alpha, got %s" % [id, glow._scale])
		p.sprite.modulate.a = 1.0
		for i in 3:
			await process_frame
		_check(is_equal_approx(glow._scale, 1.0), "%s: and back to full" % id)
		# It is hidden when the Player dies.
		p.health.take_damage(1e9)
		await F.frames(self, 2)
		_check(p.dead and not glow.visible, "%s: the glow is hidden on death" % id)
		main.queue_free()
		await process_frame

	# A radius of 0 makes none; a Player without a character has none.
	var main2: Node = F.start_run(self, &"knight")
	await F.frames(self, 2)
	var scene: PackedScene = load("res://scenes/player.tscn")
	var off = scene.instantiate()
	off.character = load("res://data/characters/knight.tres").duplicate()
	off.character.glow_radius = 0.0
	main2.get_node("World/Players").add_child(off)
	var bare = scene.instantiate()
	main2.get_node("World/Players").add_child(bare)
	await F.frames(self, 2)
	_check(off.get_node_or_null("Glow") == null, "a glow radius of 0 makes none")
	_check(bare.get_node_or_null("Glow") == null, "a Player without a character has none")
	main2.queue_free()
	await process_frame

	# The hub's Player has one.
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	for i in 90:
		await physics_frame
	hub._focus(1, true)
	for i in 20:
		await physics_frame
	await _action(&"hub_confirm")
	var players = root.get_node("PlayerRegistry").players
	_check(players.size() == 1 and players[0].get_node_or_null("Glow") != null, "the hub's Player has a Glow")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

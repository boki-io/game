extends SceneTree
## Ambient life (spec v0.9 section 3): MapLook.apply_ambience creates, updates and removes the Ambience; the motes stay inside the
## visible area; the same seed gives the same motes; each kind moves as its row says; alpha is 0 at birth and death; ambience is
## separate from the Effects bits; the ten map files carry the table of 3.1; a run and the hub have one.
## Run: godot --headless --path . --script tests/ambience.gd

const ThemeScript := preload("res://scripts/maps/map_theme.gd")
const LookScript := preload("res://scripts/maps/map_look.gd")
const AmbienceScript := preload("res://scripts/systems/ambience.gd")

# id -> [kind, colour, count]  (spec 3.1; kinds: 1 DUST, 2 EMBERS, 3 SPORES, 4 FROST, 5 GLINT)
const TABLE := {
	"ember_depths": [2, Color(1.0, 0.58, 0.2), 48], "sulfur_pits": [2, Color(0.85, 0.9, 0.3), 40],
	"spore_cavern": [3, Color(0.55, 0.9, 0.5), 48], "mossy_hollow": [3, Color(0.85, 0.95, 0.55), 32],
	"frostbite_grotto": [4, Color(0.8, 0.92, 1.0), 56], "crystal_vault": [5, Color(0.7, 0.85, 1.0), 24],
	"flooded_gallery": [1, Color(0.7, 0.8, 0.85), 40], "bone_warren": [1, Color(0.85, 0.82, 0.72), 40],
	"_default": [1, Color(0.8, 0.75, 0.65), 40], "_template": [1, Color(0.8, 0.75, 0.65), 40],
}

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _theme(kind: int, count: int):
	var t = ThemeScript.new()
	t.ambience_kind = kind
	t.ambience_count = count
	t.ambience_color = Color(0.9, 0.5, 0.2, 1.0)
	return t


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2]


func _init() -> void:
	await process_frame
	var world := Node2D.new()
	root.add_child(world)

	# Create, update and remove.
	for kind in [1, 2, 3, 4, 5]:
		var node = LookScript.apply_ambience(world, _theme(kind, 30), 1)
		_check(node != null and node.motes().size() == 30 and node.kind == kind, "kind %d: 30 motes" % kind)
	_check(world.get_children().filter(func(n): return n is AmbienceScript).size() == 1, "one Ambience, updated in place")
	_check(LookScript.apply_ambience(world, _theme(0, 30), 1) == null and world.get_node_or_null("Ambience") == null, "kind NONE removes it")
	LookScript.apply_ambience(world, _theme(1, 30), 1)
	_check(LookScript.apply_ambience(world, _theme(1, 0), 1) == null and world.get_node_or_null("Ambience") == null, "a count of 0 removes it")
	var plain = LookScript.apply_ambience(world, null, 1)
	_check(plain != null and plain.motes().size() == 40 and plain.kind == 1 and plain.color == Color(0.8, 0.75, 0.65), "a null theme gives 40 warm dust motes")
	world.remove_child(plain)
	plain.free()

	# The same seed gives the same motes, a different seed a different set.
	var w1 := Node2D.new()
	var w2 := Node2D.new()
	var w3 := Node2D.new()
	for w in [w1, w2, w3]:
		root.add_child(w)
	var a = LookScript.apply_ambience(w1, _theme(3, 20), 5)
	var b = LookScript.apply_ambience(w2, _theme(3, 20), 5)
	var c = LookScript.apply_ambience(w3, _theme(3, 20), 6)
	await _frames(2)
	var same := true
	var differs := false
	for i in 20:
		same = same and a.motes()[i].pos.is_equal_approx(b.motes()[i].pos)
		differs = differs or not a.motes()[i].pos.is_equal_approx(c.motes()[i].pos)
	_check(same, "the same seed gives the same motes")
	_check(differs, "a different seed gives different motes")
	for w in [w1, w2, w3]:
		w.queue_free()

	# Every mote stays inside the visible area (grown by the margin) and the count never changes, for every kind.
	for kind in [1, 2, 3, 4, 5]:
		var host := Node2D.new()
		root.add_child(host)
		var node = LookScript.apply_ambience(host, _theme(kind, 40), 9)
		await _frames(600)
		var rect: Rect2 = node.visible_rect()
		var inside := true
		for m in node.motes():
			inside = inside and rect.has_point(m.pos)
		_check(inside and node.motes().size() == 40, "kind %d: 40 motes, all inside the visible area after 600 frames" % kind)
		host.queue_free()

	# Each kind moves as its row says (median over the motes, over about 0.3 s).
	var wanted := {1: "right", 2: "up", 3: "any", 4: "down", 5: "still"}
	for kind in [1, 2, 4, 5]:
		var host := Node2D.new()
		root.add_child(host)
		var node = LookScript.apply_ambience(host, _theme(kind, 40), 3)
		await _frames(30)
		var before: Array = node.motes().map(func(m): return m.pos)
		await _frames(18)
		var dxs: Array = []
		var dys: Array = []
		for i in 40:
			var d: Vector2 = node.motes()[i].pos - before[i]
			if d.length() < 12.0:  # not a respawn
				dxs.append(d.x)
				dys.append(d.y)
		var mx := _median(dxs)
		var my := _median(dys)
		match wanted[kind]:
			"right":
				_check(mx > 0.5, "DUST drifts sideways, median dx %s" % mx)
			"up":
				_check(my < -1.5, "EMBERS rise, median dy %s" % my)
			"down":
				_check(my > 1.5, "FROST falls, median dy %s" % my)
			"still":
				_check(absf(mx) < 0.001 and absf(my) < 0.001, "GLINT never moves, median %s, %s" % [mx, my])
		host.queue_free()

	# Alpha is 0 at birth and at death, and within the kind's strength in between.
	for kind in [1, 2, 3, 4, 5]:
		var node = AmbienceScript.new()
		node.kind = kind
		var born := {age = 0.0, life = 5.0, phase = 0.0}
		var dying := {age = 5.0, life = 5.0, phase = 0.0}
		var mid := {age = 2.5, life = 5.0, phase = 0.0}
		_check(node.alpha_of(born) == 0.0 and is_zero_approx(node.alpha_of(dying)), "kind %d: alpha 0 at birth and death" % kind)
		_check(node.alpha_of(mid) > 0.2 and node.alpha_of(mid) <= 0.91, "kind %d: alpha %s in the middle" % [kind, node.alpha_of(mid)])
		node.free()

	# The ten map files carry the table of 3.1.
	for id in TABLE:
		var t = load("res://content/maps/%s/map.tres" % id)
		var row: Array = TABLE[id]
		_check(t != null and t.ambience_kind == row[0] and t.ambience_color.is_equal_approx(row[1]) and t.ambience_count == row[2],
			"%s carries its ambience (kind %s, count %s)" % [id, t.ambience_kind if t else "?", t.ambience_count if t else "?"])
	_check(TABLE.size() == DirAccess.get_directories_at("res://content/maps").size(), "the table covers every map folder")

	# A run has one, apart from the Effects bits.
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await _frames(5)
	var amb = main.get_node_or_null("World/Ambience")
	_check(amb != null and amb.motes().size() == 40 and amb.z_index == 4, "the run has a default dust Ambience at z 4")
	var fx = get_nodes_in_group(&"effects")[0]
	_check(fx._bits.is_empty() and amb.get_parent() != fx, "ambience does not use the Effects bits")
	main.queue_free()
	await process_frame

	# The hub has the default dust.
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await _frames(5)
	var hub_amb = hub.get_node_or_null("World/Ambience")
	_check(hub_amb != null and hub_amb.motes().size() == 40 and hub_amb.kind == 1, "the hub has the default dust")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

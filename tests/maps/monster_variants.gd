extends SceneTree
## Monster variants (spec 0.6 section 7.6): a variant for every enemy type on every map, the same behaviour under
## every theme (and a guard that MonsterVariant has no field beyond the appearance ones), and the look applied to
## the sprite of a spawned enemy, the death puff and the hub dummies. Readability against the floor and between
## types (7.4) is checked in map_themes.gd.
## Run: godot --headless --path . --script tests/maps/monster_variants.gd

const Registry := preload("res://scripts/maps/map_registry.gd")
const VariantScript := preload("res://scripts/maps/monster_variant.gd")
const SpriteScript := preload("res://scripts/player/placeholder_sprite.gd")
const ROOT := "res://content/maps/"
const ENEMY_DIR := "res://data/enemies/"
## The six appearance fields of 7.2. A new field here needs its own rule in the spec (7.7) and this list updated.
const APPEARANCE_FIELDS := ["enemy_id", "body_color", "outline_color", "eye_color", "mark", "mark_color"]
## EnemyData fields that make up an enemy's behaviour.
const BEHAVIOUR_FIELDS := ["max_health", "speed", "contact_damage", "contact_interval", "xp_drop", "hitbox_radius",
	"body_size", "immovable"]

var _failed := false
var _fails_logged := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		_fails_logged += 1
		if _fails_logged <= 20:
			print("FAIL: ", what)


func _enemy_types() -> Array:
	var out: Array = []
	for file in DirAccess.get_files_at(ENEMY_DIR):
		if file.ends_with(".tres"):
			var data = load(ENEMY_DIR + file)
			if data != null and not data.immovable:
				out.append(data)
	return out


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


## What an enemy of `type` does, read from the live enemy built by the director.
func _behaviour(e: Node, type: Object) -> Dictionary:
	e.activate(Vector2(400, 300), 1.0)
	var d := {data = e.data, brain = e.brain.get_script(), hp = e.health.max_health,
		radius = (e.get_node("Hitbox/CollisionShape2D").shape as CircleShape2D).radius,
		weight = type.weight_at(300.0), unlock = type.get("unlock_time")}
	for f in BEHAVIOUR_FIELDS:
		d[f] = e.data.get(f)
	return d


func _init() -> void:
	await process_frame
	await process_frame
	var types := _enemy_types()
	var ids: Array = types.map(func(t: Object) -> String: return String(t.id))
	ids.sort()
	_check(ids == ["dasher", "grunt", "ranged"], "the director's enemy types are grunt, ranged, dasher: %s" % [ids])
	var themes: Array = Registry.all()
	_check(themes.size() == 8, "eight maps")

	# --- Coverage ---
	for theme in themes:
		var on_disk: Array = []
		for file in DirAccess.get_files_at(ROOT + String(theme.id) + "/monsters/"):
			if file.ends_with(".tres"):
				on_disk.append(file.get_basename())
		on_disk.sort()
		_check(on_disk == ids, "%s: monster files %s, expected %s" % [theme.id, on_disk, ids])
		_check(theme.monsters.size() == ids.size(), "%s: one variant per enemy type" % theme.id)
		for id in ids:
			var v = theme.variant_for(StringName(id))
			_check(v != null, "%s: variant for %s" % [theme.id, id])
			if v != null:
				_check(String(v.enemy_id) == id, "%s: enemy_id %s equals its file name %s" % [theme.id, v.enemy_id, id])
		for v in theme.monsters:
			_check(String(v.enemy_id) in ids, "%s: variant for an unknown type %s" % [theme.id, v.enemy_id])
		_check(theme.variant_for(&"no_such_enemy") == null, "variant_for an unknown id is null")

	# --- The guard: a variant resource is appearance only ---
	var fields: Array = []
	for p in VariantScript.new().get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (p.usage & PROPERTY_USAGE_STORAGE) != 0:
			fields.append(String(p.name))
	fields.sort()
	var expected := APPEARANCE_FIELDS.duplicate()
	expected.sort()
	_check(fields == expected, "MonsterVariant fields %s, expected only %s (gameplay fields need a rule: spec 7.7)" % [fields, expected])
	for n in SpriteScript.Mark.keys():
		_check(VariantScript.Mark.has(n) and VariantScript.Mark[n] == SpriteScript.Mark[n], "sprite and variant marks agree on %s" % n)

	# --- Same behaviour, and applied, under every theme ---
	var base_main := await _run_with(null)
	var base: Dictionary = {}
	var base_sprite: Dictionary = {}
	for type in types:
		var e: Node = base_main.spawn_director._acquire(type)
		base[type.id] = _behaviour(e, type)
		base_sprite[type.id] = [e.sprite.body_color, e.sprite.outline_color, e.sprite.eye_color, e.sprite.mark]
		_check(e.sprite.body_color == type.body_color and e.sprite.mark == 0 and e.sprite.outline_color.a == 0.0
			and e.sprite.eye_color == Color.WHITE, "default theme: %s keeps today's look" % type.id)
	await _end_run(base_main)

	for theme in themes:
		var main := await _run_with(theme)
		for type in types:
			var v = theme.variant_for(type.id)
			var data_before: Dictionary = {}
			for f in BEHAVIOUR_FIELDS:
				data_before[f] = type.get(f)
			var body_before: Color = type.body_color
			var e: Node = main.spawn_director._acquire(type)
			var b := _behaviour(e, type)
			for k in b:
				_check(b[k] == base[type.id][k], "%s %s: %s differs from the default theme" % [theme.id, type.id, k])
			for f in BEHAVIOUR_FIELDS:
				_check(type.get(f) == data_before[f], "%s %s: EnemyData.%s changed" % [theme.id, type.id, f])
			_check(type.body_color == body_before, "%s %s: EnemyData.body_color changed" % [theme.id, type.id])
			# applied to the sprite
			var s: Node = e.sprite
			_check(s.body_color == v.body_color and s.outline_color == v.outline_color and s.eye_color == v.eye_color
				and s.mark == int(v.mark) and s.mark_color == v.mark_color, "%s %s: sprite shows the variant" % [theme.id, type.id])
			_check(s.mark != 0, "%s %s: carries a mark" % [theme.id, type.id])
			# danger signals are not themed
			_check(s.warn_color == SpriteScript.new().warn_color, "%s %s: warn colour unchanged" % [theme.id, type.id])
			# the death puff takes the variant's body colour
			var fx: Node = e.get_tree().get_first_node_in_group(&"effects")
			fx._fx.clear()
			e.health.take_damage(1.0e9)
			var puffs: Array = fx._fx.filter(func(f: Dictionary) -> bool: return f.kind == &"puff")
			_check(puffs.size() == 1 and puffs[0].color == v.body_color, "%s %s: death puff uses the variant body colour" % [theme.id, type.id])
		await _end_run(main)

	# A theme without a variant for a type (and a null variant) leaves the enemy as it is.
	var bare := Registry.all()[0].duplicate()
	bare.monsters = Array([], TYPE_OBJECT, &"Resource", VariantScript)
	var main := await _run_with(bare)
	var g: Node = main.spawn_director._acquire(types[0])
	_check(g.sprite.body_color == types[0].body_color and g.sprite.mark == 0, "no variant: today's look")
	g.apply_variant(null)
	_check(g.sprite.body_color == types[0].body_color, "apply_variant(null) changes nothing")
	await _end_run(main)

	# The hub dummies are not dressed.
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	for i in 10:
		await physics_frame
	var dummies: Array = hub.get_node("World/Dummies").get_children()
	_check(dummies.size() == 3, "hub has its dummies")
	for d in dummies:
		_check(d.sprite.mark == 0 and d.sprite.outline_color.a == 0.0 and d.sprite.body_color == d.data.body_color,
			"hub dummy keeps today's look")
	hub.queue_free()
	await process_frame

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

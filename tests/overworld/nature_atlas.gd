extends SceneTree
## The nature atlases and their manifest (spec 1.7 section 2): every region inside its atlas and not empty, every anchor inside
## its region, entries do not overlap, the tag counts the layout needs, a positive scale per kind, and `NatureSprites` serving
## the same numbers.
## Run: godot --headless --path . --script tests/overworld/nature_atlas.gd

const NatureSpritesS := preload("res://scripts/overworld/nature_sprites.gd")

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://content/overworld/nature/sprites.json"))
	_check(data is Dictionary, "the manifest parses")
	if data is Dictionary:
		for kind in ["trees", "rocks", "shrubs"]:
			_kind(data, kind)
		_counts(data)
		_api(data)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _kind(data: Dictionary, kind: String) -> void:
	_check(float(data.get("scales", {}).get(kind, 0.0)) > 0.0, kind + ": a positive scale")
	var tex: Texture2D = load("res://assets/nature/%s.png" % kind)
	_check(tex != null, kind + ": the atlas loads")
	if tex == null:
		return
	var img := tex.get_image()
	var list: Array = data[kind]
	var ids := {}
	var rects: Array[Rect2i] = []
	for e in list:
		var id: String = e["id"]
		_check(not ids.has(id), "%s: unique id %s" % [kind, id])
		ids[id] = true
		var r: Array = e["region"]
		var rect := Rect2i(r[0], r[1], r[2], r[3])
		_check(rect.size.x > 0 and rect.size.y > 0, id + ": a non-empty region")
		_check(Rect2i(Vector2i.ZERO, img.get_size()).encloses(rect), id + ": the region is inside the atlas")
		var a: Array = e["anchor"]
		_check(a[0] >= 0 and a[0] < rect.size.x and a[1] >= 0 and a[1] < rect.size.y, id + ": the anchor is inside the region")
		_check(not (e["tags"] as Array).is_empty(), id + ": has tags")
		for o in rects:
			_check(not o.intersects(rect), id + ": the region overlaps no other")
		rects.append(rect)
		if Rect2i(Vector2i.ZERO, img.get_size()).encloses(rect):
			var opaque := 0
			for y in rect.size.y:
				for x in rect.size.x:
					if img.get_pixel(rect.position.x + x, rect.position.y + y).a > 0.0:
						opaque += 1
			_check(opaque > 0, id + ": the region has opaque pixels")
			# the anchor row is the sprite's last row: it has opaque pixels (the foot rests on the ground)
			var foot_opaque := false
			for x in rect.size.x:
				if img.get_pixel(rect.position.x + x, rect.position.y + a[1]).a > 0.0:
					foot_opaque = true
			_check(foot_opaque, id + ": the anchor row has opaque pixels")


func _count(data: Dictionary, kind: String, tag: String) -> int:
	var n := 0
	for e in data[kind]:
		if tag in e["tags"]:
			n += 1
	return n


func _counts(data: Dictionary) -> void:
	_check((data["trees"] as Array).size() >= 20, "at least 20 trees")
	_check(_count(data, "trees", "green") >= 8, "at least 8 green trees")
	_check(_count(data, "trees", "fir") >= 2, "at least 2 firs")
	_check(_count(data, "trees", "autumn") >= 3, "at least 3 autumn trees")
	_check(_count(data, "trees", "tall") >= 1 and _count(data, "trees", "short") >= 1, "tall and short trees")
	for tag in ["pebbles", "small", "big", "pile_pebbles"]:
		_check(_count(data, "rocks", tag) >= 8, "at least 8 rocks tagged " + tag)
	_check((data["shrubs"] as Array).size() >= 15, "at least 15 shrubs")
	for tag in ["small", "wide", "green", "yellowish", "yellow"]:
		_check(_count(data, "shrubs", tag) >= 1, "a shrub tagged " + tag)


func _api(data: Dictionary) -> void:
	for kind in ["trees", "rocks", "shrubs"]:
		_check(NatureSpritesS.count(kind) == (data[kind] as Array).size(), kind + ": count matches")
		_check(NatureSpritesS.texture(kind) != null, kind + ": texture")
		_check(is_equal_approx(NatureSpritesS.scale(kind), float(data["scales"][kind])), kind + ": scale")
		var last: int = (data[kind] as Array).size() - 1
		var r: Array = data[kind][last]["region"]
		_check(NatureSpritesS.region(kind, last) == Rect2(r[0], r[1], r[2], r[3]), kind + ": region")
		var a: Array = data[kind][last]["anchor"]
		_check(NatureSpritesS.anchor(kind, last) == Vector2(a[0], a[1]), kind + ": anchor")
	var firs: Array[int] = NatureSpritesS.indices_with_tag("trees", "fir")
	_check(firs.size() == _count(data, "trees", "fir"), "indices_with_tag finds the firs")
	for i in firs:
		_check(NatureSpritesS.has_tag("trees", i, "fir"), "a fir index carries the tag")
	_check(NatureSpritesS.indices_with_tag("rocks", "no_such_tag").is_empty(), "an unknown tag lists nothing")

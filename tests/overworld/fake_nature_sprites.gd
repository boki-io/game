extends RefCounted
## A stand-in for NatureSprites in the layout tests: the same three methods the layout reads (`count`, `indices_with_tag`,
## `size_px`), with plausible tags and drawn sizes, so the layout is testable without the atlas.

var _tags := {&"tree": [], &"rock": [], &"shrub": []}
var _sizes := {&"tree": [], &"rock": [], &"shrub": []}


func _init() -> void:
	for i in 24:
		var t: Array = ["green"] if i < 12 else (["fir"] if i < 16 else ["autumn"])
		var tall := i % 3 == 0
		t.append("tall" if tall else "short")
		_add(&"tree", t, Vector2(36 + i % 5 * 6, 66 if tall else 34 + i % 4 * 4))
	for i in 12:
		var t: Array = ["pebbles"] if i < 3 else (["small"] if i < 8 else ["big"])
		if i in [1, 2]:
			t.append("pile_pebbles")
		var w := 14.0 if i < 3 else (24.0 if i < 8 else 38.0)
		_add(&"rock", t, Vector2(w, 12.0 + i))
	for i in 20:
		var colour := "green" if i < 10 else ("yellowish" if i < 18 else "yellow")
		_add(&"shrub", [colour, "small" if i % 2 == 0 else "wide"], Vector2(20 + i % 2 * 20, 14))


func _add(kind: StringName, tags: Array, size: Vector2) -> void:
	_tags[kind].append(tags)
	_sizes[kind].append(size)


func count(kind: StringName) -> int:
	return _tags[kind].size()


func indices_with_tag(kind: StringName, tag: String) -> Array:
	var out := []
	for i in _tags[kind].size():
		if tag in _tags[kind][i]:
			out.append(i)
	return out


func size_px(kind: StringName, i: int) -> Vector2:
	return _sizes[kind][i]

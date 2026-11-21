class_name NatureSprites
extends RefCounted
## The nature props' art (spec 1.7): the three atlases (`assets/nature/trees.png`, `rocks.png`, `shrubs.png`) and their manifest
## (`content/overworld/nature/sprites.json`, written by `tools/overworld/build_nature_atlas.py`). Loaded once, on first use, and
## shared. Atlases are pre-scaled by the tool, so regions and anchors are in atlas pixels and a sprite is drawn at scale 1.
## A kind is "trees", "rocks" or "shrubs"; a sprite is an index into that kind's manifest list.

const KINDS: Array[String] = ["trees", "rocks", "shrubs"]
const MANIFEST := "res://content/overworld/nature/sprites.json"
const ATLAS := "res://assets/nature/%s.png"

## The layout names kinds in the singular (`NatureLayout.KIND_*`); the manifest and the atlases in the plural.
const _PLURAL := {"tree": "trees", "rock": "rocks", "shrub": "shrubs"}

static var _loaded := false
static var _textures := {}  # kind -> Texture2D
static var _entries := {}  # kind -> Array of manifest entries
static var _scales := {}  # kind -> float
static var _tag_lists := {}  # "kind/tag" -> Array[int]


static func _load() -> void:
	if _loaded:
		return
	var text := FileAccess.get_file_as_string(MANIFEST)
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("NatureSprites: cannot read " + MANIFEST)
		return
	for kind in KINDS:
		_entries[kind] = data.get(kind, [])
		_scales[kind] = float(data.get("scales", {}).get(kind, 1.0))
		_textures[kind] = load(ATLAS % kind)
	_loaded = true


static func _k(kind) -> String:
	var k := String(kind)
	return _PLURAL.get(k, k)


## The number of sprites of a kind.
static func count(kind: String) -> int:
	kind = _k(kind)
	_load()
	return (_entries.get(kind, []) as Array).size()


## The sprite's rectangle in its atlas, for `Sprite2D.region_rect`.
static func region(kind: String, i: int) -> Rect2:
	kind = _k(kind)
	_load()
	var r: Array = _entries[kind][i]["region"]
	return Rect2(r[0], r[1], r[2], r[3])


## The sprite's drawn size in pixels (its region size: the atlas is pre-scaled).
static func size_px(kind: String, i: int) -> Vector2:
	kind = _k(kind)
	return region(kind, i).size


## The sprite's base point inside its region (the trunk foot of a tree, the bottom centre of a rock or shrub), in atlas pixels.
static func anchor(kind: String, i: int) -> Vector2:
	kind = _k(kind)
	_load()
	var a: Array = _entries[kind][i]["anchor"]
	return Vector2(a[0], a[1])


static func sprite_id(kind: String, i: int) -> String:
	kind = _k(kind)
	_load()
	return _entries[kind][i]["id"]


static func tags(kind: String, i: int) -> Array:
	kind = _k(kind)
	_load()
	return _entries[kind][i]["tags"]


static func has_tag(kind: String, i: int, tag: String) -> bool:
	kind = _k(kind)
	return tag in tags(kind, i)


## The atlas texture of a kind.
static func texture(kind: String) -> Texture2D:
	kind = _k(kind)
	_load()
	return _textures[kind]


## The factor the tool scaled the source art by (0.4 for trees); informational, nothing is scaled at runtime.
static func scale(kind: String) -> float:
	kind = _k(kind)
	_load()
	return _scales[kind]


## The indices of a kind's sprites that carry a tag, in manifest order.
static func indices_with_tag(kind: String, tag: String) -> Array[int]:
	kind = _k(kind)
	_load()
	var key := kind + "/" + tag
	if not _tag_lists.has(key):
		var out: Array[int] = []
		var list: Array = _entries[kind]
		for i in list.size():
			if tag in list[i]["tags"]:
				out.append(i)
		_tag_lists[key] = out
	return _tag_lists[key]

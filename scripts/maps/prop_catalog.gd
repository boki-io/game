class_name PropCatalog
extends Resource
## Every sprite prop and the sheet they are cut from (test-props). One file: content/props/catalog.tres.

const PATH := "res://content/props/catalog.tres"

@export var sheet: Texture2D
@export var props: Array[PropData] = []

static var _shared: PropCatalog


## The catalog, loaded once.
static func get_shared() -> PropCatalog:
	if _shared == null:
		_shared = load(PATH)
	return _shared


## The props of `group`, in file order.
func in_group(group: StringName) -> Array[PropData]:
	var out: Array[PropData] = []
	for p in props:
		if p.group == group:
			out.append(p)
	return out


## The prop named `id`, or null.
func find(id: StringName) -> PropData:
	for p in props:
		if p.id == id:
			return p
	return null

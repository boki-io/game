class_name ItemRegistry
extends RefCounted
## All items. Paths are listed explicitly so exported builds find them (as AttributeRegistry does). No item ships in
## spec 1.4: the list is empty and the next PR fills it.

const PATHS: Array[String] = []

## Tests put items here; while it is not empty, all() returns it instead of loading PATHS. Reset it to [] afterwards.
static var test_items: Array[ItemData] = []


static func all() -> Array[ItemData]:
	if not test_items.is_empty():
		return test_items
	var out: Array[ItemData] = []
	for path: String in PATHS:
		out.append(load(path))
	return out


## The item with this id, or null.
static func find(id: StringName) -> ItemData:
	for item in all():
		if item.id == id:
			return item
	return null

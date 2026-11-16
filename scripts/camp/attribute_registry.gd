class_name AttributeRegistry
extends RefCounted
## All camp attributes, in camp screen order. Paths are listed explicitly so exported builds find them.

const PATHS := [
	"res://data/attributes/toughness.tres",
	"res://data/attributes/recovery.tres",
	"res://data/attributes/might.tres",
	"res://data/attributes/fury.tres",
	"res://data/attributes/haste.tres",
	"res://data/attributes/agility.tres",
	"res://data/attributes/focus.tres",
	"res://data/attributes/greed.tres",
]


static func all() -> Array[AttributeData]:
	var out: Array[AttributeData] = []
	for path: String in PATHS:
		out.append(load(path))
	return out


## The attribute with this id, or null.
static func find(id: StringName) -> AttributeData:
	for a in all():
		if a.id == id:
			return a
	return null

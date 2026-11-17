class_name AttributeRegistry
extends RefCounted
## All camp attributes, in camp screen order. Paths are listed explicitly so exported builds find them.

const PATHS := [
	"res://content/attributes/toughness.tres",
	"res://content/attributes/recovery.tres",
	"res://content/attributes/might.tres",
	"res://content/attributes/fury.tres",
	"res://content/attributes/haste.tres",
	"res://content/attributes/agility.tres",
	"res://content/attributes/focus.tres",
	"res://content/attributes/greed.tres",
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

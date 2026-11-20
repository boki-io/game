class_name ItemRegistry
extends RefCounted
## All items (spec 1.5: 18, three per type in the ratings standard, epic, legendary). Paths are listed explicitly so
## exported builds find them (as AttributeRegistry does), by type in screen order.

const PATHS: Array[String] = [
	"res://content/items/leather_cap/item.tres",
	"res://content/items/warden_helm/item.tres",
	"res://content/items/stormcaller_crown/item.tres",
	"res://content/items/padded_vest/item.tres",
	"res://content/items/reinforced_mail/item.tres",
	"res://content/items/thornmail/item.tres",
	"res://content/items/bone_charm/item.tres",
	"res://content/items/amber_pendant/item.tres",
	"res://content/items/frostfall_pendant/item.tres",
	"res://content/items/copper_ring/item.tres",
	"res://content/items/silver_ring/item.tres",
	"res://content/items/ring_of_mastery/item.tres",
	"res://content/items/cloth_trousers/item.tres",
	"res://content/items/hardened_greaves/item.tres",
	"res://content/items/tidewalker_greaves/item.tres",
	"res://content/items/worn_boots/item.tres",
	"res://content/items/swift_boots/item.tres",
	"res://content/items/emberstep_boots/item.tres",
]

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

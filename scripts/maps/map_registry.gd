class_name MapRegistry
extends RefCounted
## All playable maps. Ids are listed explicitly so exported builds find them (a build cannot list a directory);
## tests/maps/map_content.gd checks the list against content/maps/ on disk. Adding a map: a folder and one id here.

const FOLDER := "res://content/maps/%s/map.tres"
const DEFAULT_ID := "_default"
## In the order of the v0.5 names and thumbnails (stage_0 .. stage_7).
const IDS := [
	"mossy_hollow", "crystal_vault", "ember_depths", "frostbite_grotto", "spore_cavern",
	"bone_warren", "flooded_gallery", "sulfur_pits",
]


## The loaded themes of the playable maps, in list order. Never includes the default or the template.
static func all() -> Array[MapTheme]:
	var out: Array[MapTheme] = []
	for id: String in IDS:
		out.append(load(FOLDER % id))
	return out


## The theme with this id (a playable map or the default), or null.
static func by_id(id: StringName) -> MapTheme:
	if String(id) != DEFAULT_ID and not IDS.has(String(id)):
		return null
	return load(FOLDER % String(id))


## Today's cave: used when no stage is set (editor runs, most tests).
static func default() -> MapTheme:
	return load(FOLDER % DEFAULT_ID)

class_name RelicRegistry
extends RefCounted
## All relics. Paths are listed explicitly so exported builds find them.

const PATHS := [
	"res://data/relics/tidal_wave.tres",
	"res://data/relics/frost_comet.tres",
	"res://data/relics/thorn_nova.tres",
	"res://data/relics/storm_orbs.tres",
	"res://data/relics/fire_trail.tres",
]


static func all() -> Array[RelicData]:
	var out: Array[RelicData] = []
	for path: String in PATHS:
		out.append(load(path))
	return out


## The relic with this id, or null.
static func find(id: StringName) -> RelicData:
	for r in all():
		if r.id == id:
			return r
	return null

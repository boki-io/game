class_name RelicRegistry
extends RefCounted
## All relics. Paths are listed explicitly so exported builds find them.

const PATHS := [
	"res://content/relics/tidal_wave/relic.tres",
	"res://content/relics/frost_comet/relic.tres",
	"res://content/relics/thorn_nova/relic.tres",
	"res://content/relics/storm_orbs/relic.tres",
	"res://content/relics/fire_trail/relic.tres",
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

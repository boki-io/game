class_name UpgradePool
extends RefCounted
## The Sword's upgrade pool. Paths are listed explicitly so exported builds find them.

const SWORD := [
	"res://data/upgrades/slash_arc.tres",
	"res://data/upgrades/slash_speed.tres",
	"res://data/upgrades/slash_damage.tres",
	"res://data/upgrades/dash_range.tres",
	"res://data/upgrades/dash_trail.tres",
	"res://data/upgrades/dash_efficient.tres",
	"res://data/upgrades/spin_double.tres",
	"res://data/upgrades/spin_wide.tres",
	"res://data/upgrades/spin_cyclone.tres",
	"res://data/upgrades/slam_shockwave.tres",
	"res://data/upgrades/slam_stun.tres",
	"res://data/upgrades/slam_damage.tres",
	"res://data/upgrades/max_hp.tres",
	"res://data/upgrades/mana_regen.tres",
	"res://data/upgrades/max_mana.tres",
	"res://data/upgrades/move_speed.tres",
	"res://data/upgrades/pickup_radius.tres",
	"res://data/upgrades/damage.tres",
]


static func sword() -> Array[UpgradeData]:
	var pool: Array[UpgradeData] = []
	for path: String in SWORD:
		pool.append(load(path))
	return pool

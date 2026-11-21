class_name DungeonRules
extends Resource
## The tuning of caves and dungeons played as arena stages (spec 1.6, section 10). Data: content/overworld/dungeon_rules.tres.
## The per-kind arrays are indexed cave 0, dungeon 1, final vault 2 (see kind_index). Modifiers are whole percentages, as
## StageData's are.

const KIND_NAMES: Array[String] = ["cave", "dungeon", "final_dungeon"]

## Stages per kind.
@export var stages := PackedInt32Array([1, 3, 3])
## Added to the zone's tier, then clamped to hard.
@export var tier_offset := PackedInt32Array([0, 1, 2])
@export var population_bonus := PackedInt32Array([0, 10, 20])
## Population and difficulty added per later stage.
@export var stage_step := PackedInt32Array([8, 8, 10])
## The base tier (StageData.Tier) of each zone 0 to 7.
@export var zone_tiers := PackedInt32Array([0, 0, 1, 1, 1, 1, 2, 2])
@export var population_per_zone := 4
@export var difficulty_per_zone := 3
@export var experience_per_zone := 3
@export var currency_per_zone := 2
## A cap on the final population modifier.
@export var max_population := 60


## 0 cave, 1 dungeon, 2 final vault; a marker kind that is none of them gives a cave.
static func kind_index(kind: String) -> int:
	return maxi(KIND_NAMES.find(kind), 0)


## The midpoint of PathGenerator.RANGES for `tier` and `key` (integer division, so toward zero).
static func midpoint(tier: int, key: String) -> int:
	var r: Array = PathGenerator.RANGES[tier][key]
	return (r[0] + r[1]) / 2


## The stages of the cave or dungeon `marker` (a markers.json entry): one StageData per stage, on the map of its `map_id`.
static func stages_for(marker: Dictionary, rules: DungeonRules) -> Array[StageData]:
	var k := kind_index(String(marker.get("kind", "cave")))
	var zone := clampi(int(marker.get("zone", 0)), 0, rules.zone_tiers.size() - 1)
	var tier := clampi(rules.zone_tiers[zone] + rules.tier_offset[k], StageData.Tier.EASY, StageData.Tier.HARD)
	var theme := MapRegistry.by_id(StringName(marker.get("map_id", "")))
	var count: int = rules.stages[k]
	var out: Array[StageData] = []
	for n in count:
		var s := StageData.new()
		s.theme = theme
		s.tier = tier as StageData.Tier
		s.name = String(marker.get("name", "Cave")) + (" - stage %d" % (n + 1) if count > 1 else "")
		s.population = mini(midpoint(tier, "population") + rules.population_per_zone * zone + rules.population_bonus[k]
			+ rules.stage_step[k] * n, rules.max_population)
		s.difficulty = midpoint(tier, "difficulty") + rules.difficulty_per_zone * zone + rules.stage_step[k] * n
		s.experience = midpoint(tier, "experience") + rules.experience_per_zone * zone
		s.currency = midpoint(tier, "currency") + rules.currency_per_zone * zone
		out.append(s)
	return out

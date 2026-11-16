class_name PathGenerator
extends RefCounted
## Builds a run's path (3 + 3 + 1 stages) from a seed. Everything random (the middle stage's extra neighbour, tier
## order, rolled values, names and thumbnails) comes from ONE seeded RandomNumberGenerator, so a seed reproduces the
## whole path. A stage's name, thumbnail and look come from a MapTheme of the MapRegistry. Pure logic: no scene or
## autoload is touched.

const COLUMN_SIZES := [3, 3, 1]
const STEP := 5

## Ranges (min, max) per tier, in whole percent, rolled in steps of STEP. First guess: tune while playing.
const RANGES := {
	StageData.Tier.EASY: {population = [-20, -10], difficulty = [-10, -5], experience = [-15, -5], currency = [-5, 0]},
	StageData.Tier.NORMAL: {population = [-5, 5], difficulty = [-5, 5], experience = [0, 10], currency = [0, 5]},
	StageData.Tier.HARD: {population = [10, 20], difficulty = [5, 10], experience = [15, 30], currency = [10, 20]},
}


static func generate(path_seed: int) -> StagePath:
	var rng := RandomNumberGenerator.new()
	rng.seed = path_seed
	var path := StagePath.new()
	path.path_seed = path_seed

	# Edges. Top and bottom are fixed; the middle stage gets one random neighbour (top or bottom).
	var neighbour := 0 if rng.randi() % 2 == 0 else 2
	path.edges = [
		[[0, 1], [mini(1, neighbour), maxi(1, neighbour)], [1, 2]],
		[[0], [0], [0]],
	]

	var themes := MapRegistry.all()
	var order := _shuffled(themes.size(), rng)  # which map each stage gets
	var used := 0
	for column in COLUMN_SIZES.size():
		var tiers: Array = []
		if COLUMN_SIZES[column] == 1:
			tiers = [StageData.Tier.HARD]
		else:
			tiers = _shuffled_tiers(rng)
		var stages: Array = []
		for row in COLUMN_SIZES[column]:
			var stage := _roll_stage(tiers[row], rng)
			var theme: MapTheme = themes[order[used]]
			stage.theme = theme
			stage.name = theme.display_name
			stage.thumbnail = theme.thumbnail
			used += 1
			stages.append(stage)
		path.columns.append(stages)
	return path


static func _roll_stage(tier: StageData.Tier, rng: RandomNumberGenerator) -> StageData:
	var stage := StageData.new()
	stage.tier = tier
	var ranges: Dictionary = RANGES[tier]
	stage.population = _roll(ranges.population, rng)
	stage.difficulty = _roll(ranges.difficulty, rng)
	stage.experience = _roll(ranges.experience, rng)
	stage.currency = _roll(ranges.currency, rng)
	return stage


static func _roll(range_: Array, rng: RandomNumberGenerator) -> int:
	return range_[0] + STEP * rng.randi_range(0, (range_[1] - range_[0]) / STEP)


static func _shuffled_tiers(rng: RandomNumberGenerator) -> Array:
	var tiers: Array = [StageData.Tier.EASY, StageData.Tier.NORMAL, StageData.Tier.HARD]
	_shuffle(tiers, rng)
	return tiers


## 0..count-1 in a seeded random order.
static func _shuffled(count: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = range(count)
	_shuffle(out, rng)
	return out


## Fisher-Yates with the given rng (Array.shuffle() would use the global one and break seed reproducibility).
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp

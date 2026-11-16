class_name StageData
extends Resource
## One stage of a run's path. The arena (main.tscn) is reused; a stage only changes how it plays.
## Every modifier is a whole percentage ADDED to the base (0 = today's behaviour), never multiplied together.

enum Tier { EASY, NORMAL, HARD }

const TIER_NAMES := ["Easy", "Normal", "Hard"]
## Hard ceiling on the alive cap: the crowd performance budget.
const ALIVE_CAP_MAX := 300
## Base chance that a mob drops a coin (0..1). The stage's `currency` is added to it as percentage points.
const BASE_COIN_CHANCE := 0.25

@export var name := "Cave"
@export var thumbnail: Texture2D
@export var tier := Tier.NORMAL
## Spawn rate and alive cap change by this percent.
@export var population := 0
## Display only in v0.5: changes no gameplay.
@export var difficulty := 0
## XP from kills changes by this percent.
@export var experience := 0
## Percentage points added to the coin drop chance.
@export var currency := 0


func tier_name() -> String:
	return TIER_NAMES[tier]


## `base` changed by `percent` (+20 = 20% more).
static func add_percent(base: float, percent: int) -> float:
	return base * (1.0 + percent / 100.0)


## Spawn rate after the population modifier.
func scaled_rate(base: float) -> float:
	return add_percent(base, population)


## Alive cap after the population modifier, never above ALIVE_CAP_MAX.
func scaled_cap(base: int) -> int:
	return mini(roundi(add_percent(base, population)), ALIVE_CAP_MAX)


## Value of the XP gem a mob drops. A mob that drops no XP (xp_drop 0) stays at 0.
func scaled_xp(xp_drop: int) -> int:
	if xp_drop <= 0:
		return 0
	return maxi(1, roundi(add_percent(xp_drop, experience)))


## Chance (0..1) that a mob drops a coin: 25% plus the gold value in points, clamped.
func coin_chance() -> float:
	return clampf(BASE_COIN_CHANCE + currency / 100.0, 0.0, 1.0)

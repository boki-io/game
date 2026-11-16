class_name AttributeData
extends Resource
## One permanent attribute bought with gold at the camp (spec 0.7, section 3.4). Bonuses are linear in the level.

@export var id: StringName
@export var display_name := ""
## One line shown on the camp screen.
@export var description := ""
@export var max_level := 7
## Cost of level n is round(base_cost x cost_growth ^ (n - 1)).
@export var base_cost := 40
@export var cost_growth := 1.5
## Stats key -> amount per level (applied as amount x level).
@export var adds: Dictionary = {}
## Stats key -> fraction per level (applied as a multiplier 1 + fraction x level; negative for Haste).
@export var scales: Dictionary = {}
## Points of coin drop chance per level, as a fraction. Read by CampAttributes.coin_bonus, not written to Stats.
@export var coin_chance := 0.0
## Text with {0}, {1} placeholders, for example "+{0} max mana, +{1} mana/s".
@export var summary := ""
## The numbers for the placeholders, per level (positive; the sign is part of `summary`).
@export var display_values: Array[float] = []


## The text for `level`: `level x display_values` in the summary.
func describe(level: int) -> String:
	var args: Array[String] = []
	for v in display_values:
		args.append(_num(v * level))
	return summary.format(args)


## Same format as HubInfoPanel.num (no trailing zeros), copied so this resource has no UI or autoload dependency.
static func _num(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 2)

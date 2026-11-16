class_name CampShop
extends RefCounted
## Pure buy/undo/reset logic for camp attributes (spec 0.7, 5). No scene, no autoload.
## A state is a Dictionary {gold: int, levels: Dictionary (attribute id -> int)}; the functions change it in place.


static func make_state(gold: int, levels: Dictionary) -> Dictionary:
	return {gold = gold, levels = levels}


## The cost of buying level `level` (1 to max_level): round(base_cost x cost_growth ^ (level - 1)).
static func cost(attr: AttributeData, level: int) -> int:
	return roundi(attr.base_cost * pow(attr.cost_growth, level - 1))


static func level_of(state: Dictionary, attr: AttributeData) -> int:
	return clampi(int(state.levels.get(attr.id, 0)), 0, attr.max_level)


## The cost of the next level, or -1 at max level.
static func next_cost(state: Dictionary, attr: AttributeData) -> int:
	var level := level_of(state, attr)
	return -1 if level >= attr.max_level else cost(attr, level + 1)


static func can_buy(state: Dictionary, attr: AttributeData) -> bool:
	var price := next_cost(state, attr)
	return price >= 0 and state.gold >= price


static func buy(state: Dictionary, attr: AttributeData) -> bool:
	if not can_buy(state, attr):
		return false
	var level := level_of(state, attr)
	state.gold -= cost(attr, level + 1)
	state.levels[attr.id] = level + 1
	return true


## Lowers one level and refunds exactly the cost that level had.
static func undo(state: Dictionary, attr: AttributeData) -> bool:
	var level := level_of(state, attr)
	if level <= 0:
		return false
	state.gold += cost(attr, level)
	state.levels[attr.id] = level - 1
	return true


## Undoes every level of every attribute. Returns the refund.
static func reset_all(state: Dictionary) -> int:
	var refund := spent(state)
	state.gold += refund
	for a in AttributeRegistry.all():
		state.levels[a.id] = 0
	return refund


## Total gold sunk into the current levels.
static func spent(state: Dictionary) -> int:
	var total := 0
	for a in AttributeRegistry.all():
		for n in range(1, level_of(state, a) + 1):
			total += cost(a, n)
	return total

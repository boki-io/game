class_name Inventory
extends RefCounted
## The player's items (spec 1.4): the pool of unlocked item ids, shared by all characters, and one loadout per character
## (slot -> item id). An item is a single copy: it is worn by one character at a time. GameSession owns the instance and
## saves it (InventorySave); nothing in here reads an autoload.

signal changed

## The seven places, in screen order, and the six item types (a ring fits ring_1 or ring_2).
const SLOTS: Array[StringName] = [&"helmet", &"chestplate", &"necklace", &"ring_1", &"ring_2", &"pants", &"shoes"]
const TYPES: Array[StringName] = [&"helmet", &"chestplate", &"necklace", &"ring", &"pants", &"shoes"]

## Item ids in the order they were unlocked, no duplicates.
var unlocked: Array[StringName] = []
var _worn: Dictionary = {}  # character id -> {slot -> item id}


## The slots an item of this type can go in (empty for an unknown type).
static func slots_for(item_type: StringName) -> Array[StringName]:
	if item_type == &"ring":
		return [&"ring_1", &"ring_2"]
	if item_type in TYPES:
		return [item_type]
	return []


## Adds a known, not yet unlocked item to the pool.
func unlock(id: StringName) -> bool:
	if ItemRegistry.find(id) == null or id in unlocked:
		return false
	unlocked.append(id)
	changed.emit()
	return true


func is_unlocked(id: StringName) -> bool:
	return id in unlocked


## The item worn in `slot` by this character, or null.
func worn(character_id: StringName, slot: StringName) -> ItemData:
	var id: StringName = _loadout(character_id).get(slot, &"")
	return ItemRegistry.find(id) if id != &"" else null


## Everything this character wears, in slot order.
func worn_items(character_id: StringName) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for slot in SLOTS:
		var item := worn(character_id, slot)
		if item != null:
			out.append(item)
	return out


## The character wearing the item, or &"".
func wearer_of(id: StringName) -> StringName:
	for character_id in _worn:
		if id in _worn[character_id].values():
			return character_id
	return &""


## The slot of this character that holds the item, or &"".
func slot_of(character_id: StringName, id: StringName) -> StringName:
	var loadout := _loadout(character_id)
	for slot in loadout:
		if loadout[slot] == id:
			return slot
	return &""


## Wears an unlocked item and returns the slot used, or &"" when it cannot be worn (not unlocked, or `slot` does not
## fit it). Without `slot` it goes to the item's own slot; a ring takes the first free ring slot, or replaces ring_1
## when both are full. Re-equipping what this character already wears into the slot it holds changes nothing (and
## returns that slot). An item worn by another character is taken from them; whatever sat in the target slot goes back
## to the pool unworn.
func equip(character_id: StringName, id: StringName, slot: StringName = &"") -> StringName:
	var item := ItemRegistry.find(id)
	if item == null or not is_unlocked(id):
		return &""
	var allowed := slots_for(item.slot)
	var held := slot_of(character_id, id)
	var target := slot
	if target == &"":
		if held != &"":
			return held
		target = allowed[0] if not allowed.is_empty() else &""
		for candidate in allowed:
			if _loadout(character_id).get(candidate, &"") == &"":
				target = candidate
				break
	if target == &"" or not target in allowed:
		return &""
	if held == target:
		return target
	var other := wearer_of(id)
	if other != &"" and other != character_id:
		_loadout(other).erase(slot_of(other, id))
	if held != &"":
		_loadout(character_id).erase(held)
	_loadout(character_id)[target] = id
	changed.emit()
	return target


## Takes the item off; it stays in the pool. False when the slot was empty.
func unequip(character_id: StringName, slot: StringName) -> bool:
	var loadout := _loadout(character_id)
	if not loadout.has(slot):
		return false
	loadout.erase(slot)
	changed.emit()
	return true


## A copy of every loadout, for saving: {character id: {slot: item id}}.
func worn_state() -> Dictionary:
	var out := {}
	for character_id in _worn:
		if not _worn[character_id].is_empty():
			out[character_id] = _worn[character_id].duplicate()
	return out


## Replaces the contents without emitting `changed` (used by loading, which must not trigger a save).
func set_state(pool: Array, loadouts: Dictionary) -> void:
	unlocked.assign(pool)
	_worn = {}
	for character_id in loadouts:
		_worn[character_id] = loadouts[character_id].duplicate()


func _loadout(character_id: StringName) -> Dictionary:
	if not _worn.has(character_id):
		_worn[character_id] = {}
	return _worn[character_id]

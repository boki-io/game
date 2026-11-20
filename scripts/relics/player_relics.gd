class_name PlayerRelics
extends Node
## The relics a player carries (spec 1.0): up to `slots` (MAX_SLOTS, plus one per granted relic), each up to MAX_LEVEL. Each owned relic has one
## RelicBehavior child that does the work. Nothing is added in the hub, and behaviors stop while the player is dead.

const MAX_SLOTS := 4
const MAX_LEVEL := 3

## A relic was added or raised.
signal changed
## The slot (0 to slots - 1) the HUD should flash.
signal flashed(slot: int)

## id -> level. The insertion order is the slot order.
var levels: Dictionary = {}
var slots := MAX_SLOTS
## Relics given by worn legendary items (spec 1.5). Each one has its own extra slot, so free_slots() is unchanged by it.
var granted: Array[StringName] = []

var _behaviors: Dictionary = {}  # id -> RelicBehavior
var _stopped := false

@onready var player: Player = get_parent()


func _physics_process(_delta: float) -> void:
	var dead: bool = player.dead
	if dead == _stopped:
		return
	_stopped = dead
	for b: RelicBehavior in _behaviors.values():
		b.process_mode = Node.PROCESS_MODE_DISABLED if dead else Node.PROCESS_MODE_INHERIT


func free_slots() -> int:
	return slots - levels.size()


func owns(id: StringName) -> bool:
	return levels.has(id)


func level_of(data: RelicData) -> int:
	return levels.get(data.id, 0)


## The slot index of `id` (insertion order), or -1.
func slot_of(id: StringName) -> int:
	return levels.keys().find(id)


## The behavior node of an owned relic, or null.
func behavior_of(id: StringName) -> RelicBehavior:
	return _behaviors.get(id)


## Gives a relic for the whole run in an extra slot (a worn legendary item, spec 1.5). Returns false in the hub or
## when the relic is already owned.
func grant(data: RelicData) -> bool:
	if player.hub_mode or owns(data.id):
		return false
	slots += 1
	granted.append(data.id)
	return add_or_raise(data, false)


## Gives a new relic (level 1, first free slot) or raises an owned one. Returns false when nothing changed: the
## hub, no free slot, or a relic already at MAX_LEVEL. `flash` is false when restoring a saved run.
func add_or_raise(data: RelicData, flash := true) -> bool:
	if player.hub_mode:
		return false
	var current := level_of(data)
	if current >= MAX_LEVEL or (current == 0 and free_slots() <= 0):
		return false
	levels[data.id] = current + 1
	if current == 0:
		var b: RelicBehavior = data.behavior.new()
		b.name = String(data.id).to_pascal_case()
		b.player = player
		b.data = data
		_behaviors[data.id] = b
		if _stopped:
			b.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(b)
	_behaviors[data.id].set_level(current + 1)
	changed.emit()
	if flash:
		flashed.emit(slot_of(data.id))
	return true

class_name AbilityCaster
extends Node
## Owns cooldowns, checks mana, runs ability behaviors. One active cast at a time;
## the auto Slash holds off while a Q/E/R cast is running.

signal cast_started(slot: StringName, data: AbilityData)
## reason is &"mana", &"cooldown", &"no_target" (nothing to aim at) or &"blocked" (no room to move).
signal cast_failed(slot: StringName, reason: StringName)

const AUTO_TARGET_RANGE := 90.0
const INPUT_BUFFER := 0.15  # seconds a press is remembered while another cast is running
const CHAIN_WINDOW := 1.0  # seconds after a chained dash to cast the next one (Double Dash)

@export var ability_auto: AbilityData
@export var ability_q: AbilityData
@export var ability_e: AbilityData
@export var ability_r: AbilityData

var cooldowns: Dictionary = {&"auto": 0.0, &"q": 0.0, &"e": 0.0, &"r": 0.0}

var _active: AbilityBehavior
var _active_slot: StringName = &""
var _behaviors: Dictionary = {}  # slot -> AbilityBehavior
var _buffered_slot: StringName = &""
var _buffer_left := 0.0

# Chained casts (Double Dash): after the first cast, `_chain_remaining` free follow-ups can be cast
# while the window is open. The ability's cooldown is frozen until the chain ends.
var _chain_slot: StringName = &""
var _chain_remaining := 0
## True while a chained follow-up cast is being started (behaviors may use it).
var casting_follow_up := false
var _chain_window := 0.0

@onready var player: Player = get_parent()
@onready var stats: Stats = player.get_node("Stats")
@onready var mana: Mana = player.get_node("Mana")


func _ready() -> void:
	var input: PlayerInput = player.get_node("PlayerInput")
	input.ability_pressed.connect(_on_ability_pressed)


func is_busy() -> bool:
	return _active != null


## True while a follow-up cast for `slot` is available.
func chain_open(slot: StringName) -> bool:
	return _chain_slot == slot and _chain_window > 0.0 and _chain_remaining > 0


func chain_remaining(slot: StringName) -> int:
	return _chain_remaining if _chain_slot == slot else 0


func chain_window_fraction() -> float:
	return clampf(_chain_window / CHAIN_WINDOW, 0.0, 1.0)


## Stops the active cast and runs its cleanup (used on death).
func cancel() -> void:
	_end_chain()
	if _active:
		_active.finish()
		_active = null


func slot_data(slot: StringName) -> AbilityData:
	match slot:
		&"auto":
			return ability_auto
		&"q":
			return ability_q
		&"e":
			return ability_e
		&"r":
			return ability_r
	return null


## Modified stat for an ability, e.g. value(data, &"cooldown", data.cooldown).
func value(data: AbilityData, stat: StringName, base: float) -> float:
	return stats.value(StringName("%s.%s" % [data.id, stat]), base)


func play_sfx(data: AbilityData) -> void:
	Audio.play_stream(data.sfx)


func damage_of(data: AbilityData) -> float:
	return value(data, &"damage", data.damage) * stats.value(&"damage", 1.0)


func cooldown_of(data: AbilityData) -> float:
	return value(data, &"cooldown", data.cooldown)


func mana_cost_of(data: AbilityData) -> float:
	return maxf(value(data, &"mana_cost", data.mana_cost), 0.0)


func _physics_process(delta: float) -> void:
	if player.dead:
		return
	for slot: StringName in cooldowns:
		if slot != _chain_slot:  # a chained ability's cooldown starts when its chain ends
			cooldowns[slot] = maxf(cooldowns[slot] - delta, 0.0)

	if _chain_window > 0.0:
		_chain_window -= delta
		if _chain_window <= 0.0:
			_end_chain()

	if _active:
		if _active.update(delta):
			_finish_active()

	if _active == null:
		if _buffer_left > 0.0:
			_buffer_left -= delta
			if _buffer_left > 0.0:
				var slot := _buffered_slot
				_buffered_slot = &""
				_buffer_left = 0.0
				_try_cast(slot)
		if _active == null:
			_auto_cast()


func _on_ability_pressed(slot: StringName) -> void:
	if player.dead:
		return
	if _active:
		_buffered_slot = slot
		_buffer_left = INPUT_BUFFER
		return
	_try_cast(slot)


func _try_cast(slot: StringName) -> void:
	var data := slot_data(slot)
	if data == null or data.behavior == null:
		return
	if chain_open(slot):
		_cast_follow_up(slot, data)
		return
	if cooldowns[slot] > 0.0:
		cast_failed.emit(slot, &"cooldown")
		return
	var aim := player.player_input.aim_vector
	var behavior := _behavior_for(slot, data)
	if not behavior.can_cast(self, aim, data):
		cast_failed.emit(slot, behavior.fail_reason)
		return
	if not mana.can_afford(mana_cost_of(data)):
		cast_failed.emit(slot, &"mana")
		return
	_begin(slot, data, aim)


func _auto_cast() -> void:
	if ability_auto == null or cooldowns[&"auto"] > 0.0:
		return
	var reach := ability_auto.target_range if ability_auto.target_range > 0.0 else AUTO_TARGET_RANGE
	var target := EnemyGrid.nearest(player.global_position, reach)
	if target == null:
		return
	var to_target := target.global_position - player.global_position
	# An enemy standing on the player gives no direction: fall back to the aim.
	var dir := to_target.normalized() if to_target.length() >= 1.0 else player.player_input.aim_vector
	_begin(&"auto", ability_auto, dir)


func _behavior_for(slot: StringName, data: AbilityData) -> AbilityBehavior:
	if not _behaviors.has(slot):
		_behaviors[slot] = data.behavior.new()
	return _behaviors[slot]


func _begin(slot: StringName, data: AbilityData, aim: Vector2) -> void:
	var cost := mana_cost_of(data)
	if cost > 0.0:
		mana.spend(cost)
		var fx := Effects.get_for(self)
		if fx:
			fx.mana_number(player.global_position + Vector2(16, -22), cost)
	cooldowns[slot] = cooldown_of(data)
	var chain := int(value(data, &"chain", 0.0))
	if chain > 0:
		_chain_slot = slot
		_chain_remaining = chain
		_chain_window = 0.0
	player.face_towards(aim, 0.25)
	cast_started.emit(slot, data)
	var behavior := _behavior_for(slot, data)
	behavior.cast(self, aim, data)
	# Instant abilities finish in their first update; the rest keep the caster busy.
	_active = behavior
	_active_slot = slot
	if behavior.update(0.0):
		_finish_active()


## A follow-up in a chain: no mana, no cooldown check, re-aimed from the current aim.
func _cast_follow_up(slot: StringName, data: AbilityData) -> void:
	var aim := player.player_input.aim_vector
	var behavior := _behavior_for(slot, data)
	if not behavior.can_cast(self, aim, data):
		cast_failed.emit(slot, behavior.fail_reason)  # the chain stays open
		return
	_chain_remaining -= 1
	_chain_window = 0.0
	player.face_towards(aim, 0.25)
	cast_started.emit(slot, data)
	casting_follow_up = true
	behavior.cast(self, aim, data)
	casting_follow_up = false
	_active = behavior
	_active_slot = slot
	if behavior.update(0.0):
		_finish_active()


func _finish_active() -> void:
	_active.finish()
	_active = null
	if _chain_slot != &"" and _active_slot == _chain_slot:
		if _chain_remaining > 0:
			_chain_window = CHAIN_WINDOW
		else:
			_end_chain()


func _end_chain() -> void:
	_chain_slot = &""
	_chain_remaining = 0
	_chain_window = 0.0
